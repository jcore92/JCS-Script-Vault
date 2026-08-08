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
twingate_last_error=""

pause_screen() { echo ""; entertocontinue; }

run_as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

twingate_device_files_exist() {
    run_as_root test -r "$twingate_key_path" && run_as_root test -r "$twingate_state_path"
}

require_twingate_device() {
    twingate_device_files_exist || { echo "This computer has not been set up for Twingate Travel Access yet."; return 1; }
}

require_twingate_runtime() {
    if command -v podman >/dev/null 2>&1; then twingate_runtime="podman"; return 0; fi
    if command -v docker >/dev/null 2>&1; then twingate_runtime="docker"; return 0; fi
    echo "Podman or Docker is required, but neither was found."
    echo "Install one container runtime with the dedicated JS-Forge installer, then try again."
    return 1
}

runtime_cmd() { run_as_root "$twingate_runtime" "$@"; }

read_twingate_state() {
    local state
    state="$(run_as_root cat "$twingate_state_path" 2>/dev/null)" || return 1
    twingate_tenant="$(printf '%s' "$state" | jq -r '.tenant // empty')"
    twingate_device_name="$(printf '%s' "$state" | jq -r '.deviceName // empty')"
    twingate_service_account_id="$(printf '%s' "$state" | jq -r '.serviceAccountId // empty')"
    twingate_service_key_id="$(printf '%s' "$state" | jq -r '.serviceKeyId // empty')"
    [ -n "$twingate_tenant" ] && [ -n "$twingate_device_name" ] && [ -n "$twingate_service_account_id" ] && [ -n "$twingate_service_key_id" ]
}

prompt_tenant() {
    local value
    while true; do
        read -r -p "Twingate tenant name: " value
        value="${value#https://}"; value="${value%%.twingate.com*}"
        case "$value" in ""|*[!A-Za-z0-9-]*) echo "Enter only the tenant subdomain, for example: my-company";; *) twingate_tenant="$value"; return 0;; esac
    done
}

prompt_admin_api_key() {
    local answer url
    url="https://${twingate_tenant}.twingate.com/settings/api"
    echo ""; echo "Create or manage your Twingate Admin API key here:"; echo "$url"; echo ""
    read -r -p "Open Twingate API settings now? [Y/n]: " answer
    case "$answer" in n|N|no|NO) ;; *) xdg-open "$url" >/dev/null 2>&1 &;; esac
    echo "Generate an API key, save it in your password manager, then return here."
    read -r -s -p "Enter Twingate Admin API key (input hidden): " twingate_admin_api_key
    printf '\n'
    [ -n "$twingate_admin_api_key" ] || { echo "No API key was entered."; return 1; }
}

prompt_key_expiration() {
    local value
    while true; do
        read -r -p "Key expiration in days, 0 for no expiration [0]: " value
        value="${value:-0}"
        case "$value" in *[!0-9]*|"") echo "Enter a whole number from 0 through 365.";; *) [ "$value" -le 365 ] && { twingate_key_expiration="$value"; return 0; }; echo "Enter a whole number from 0 through 365.";; esac
    done
}

api_call() {
    local query="$1" variables="$2" payload
    payload="$(jq -n --arg query "$query" --argjson variables "$variables" '{query:$query,variables:$variables}')" || return 1
    curl --silent --show-error --fail-with-body --connect-timeout 15 --max-time 45 \
        -H "Content-Type: application/json" -H "X-API-KEY: $twingate_admin_api_key" \
        --data "$payload" "https://${twingate_tenant}.twingate.com/api/graphql/"
}

api_error() {
    local response="$1"
    twingate_last_error="$(printf '%s' "$response" | jq -r '.errors[0].message // .data[]?.error // "Unknown Twingate API error"' 2>/dev/null)"
}

api_mutation() {
    local field="$1" query="$2" variables="$3" response ok
    response="$(api_call "$query" "$variables")" || { twingate_last_error="Unable to contact the Twingate API."; return 1; }
    ok="$(printf '%s' "$response" | jq -r ".data.${field}.ok // false")"
    [ "$ok" = "true" ] && { twingate_response="$response"; return 0; }
    api_error "$response"
    return 1
}

remote_missing_is_ok() {
    case "${twingate_last_error,,}" in *not\ found*|*does\ not\ exist*|*not\ exist*) return 0;; *) return 1;; esac
}

create_service_account() {
    local q v
    q='mutation serviceAccountCreate($name:String!,$resourceIds:[ID]){serviceAccountCreate(name:$name,resourceIds:$resourceIds){ok error entity{id name}}}'
    v="$(jq -n --arg name "$twingate_device_name" '{name:$name,resourceIds:[]}')"
    api_mutation serviceAccountCreate "$q" "$v" || { echo "Twingate API error: $twingate_last_error"; return 1; }
    twingate_service_account_id="$(printf '%s' "$twingate_response" | jq -r '.data.serviceAccountCreate.entity.id // empty')"
    [ -n "$twingate_service_account_id" ]
}

create_service_key() {
    local key_name="$1" q v
    q='mutation serviceAccountKeyCreate($expirationTime:Int!,$name:String,$serviceAccountId:ID!){serviceAccountKeyCreate(expirationTime:$expirationTime,name:$name,serviceAccountId:$serviceAccountId){ok error entity{id name} token}}'
    v="$(jq -n --argjson expirationTime "$twingate_key_expiration" --arg name "$key_name" --arg serviceAccountId "$twingate_service_account_id" '{expirationTime:$expirationTime,name:$name,serviceAccountId:$serviceAccountId}')"
    api_mutation serviceAccountKeyCreate "$q" "$v" || { echo "Twingate API error: $twingate_last_error"; return 1; }
    twingate_service_key_id="$(printf '%s' "$twingate_response" | jq -r '.data.serviceAccountKeyCreate.entity.id // empty')"
    twingate_service_key_token="$(printf '%s' "$twingate_response" | jq -r '.data.serviceAccountKeyCreate.token // empty')"
    [ -n "$twingate_service_key_id" ] && [ -n "$twingate_service_key_token" ] || return 1
    printf '%s' "$twingate_service_key_token" | jq -e 'type == "object"' >/dev/null 2>&1 || { echo "The returned Service Key was not valid JSON; it was not written to disk."; return 1; }
}

write_twingate_files() {
    local key_tmp state_tmp result
    key_tmp="$(mktemp)" || return 1; state_tmp="$(mktemp)" || { rm -f "$key_tmp"; return 1; }
    printf '%s\n' "$twingate_service_key_token" > "$key_tmp"
    jq -n --arg tenant "$twingate_tenant" --arg deviceName "$twingate_device_name" --arg serviceAccountId "$twingate_service_account_id" --arg serviceKeyId "$twingate_service_key_id" --arg updatedAt "$(date -u +%FT%TZ)" '{tenant:$tenant,deviceName:$deviceName,serviceAccountId:$serviceAccountId,serviceKeyId:$serviceKeyId,updatedAt:$updatedAt}' > "$state_tmp"
    run_as_root install -d -m 700 "$twingate_dir" && run_as_root install -o root -g root -m 600 "$key_tmp" "$twingate_key_path" && run_as_root install -o root -g root -m 600 "$state_tmp" "$twingate_state_path"
    result=$?; rm -f "$key_tmp" "$state_tmp"; return "$result"
}

start_client() {
    require_twingate_runtime && require_twingate_device || return 1
    runtime_cmd rm -f "$twingate_container_name" >/dev/null 2>&1 || true
    runtime_cmd run -d --name "$twingate_container_name" --network host --device /dev/net/tun --cap-add NET_ADMIN -v "$twingate_key_path:/etc/twingate/service_key.json:ro" twingate/client:latest || { echo "The Twingate Client container could not be started."; return 1; }
    echo "Twingate Client started with $twingate_runtime."
}

stop_client() {
    require_twingate_runtime || return 1
    runtime_cmd stop "$twingate_container_name" >/dev/null 2>&1 && echo "Twingate Client stopped." || echo "No running Twingate Client container was found."
}

show_status() {
    require_twingate_runtime || return 1
    echo ""; echo "Container runtime: $twingate_runtime"
    if twingate_device_files_exist && read_twingate_state; then
        echo "Tenant: $twingate_tenant"; echo "Device identity: $twingate_device_name"; echo "Service Account ID: $twingate_service_account_id"; echo "Service Key file: present"
    else
        echo "Local device state: not configured"
    fi
    echo ""; runtime_cmd ps -a --filter "name=^/${twingate_container_name}$" --format 'Container: {{.Names}} | State: {{.State}} | Status: {{.Status}}' 2>/dev/null || true
}

show_logs() { require_twingate_runtime && runtime_cmd logs --tail 80 "$twingate_container_name"; }

revoke_key() {
    local q='mutation serviceAccountKeyRevoke($id:ID!){serviceAccountKeyRevoke(id:$id){ok error}}' v
    v="$(jq -n --arg id "$1" '{id:$id}')"; api_mutation serviceAccountKeyRevoke "$q" "$v"
}

delete_key() {
    local q='mutation serviceAccountKeyDelete($id:ID!){serviceAccountKeyDelete(id:$id){ok error}}' v
    v="$(jq -n --arg id "$1" '{id:$id}')"; api_mutation serviceAccountKeyDelete "$q" "$v"
}

delete_service_account() {
    local q='mutation serviceAccountDelete($id:ID!){serviceAccountDelete(id:$id){ok error}}' v
    v="$(jq -n --arg id "$1" '{id:$id}')"; api_mutation serviceAccountDelete "$q" "$v"
}

remote_step() {
    local label="$1"; shift
    "$@" && { echo "$label: complete"; return 0; }
    remote_missing_is_ok && { echo "$label: already absent"; return 0; }
    echo "$label: $twingate_last_error"
    return 1
}

local_cleanup() {
    require_twingate_runtime || return 1
    runtime_cmd rm -f "$twingate_container_name" >/dev/null 2>&1 || true
    run_as_root rm -f "$twingate_key_path" "$twingate_state_path" || return 1
    echo "Local Twingate container and files were removed."
}

setup_device() {
    echo ""; echo "$script_title — Set up this computer"; divider
    require_twingate_runtime || return 1
    twingate_device_files_exist && { echo "This computer already has local Twingate Travel Access files."; echo "Use Replace device key or Remove this computer instead."; return 1; }
    twingate_device_name="$(hostname)"; [ -n "$twingate_device_name" ] || return 1
    echo "Device identity: $twingate_device_name"
    prompt_tenant && prompt_admin_api_key && prompt_key_expiration || return 1
    echo "Creating the Twingate Service Account..."; create_service_account || return 1
    echo "Creating the device Service Key..."; create_service_key "$twingate_device_name-key" || { echo "The Service Account was created, but no local key was saved."; echo "Remote Service Account ID: $twingate_service_account_id"; return 1; }
    write_twingate_files || { echo "The Service Key was created remotely but could not be saved locally."; return 1; }
    unset twingate_admin_api_key twingate_service_key_token
    echo "Starting the Twingate Client..."; start_client || return 1
    echo "Twingate Travel Access is ready for: $twingate_device_name"
    echo "Assign the Resources this computer may access in Twingate Admin."
}

replace_key() {
    local old_key answer
    require_twingate_device && read_twingate_state || { echo "Local Twingate state is incomplete."; return 1; }
    read -r -p "Create a replacement key and revoke the current key? [y/N]: " answer
    case "$answer" in y|Y|yes|YES) ;; *) return 0;; esac
    old_key="$twingate_service_key_id"
    prompt_admin_api_key && prompt_key_expiration || return 1
    create_service_key "$twingate_device_name-key-$(date +%Y%m%d%H%M%S)" || return 1
    write_twingate_files || return 1
    start_client || return 1; sleep 5
    remote_step "Previous Service Key revocation" revoke_key "$old_key" || echo "The old key remains active; revoke it manually if needed."
    unset twingate_admin_api_key twingate_service_key_token
    echo "Replacement key is installed."
}

remove_device() {
    local answer remote_failed=0
    require_twingate_device && read_twingate_state || { echo "Local Twingate state is incomplete. Use Remove local Twingate files only."; return 1; }
    echo "This attempts remote cleanup, then removes the local container and files."
    read -r -p "Type REMOVE to continue: " answer; [ "$answer" = "REMOVE" ] || return 0
    prompt_admin_api_key || return 1
    remote_step "Service Key revocation" revoke_key "$twingate_service_key_id" || remote_failed=1
    remote_step "Service Key deletion" delete_key "$twingate_service_key_id" || remote_failed=1
    remote_step "Service Account deletion" delete_service_account "$twingate_service_account_id" || remote_failed=1
    if [ "$remote_failed" -ne 0 ]; then
        echo ""; echo "Remote cleanup could not be fully confirmed."
        read -r -p "Remove local Twingate files anyway? [y/N]: " answer
        case "$answer" in y|Y|yes|YES) ;; *) echo "Local files were kept."; return 1;; esac
    fi
    local_cleanup
    unset twingate_admin_api_key
}

remove_local_only() {
    local answer
    echo "This stops local Twingate access and deletes local files only."
    echo "It does not revoke or delete anything in Twingate Admin."
    read -r -p "Type LOCAL to continue: " answer
    [ "$answer" = "LOCAL" ] || return 0
    local_cleanup
}

open_admin() {
    if twingate_device_files_exist && read_twingate_state; then :; else prompt_tenant || return 1; fi
    xdg-open "https://${twingate_tenant}.twingate.com/" >/dev/null 2>&1 &
}

menu() {
    local selection
    while true; do
        clear; echo "$script_title"; divider
        echo "1) Set up this computer"
        echo "2) Start connection"
        echo "3) Stop connection"
        echo "4) Check connection status"
        echo "5) View connection logs"
        echo "6) Replace device key"
        echo "7) Remove this computer"
        echo "8) Remove local Twingate files only"
        echo "9) Open Twingate Admin"
        echo "10) Exit"
        echo ""; read -r -p "Select an option: " selection
        case "$selection" in
            1) setup_device; pause_screen;; 2) start_client; pause_screen;; 3) stop_client; pause_screen;; 4) show_status; pause_screen;; 5) show_logs; pause_screen;; 6) replace_key; pause_screen;; 7) remove_device; pause_screen;; 8) remove_local_only; pause_screen;; 9) open_admin; pause_screen;; 10) return 0;; *) echo "Choose a number from 1 to 10."; sleep 1;;
        esac
    done
}

menu