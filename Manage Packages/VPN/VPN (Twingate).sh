#!/bin/bash
#jsf_no_pause="1"


app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"


source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core
jsf_require_all --native curl jq

script_title="Twingate Travel Access"
twingate_dir="/etc/twingate"
twingate_key_path="$twingate_dir/service_key.json"
twingate_state_path="$twingate_dir/jsf-travel-access.json"
twingate_container_name="jsf-twingate-client"
twingate_runtime=""

pause_screen() {
    echo ""
    entertocontinue
}

run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "This action requires root privileges, but sudo is not available." >&2
        return 1
    fi
}

twingate_device_files_exist() {
    run_as_root test -r "$twingate_state_path" &&
        run_as_root test -r "$twingate_key_path"
}

require_twingate_device() {
    if ! twingate_device_files_exist; then
        echo "This computer has not been set up for Twingate Travel Access yet."
        return 1
    fi
}

require_twingate_runtime() {
    if command -v podman >/dev/null 2>&1; then
        twingate_runtime="podman"
        return 0
    fi

    if command -v docker >/dev/null 2>&1; then
        twingate_runtime="docker"
        return 0
    fi

    echo "Podman or Docker is required, but neither was found."
    echo "Install one container runtime with the dedicated JS-Forge installer, then try again."
    return 1
}

twingate_runtime_command() {
    run_as_root "$twingate_runtime" "$@"
}

read_twingate_state() {
    local state_json

    state_json="$(run_as_root cat "$twingate_state_path" 2>/dev/null)" || return 1
    twingate_tenant="$(printf '%s' "$state_json" | jq -r '.tenant // empty')"
    twingate_device_name="$(printf '%s' "$state_json" | jq -r '.deviceName // empty')"
    twingate_service_account_id="$(printf '%s' "$state_json" | jq -r '.serviceAccountId // empty')"
    twingate_service_key_id="$(printf '%s' "$state_json" | jq -r '.serviceKeyId // empty')"

    [ -n "$twingate_tenant" ] &&
        [ -n "$twingate_device_name" ] &&
        [ -n "$twingate_service_account_id" ] &&
        [ -n "$twingate_service_key_id" ]
}

prompt_tenant() {
    local value

    while true; do
        read -r -p "Twingate tenant name: " value
        value="${value#https://}"
        value="${value%%.twingate.com*}"
        case "$value" in
            ""|*[!A-Za-z0-9-]*) echo "Enter only the tenant subdomain, for example: my-company" ;;
            *) twingate_tenant="$value"; return 0 ;;
        esac
    done
}

prompt_admin_api_key() {
    local api_settings_url answer

    api_settings_url="https://${twingate_tenant}.twingate.com/settings/api"
    echo ""
    echo "Create or manage your Twingate Admin API key here:"
    echo "$api_settings_url"
    echo ""
    read -r -p "Open Twingate API settings now? [Y/n]: " answer
    case "$answer" in
        n|N|no|NO) ;;
        *) xdg-open "$api_settings_url" >/dev/null 2>&1 & ;;
    esac

    echo ""
    echo "Generate an API key, save it in your password manager,"
    echo "then return here and paste it at the hidden prompt."
    read -r -s -p "Enter Twingate Admin API key (input hidden): " twingate_admin_api_key
    printf '\n'

    [ -n "$twingate_admin_api_key" ] || {
        echo "No API key was entered."
        return 1
    }
}

prompt_key_expiration() {
    local value

    while true; do
        read -r -p "Key expiration in days, 0 for no expiration [0]: " value
        value="${value:-0}"
        case "$value" in
            ""|*[!0-9]*) echo "Enter a whole number from 0 through 365." ;;
            *)
                if [ "$value" -le 365 ]; then
                    twingate_key_expiration="$value"
                    return 0
                fi
                echo "Enter a whole number from 0 through 365."
                ;;
        esac
    done
}

twingate_api_call() {
    local query="$1" variables="$2" payload

    payload="$(jq -n --arg query "$query" --argjson variables "$variables" '{query: $query, variables: $variables}')" || return 1
    curl --silent --show-error --fail-with-body \
        --connect-timeout 15 --max-time 45 \
        -H "Content-Type: application/json" \
        -H "X-API-KEY: $twingate_admin_api_key" \
        --data "$payload" \
        "https://${twingate_tenant}.twingate.com/api/graphql/"
}

twingate_show_api_error() {
    local response="$1" message

    message="$(printf '%s' "$response" | jq -r '.errors[0].message // .data[]?.error // empty' 2>/dev/null)"
    if [ -n "$message" ]; then
        echo "Twingate API error: $message"
    else
        echo "Twingate did not return a usable response."
    fi
}

twingate_create_service_account() {
    local query variables response ok

    query='mutation serviceAccountCreate($name: String!, $resourceIds: [ID]) {
      serviceAccountCreate(name: $name, resourceIds: $resourceIds) {
        ok error entity { id name }
      }
    }'
    variables="$(jq -n --arg name "$twingate_device_name" '{name: $name, resourceIds: []}')"
    response="$(twingate_api_call "$query" "$variables")" || {
        echo "Unable to contact the Twingate API."
        return 1
    }
    ok="$(printf '%s' "$response" | jq -r '.data.serviceAccountCreate.ok // false')"
    [ "$ok" = "true" ] || { twingate_show_api_error "$response"; return 1; }

    twingate_service_account_id="$(printf '%s' "$response" | jq -r '.data.serviceAccountCreate.entity.id // empty')"
    [ -n "$twingate_service_account_id" ]
}

twingate_create_service_key() {
    local key_name="$1" query variables response ok

    query='mutation serviceAccountKeyCreate($expirationTime: Int!, $name: String, $serviceAccountId: ID!) {
      serviceAccountKeyCreate(expirationTime: $expirationTime, name: $name, serviceAccountId: $serviceAccountId) {
        ok error entity { id name } token
      }
    }'
    variables="$(jq -n \
        --argjson expirationTime "$twingate_key_expiration" \
        --arg name "$key_name" \
        --arg serviceAccountId "$twingate_service_account_id" \
        '{expirationTime: $expirationTime, name: $name, serviceAccountId: $serviceAccountId}')"
    response="$(twingate_api_call "$query" "$variables")" || {
        echo "Unable to contact the Twingate API."
        return 1
    }
    ok="$(printf '%s' "$response" | jq -r '.data.serviceAccountKeyCreate.ok // false')"
    [ "$ok" = "true" ] || { twingate_show_api_error "$response"; return 1; }

    twingate_service_key_id="$(printf '%s' "$response" | jq -r '.data.serviceAccountKeyCreate.entity.id // empty')"
    twingate_service_key_token="$(printf '%s' "$response" | jq -r '.data.serviceAccountKeyCreate.token // empty')"
    [ -n "$twingate_service_key_id" ] && [ -n "$twingate_service_key_token" ] || return 1

    if ! printf '%s' "$twingate_service_key_token" | jq -e 'type == "object"' >/dev/null 2>&1; then
        echo "The returned Service Key was not valid JSON; it was not written to disk."
        return 1
    fi
}

write_twingate_files() {
    local key_tmp state_tmp result

    key_tmp="$(mktemp)" || return 1
    state_tmp="$(mktemp)" || { rm -f "$key_tmp"; return 1; }

    printf '%s\n' "$twingate_service_key_token" > "$key_tmp"
    jq -n \
        --arg tenant "$twingate_tenant" \
        --arg deviceName "$twingate_device_name" \
        --arg serviceAccountId "$twingate_service_account_id" \
        --arg serviceKeyId "$twingate_service_key_id" \
        --arg updatedAt "$(date -u +%FT%TZ)" \
        '{tenant: $tenant, deviceName: $deviceName, serviceAccountId: $serviceAccountId, serviceKeyId: $serviceKeyId, updatedAt: $updatedAt}' > "$state_tmp"

    run_as_root install -d -m 700 "$twingate_dir" &&
        run_as_root install -o root -g root -m 600 "$key_tmp" "$twingate_key_path" &&
        run_as_root install -o root -g root -m 600 "$state_tmp" "$twingate_state_path"
    result=$?
    rm -f "$key_tmp" "$state_tmp"
    return "$result"
}

twingate_start_client() {
    require_twingate_runtime || return 1
    require_twingate_device || return 1

    twingate_runtime_command rm -f "$twingate_container_name" >/dev/null 2>&1 || true
    twingate_runtime_command run -d \
        --name "$twingate_container_name" \
        --network host \
        --device /dev/net/tun \
        --cap-add NET_ADMIN \
        -v "$twingate_key_path:/etc/twingate/service_key.json:ro" \
        twingate/client:latest || {
            echo "The Twingate Client container could not be started."
            return 1
        }
    echo "Twingate Client started with $twingate_runtime."
}

twingate_stop_client() {
    require_twingate_runtime || return 1
    if twingate_runtime_command stop "$twingate_container_name" >/dev/null 2>&1; then
        echo "Twingate Client stopped."
    else
        echo "No running Twingate Client container was found."
    fi
}

twingate_status() {
    require_twingate_runtime || return 1
    echo ""
    echo "Container runtime: $twingate_runtime"
    if twingate_device_files_exist && read_twingate_state; then
        echo "Tenant: $twingate_tenant"
        echo "Device identity: $twingate_device_name"
        echo "Service Account ID: $twingate_service_account_id"
        echo "Service Key file: present"
    else
        echo "Local device state: not configured"
    fi
    echo ""
    twingate_runtime_command ps -a --filter "name=^/${twingate_container_name}$" \
        --format 'Container: {{.Names}} | State: {{.State}} | Status: {{.Status}}' 2>/dev/null || true
}

twingate_logs() {
    require_twingate_runtime || return 1
    twingate_runtime_command logs --tail 80 "$twingate_container_name"
}

twingate_revoke_key() {
    local id="$1" query variables response ok

    query='mutation serviceAccountKeyRevoke($id: ID!) { serviceAccountKeyRevoke(id: $id) { ok error } }'
    variables="$(jq -n --arg id "$id" '{id: $id}')"
    response="$(twingate_api_call "$query" "$variables")" || return 1
    ok="$(printf '%s' "$response" | jq -r '.data.serviceAccountKeyRevoke.ok // false')"
    [ "$ok" = "true" ] || { twingate_show_api_error "$response"; return 1; }
}

twingate_delete_key() {
    local id="$1" query variables response ok

    query='mutation serviceAccountKeyDelete($id: ID!) { serviceAccountKeyDelete(id: $id) { ok error } }'
    variables="$(jq -n --arg id "$id" '{id: $id}')"
    response="$(twingate_api_call "$query" "$variables")" || return 1
    ok="$(printf '%s' "$response" | jq -r '.data.serviceAccountKeyDelete.ok // false')"
    [ "$ok" = "true" ] || { twingate_show_api_error "$response"; return 1; }
}

twingate_delete_service_account() {
    local id="$1" query variables response ok

    query='mutation serviceAccountDelete($id: ID!) { serviceAccountDelete(id: $id) { ok error } }'
    variables="$(jq -n --arg id "$id" '{id: $id}')"
    response="$(twingate_api_call "$query" "$variables")" || return 1
    ok="$(printf '%s' "$response" | jq -r '.data.serviceAccountDelete.ok // false')"
    [ "$ok" = "true" ] || { twingate_show_api_error "$response"; return 1; }
}

twingate_setup() {
    echo ""
    echo "$script_title — Set up this computer"
    divider
    require_twingate_runtime || return 1

    if twingate_device_files_exist; then
        echo "This computer already has local Twingate Travel Access files."
        echo "Use Replace device key or Remove this computer instead."
        return 1
    fi

    twingate_device_name="$(hostname)"
    [ -n "$twingate_device_name" ] || { echo "Unable to determine this computer's hostname."; return 1; }
    echo "Device identity: $twingate_device_name"

    prompt_tenant || return 1
    prompt_admin_api_key || return 1
    prompt_key_expiration || return 1

    echo "Creating the Twingate Service Account..."
    twingate_create_service_account || return 1
    echo "Creating the device Service Key..."
    if ! twingate_create_service_key "$twingate_device_name-key"; then
        echo "The Service Account was created, but no local key was saved."
        echo "Remote Service Account ID: $twingate_service_account_id"
        return 1
    fi
    write_twingate_files || {
        echo "The Service Key was created remotely but could not be saved locally."
        return 1
    }

    unset twingate_admin_api_key twingate_service_key_token
    echo "Starting the Twingate Client..."
    twingate_start_client || return 1
    echo ""
    echo "Twingate Travel Access is ready for: $twingate_device_name"
    echo "Assign the Resources this computer may access in Twingate Admin."
}

twingate_replace_key() {
    local old_key_id answer key_name

    require_twingate_device || return 1
    read_twingate_state || { echo "Local Twingate state is incomplete."; return 1; }
    echo "This creates a new device key, restarts the Client, then revokes the current key."
    read -r -p "Continue? [y/N]: " answer
    case "$answer" in y|Y|yes|YES) ;; *) return 0 ;; esac

    old_key_id="$twingate_service_key_id"
    prompt_admin_api_key || return 1
    prompt_key_expiration || return 1
    key_name="$twingate_device_name-key-$(date +%Y%m%d%H%M%S)"

    echo "Creating replacement Service Key..."
    twingate_create_service_key "$key_name" || return 1
    write_twingate_files || { echo "Replacement key could not be installed locally."; return 1; }
    echo "Restarting the Twingate Client with the replacement key..."
    twingate_start_client || return 1
    sleep 5
    echo "Revoking the previous Service Key..."
    twingate_revoke_key "$old_key_id" || {
        echo "The replacement key is installed, but the previous key was not revoked."
        echo "Revoke it in Twingate Admin: $old_key_id"
        return 1
    }
    unset twingate_admin_api_key twingate_service_key_token
    echo "Device key replaced successfully."
}

twingate_remove_device() {
    local answer

    require_twingate_device || return 1
    read_twingate_state || { echo "Local Twingate state is incomplete."; return 1; }
    echo "This stops the local Client, deletes its Service Key and Service Account,"
    echo "and removes local Twingate files."
    read -r -p "Type REMOVE to continue: " answer
    [ "$answer" = "REMOVE" ] || return 0

    prompt_admin_api_key || return 1
    require_twingate_runtime || return 1
    twingate_runtime_command rm -f "$twingate_container_name" >/dev/null 2>&1 || true
    echo "Revoking Service Key..."
    twingate_revoke_key "$twingate_service_key_id" || return 1
    echo "Deleting Service Key..."
    twingate_delete_key "$twingate_service_key_id" || return 1
    echo "Deleting Service Account..."
    twingate_delete_service_account "$twingate_service_account_id" || return 1
    run_as_root rm -f "$twingate_key_path" "$twingate_state_path" || return 1
    unset twingate_admin_api_key
    echo "Twingate Travel Access was removed from this computer."
}

twingate_open_admin() {
    if twingate_device_files_exist && read_twingate_state; then
        xdg-open "https://${twingate_tenant}.twingate.com/" >/dev/null 2>&1 &
    else
        prompt_tenant || return 1
        xdg-open "https://${twingate_tenant}.twingate.com/" >/dev/null 2>&1 &
    fi
}

twingate_menu() {
    local selection
    while true; do
        clear
        echo "$script_title"
        divider
        echo "1) Set up this computer"
        echo "2) Start connection"
        echo "3) Stop connection"
        echo "4) Check connection status"
        echo "5) View connection logs"
        echo "6) Replace device key"
        echo "7) Remove this computer"
        echo "8) Open Twingate Admin"
        echo "9) Exit"
        echo ""
        read -r -p "Select an option: " selection
        case "$selection" in
            1) twingate_setup; pause_screen ;;
            2) twingate_start_client; pause_screen ;;
            3) twingate_stop_client; pause_screen ;;
            4) twingate_status; pause_screen ;;
            5) twingate_logs; pause_screen ;;
            6) twingate_replace_key; pause_screen ;;
            7) twingate_remove_device; pause_screen ;;
            8) twingate_open_admin; pause_screen ;;
            9) return 0 ;;
            *) echo "Choose a number from 1 to 9."; sleep 1 ;;
        esac
    done
}

twingate_menu