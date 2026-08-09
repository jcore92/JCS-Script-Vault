#!/bin/bash
jsf_no_pause="1"

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
twingate_image="docker.io/twingate/client:latest"
twingate_runtime=""
twingate_last_error=""

pause_screen() {
	echo ""
	entertocontinue
}
run_as_root() { if [ "$EUID" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
device_files_exist() { run_as_root test -r "$twingate_key_path" && run_as_root test -r "$twingate_state_path"; }
require_device() { device_files_exist || {
	echo "This computer has not been set up for Twingate Travel Access yet."
	return 1
}; }

require_runtime() {
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

runtime_cmd() { run_as_root "$twingate_runtime" "$@"; }

choose() {
	local prompt="$1" result_var="$2"
	shift 2
	cursor_menu "$prompt" "$result_var" "$@"
}

read_state() {
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
		value="${value#https://}"
		value="${value%%.twingate.com*}"
		case "$value" in "" | *[!A-Za-z0-9-]*) echo "Enter only the tenant subdomain, for example: my-company" ;; *)
			twingate_tenant="$value"
			return 0
			;;
		esac
	done
}

prompt_api_key() {
	local selection url options=("Open API settings" "Continue without opening" "Cancel")
	url="https://${twingate_tenant}.twingate.com/settings/api"
	clear
	echo "$script_title"
	divider
	echo "Create or manage your Twingate Admin API key here:"
	echo "$url"
	echo ""
	choose "What would you like to do?" selection "${options[@]}"
	case "$selection" in
	"Open API settings") xdg-open "$url" >/dev/null 2>&1 & ;;
	"Cancel") return 1 ;;
	esac
	echo ""
	echo "Generate an API key, save it in your password manager, then return here."
	read -r -s -p "Enter Twingate Admin API key (input hidden): " twingate_admin_api_key
	printf '\n'
	[ -n "$twingate_admin_api_key" ] || {
		echo "No API key was entered."
		return 1
	}
}

choose_expiration() {
	local selection options=("No expiration" "30 days" "90 days" "365 days" "Enter a custom number" "Cancel")
	choose "Choose Service Key expiration:" selection "${options[@]}"
	case "$selection" in
	"No expiration") twingate_key_expiration=0 ;; "30 days") twingate_key_expiration=30 ;; "90 days") twingate_key_expiration=90 ;; "365 days") twingate_key_expiration=365 ;;
	"Enter a custom number")
		read -r -p "Expiration in days, 0 through 365: " twingate_key_expiration
		case "$twingate_key_expiration" in "" | *[!0-9]*) return 1 ;; esac
		[ "$twingate_key_expiration" -le 365 ] || return 1
		;;
	*) return 1 ;;
	esac
}

api_call() {
	local query="$1" variables="$2" payload
	payload="$(jq -n --arg query "$query" --argjson variables "$variables" '{query:$query,variables:$variables}')" || return 1
	curl --silent --show-error --fail-with-body --connect-timeout 15 --max-time 45 -H "Content-Type: application/json" -H "X-API-KEY: $twingate_admin_api_key" --data "$payload" "https://${twingate_tenant}.twingate.com/api/graphql/"
}

mutation() {
	local field="$1" query="$2" variables="$3" response ok
	response="$(api_call "$query" "$variables")" || {
		twingate_last_error="Unable to contact the Twingate API."
		return 1
	}
	ok="$(printf '%s' "$response" | jq -r ".data.${field}.ok // false")"
	[ "$ok" = true ] && {
		twingate_response="$response"
		return 0
	}
	twingate_last_error="$(printf '%s' "$response" | jq -r '.errors[0].message // .data[]?.error // "Unknown Twingate API error"')"
	return 1
}

remote_missing() { case "${twingate_last_error,,}" in *not\ found* | *does\ not\ exist* | *not\ exist*) return 0 ;; *) return 1 ;; esac }

create_account() {
	local q='mutation serviceAccountCreate($name:String!,$resourceIds:[ID]){serviceAccountCreate(name:$name,resourceIds:$resourceIds){ok error entity{id}}}' v
	v="$(jq -n --arg name "$twingate_device_name" '{name:$name,resourceIds:[]}')"
	mutation serviceAccountCreate "$q" "$v" || {
		echo "Twingate API error: $twingate_last_error"
		return 1
	}
	twingate_service_account_id="$(printf '%s' "$twingate_response" | jq -r '.data.serviceAccountCreate.entity.id // empty')"
	[ -n "$twingate_service_account_id" ]
}

create_key() {
	local name="$1" q='mutation serviceAccountKeyCreate($expirationTime:Int!,$name:String,$serviceAccountId:ID!){serviceAccountKeyCreate(expirationTime:$expirationTime,name:$name,serviceAccountId:$serviceAccountId){ok error entity{id} token}}' v
	v="$(jq -n --argjson expirationTime "$twingate_key_expiration" --arg name "$name" --arg serviceAccountId "$twingate_service_account_id" '{expirationTime:$expirationTime,name:$name,serviceAccountId:$serviceAccountId}')"
	mutation serviceAccountKeyCreate "$q" "$v" || {
		echo "Twingate API error: $twingate_last_error"
		return 1
	}
	twingate_service_key_id="$(printf '%s' "$twingate_response" | jq -r '.data.serviceAccountKeyCreate.entity.id // empty')"
	twingate_service_key_token="$(printf '%s' "$twingate_response" | jq -r '.data.serviceAccountKeyCreate.token // empty')"
	[ -n "$twingate_service_key_id" ] && printf '%s' "$twingate_service_key_token" | jq -e 'type=="object"' >/dev/null
}

write_files() {
	local key_tmp state_tmp result
	key_tmp="$(mktemp)"
	state_tmp="$(mktemp)" || {
		rm -f "$key_tmp"
		return 1
	}
	printf '%s\n' "$twingate_service_key_token" >"$key_tmp"
	jq -n --arg tenant "$twingate_tenant" --arg deviceName "$twingate_device_name" --arg serviceAccountId "$twingate_service_account_id" --arg serviceKeyId "$twingate_service_key_id" '{tenant:$tenant,deviceName:$deviceName,serviceAccountId:$serviceAccountId,serviceKeyId:$serviceKeyId}' >"$state_tmp"
	run_as_root install -d -m 700 "$twingate_dir" && run_as_root install -o root -g root -m 600 "$key_tmp" "$twingate_key_path" && run_as_root install -o root -g root -m 600 "$state_tmp" "$twingate_state_path"
	result=$?
	rm -f "$key_tmp" "$state_tmp"
	return "$result"
}

start_client() {
	local container_args=()

	require_runtime && require_device || return 1

	runtime_cmd rm -f "$twingate_container_name" >/dev/null 2>&1 || true

	container_args=(
		-d
		--name "$twingate_container_name"
		--network host
	)

	case "$(jsf_detect_distro_family)" in
	opensuse)
		container_args+=(
			--device /dev/net/tun:/dev/net/tun
			--cap-add NET_ADMIN
			--security-opt label=disable
			-v "$twingate_key_path:/etc/twingate/service_key.json:ro,Z"
		)

		echo "Using the container compatibility profile."
		;;
	*)
		container_args+=(
			--device /dev/net/tun
			--cap-add NET_ADMIN
			-v "$twingate_key_path:/etc/twingate/service_key.json:ro"
		)
		;;
	esac

	runtime_cmd run "${container_args[@]}" "$twingate_image" || {
		echo "The Twingate Client container could not be started."
		return 1
	}

	echo "Twingate Client started with $twingate_runtime."
}

stop_client() { require_runtime && { runtime_cmd stop "$twingate_container_name" >/dev/null 2>&1 && echo "Twingate Client stopped." || echo "No running Twingate Client container was found."; }; }
show_logs() { require_runtime && runtime_cmd logs --tail 80 "$twingate_container_name"; }

show_status() {
	require_runtime || return 1
	echo "Container runtime: $twingate_runtime"
	if device_files_exist && read_state; then
		echo "Tenant: $twingate_tenant"
		echo "Device identity: $twingate_device_name"
		echo "Service Account ID: $twingate_service_account_id"
	else echo "Local device state: not configured"; fi
	runtime_cmd ps -a --filter "name=^/${twingate_container_name}$" --format 'Container: {{.Names}} | State: {{.State}} | Status: {{.Status}}' 2>/dev/null || true
}

live_status() {
	local key
	local container_state
	local started_at
	local recent_logs

	require_runtime || return 1

	while true; do
		clear
		echo "$script_title — Live Status"
		divider

		if device_files_exist && read_state; then
			echo "Tenant: $twingate_tenant"
			echo "Device identity: $twingate_device_name"
			echo "Service Key: present"
		else
			echo "Local device state: not configured"
		fi

		echo "Runtime: $twingate_runtime"

		container_state="$(runtime_cmd inspect \
			--format '{{.State.Status}}' \
			"$twingate_container_name" 2>/dev/null || echo "not created")"

		started_at="$(runtime_cmd inspect \
			--format '{{.State.StartedAt}}' \
			"$twingate_container_name" 2>/dev/null || echo "—")"

		echo "Container: $twingate_container_name"
		echo "State: $container_state"
		echo "Started: $started_at"

		divider
		echo "Recent Client activity:"
		recent_logs="$(runtime_cmd logs --tail 5 "$twingate_container_name" 2>&1)"

		if [ -n "$recent_logs" ]; then
			printf '%s\n' "$recent_logs"
		else
			echo "No Client logs are available yet."
		fi

		divider
		echo "Refreshes every 2 seconds. Press Q to return."

		IFS= read -r -s -n 1 -t 2 key || true

		case "$key" in
		q | Q)
			return 0
			;;
		esac
	done
}

revoke_key() { mutation serviceAccountKeyRevoke 'mutation serviceAccountKeyRevoke($id:ID!){serviceAccountKeyRevoke(id:$id){ok error}}' "$(jq -n --arg id "$1" '{id:$id}')"; }
delete_key() { mutation serviceAccountKeyDelete 'mutation serviceAccountKeyDelete($id:ID!){serviceAccountKeyDelete(id:$id){ok error}}' "$(jq -n --arg id "$1" '{id:$id}')"; }
delete_account() { mutation serviceAccountDelete 'mutation serviceAccountDelete($id:ID!){serviceAccountDelete(id:$id){ok error}}' "$(jq -n --arg id "$1" '{id:$id}')"; }
remote_step() {
	local label="$1"
	shift
	"$@" && {
		echo "$label: complete"
		return 0
	}
	remote_missing && {
		echo "$label: already absent"
		return 0
	}
	echo "$label: $twingate_last_error"
	return 1
}

local_cleanup() {
	require_runtime || return 1
	runtime_cmd rm -f "$twingate_container_name" >/dev/null 2>&1 || true
	run_as_root rm -f "$twingate_key_path" "$twingate_state_path"
	echo "Local Twingate container and files were removed."
}

setup_device() {
	require_runtime || return 1
	device_files_exist && {
		echo "This computer already has local Twingate Travel Access files."
		return 1
	}
	twingate_device_name="$(hostname)"
	echo "Device identity: $twingate_device_name"
	prompt_tenant && prompt_api_key && choose_expiration || return 1
	echo "Creating Service Account..."
	create_account || return 1
	echo "Creating Service Key..."
	create_key "$twingate_device_name-key" || return 1
	write_files || return 1
	unset twingate_admin_api_key twingate_service_key_token
	start_client && echo "Twingate Travel Access is ready. Assign Resources in Twingate Admin."
}

replace_key() {
	local selection old options=("Cancel" "Create replacement key")
	require_device && read_state || return 1
	choose "Replace this computer's device key?" selection "${options[@]}"
	[ "$selection" = "Create replacement key" ] || return 0
	old="$twingate_service_key_id"
	prompt_api_key && choose_expiration || return 1
	create_key "$twingate_device_name-key-$(date +%Y%m%d%H%M%S)" && write_files && start_client || return 1
	remote_step "Previous Service Key revocation" revoke_key "$old" || echo "The old key remains active; revoke it manually if needed."
	unset twingate_admin_api_key twingate_service_key_token
}

remove_device() {
	local selection failed=0 options=("Cancel" "Remove remote identity and local files" "Remove local files only")
	require_device && read_state || {
		echo "Local state is incomplete. Use local-only removal."
		return 1
	}
	choose "Choose removal behavior:" selection "${options[@]}"
	[ "$selection" = "Remove local files only" ] && {
		local_cleanup
		return
	}
	[ "$selection" = "Remove remote identity and local files" ] || return 0
	prompt_api_key || return 1
	remote_step "Service Key revocation" revoke_key "$twingate_service_key_id" || failed=1
	remote_step "Service Key deletion" delete_key "$twingate_service_key_id" || failed=1
	remote_step "Service Account deletion" delete_account "$twingate_service_account_id" || failed=1
	if [ "$failed" -ne 0 ]; then
		options=("Keep local files" "Remove local files anyway")
		choose "Remote cleanup was incomplete. What now?" selection "${options[@]}"
		[ "$selection" = "Remove local files anyway" ] || return 1
	fi
	local_cleanup
	unset twingate_admin_api_key
}

remove_local_only() {
	local selection options=("Cancel" "Remove local Twingate files")
	choose "This will not change anything in Twingate Admin." selection "${options[@]}"
	[ "$selection" = "Remove local Twingate files" ] && local_cleanup
}

open_admin() {
	if device_files_exist && read_state; then
		:
	else
		prompt_tenant || return 1
	fi

	xdg-open "https://${twingate_tenant}.twingate.com/" >/dev/null 2>&1 &
}

menu() {
	local selection options=("Set up this computer" "Start connection" "Stop connection" "Check connection status" "Live connection status" "View connection logs" "Replace device key" "Remove this computer" "Remove local Twingate files only" "Open Twingate Admin" "Exit")
	while true; do
		clear
		echo "$script_title"
		divider
		choose "Select an option:" selection "${options[@]}"
		case "$selection" in
		"Set up this computer") setup_device ;; "Start connection") start_client ;; "Stop connection") stop_client ;; "Check connection status") show_status ;; "Live connection status") live_status ;; "View connection logs") show_logs ;; "Replace device key") replace_key ;; "Remove this computer") remove_device ;; "Remove local Twingate files only") remove_local_only ;; "Open Twingate Admin") open_admin ;; "Exit") return ;;
		esac
		[ "$selection" = "Exit" ] || pause_screen
	done
}

menu
