#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

set -euo pipefail

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

USE_SUDO=""
RUNIT_INSTALLED="no"
RUNIT_ACTIVE="no"
RUNIT_AVAILABLE_DIR=""
RUNIT_ACTIVE_DIR=""

APP_ID=""
APP_DESC=""
APP_CMD=""
APP_USER="root"
APP_WORKDIR="/"
APP_LOG="yes"
APP_AUTOSTART="yes"

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_whiptail() {
  if ! have_cmd whiptail; then
    die "whiptail is required for this tool. Please install it and rerun."
  fi
}

require_root_mode() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    USE_SUDO="yes"
  fi
}

run_cmd_plain() {
  "$@"
}

run_cmd_with_password() {
  local password="$1"
  shift
  printf '%s\n' "$password" | sudo -S -p '' "$@"
}

run_cmd_auto() {
  local password="$1"
  shift
  if [ -n "$USE_SUDO" ]; then
    run_cmd_with_password "$password" "$@"
  else
    run_cmd_plain "$@"
  fi
}

sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

shell_single_quote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

path_has_entries() {
  local p="$1"
  [ -d "$p" ] || return 1
  find "$p" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1 | grep -q .
}

detect_runit_state() {
  local d
  local available_candidates=()
  local active_candidates=()

  RUNIT_INSTALLED="no"
  RUNIT_ACTIVE="no"

  if have_cmd runsvdir || have_cmd runsv || [ -x /usr/bin/runsvdir ] || [ -x /sbin/runsvdir ]; then
    RUNIT_INSTALLED="yes"
  fi

  if [ -n "${RUNIT_AVAILABLE_DIR_OVERRIDE:-}" ]; then
    available_candidates+=("${RUNIT_AVAILABLE_DIR_OVERRIDE}")
  fi
  available_candidates+=(
    "/etc/runit/sv"
    "/etc/sv"
    "/etc/runit"
    "/service"
    "/var/service"
  )

  if [ -n "${RUNIT_ACTIVE_DIR_OVERRIDE:-}" ]; then
    active_candidates+=("${RUNIT_ACTIVE_DIR_OVERRIDE}")
  fi
  active_candidates+=(
    "/run/runit/service"
    "/var/service"
    "/service"
    "/etc/service"
  )

  RUNIT_AVAILABLE_DIR=""
  RUNIT_ACTIVE_DIR=""

  for d in "${available_candidates[@]}"; do
    if [ -d "$d" ]; then
      RUNIT_AVAILABLE_DIR="$d"
      break
    fi
  done

  for d in "${active_candidates[@]}"; do
    if [ -d "$d" ]; then
      RUNIT_ACTIVE_DIR="$d"
      break
    fi
  done

  [ -n "$RUNIT_AVAILABLE_DIR" ] || RUNIT_AVAILABLE_DIR="${RUNIT_AVAILABLE_DIR_OVERRIDE:-/etc/sv}"

  if [ -z "$RUNIT_ACTIVE_DIR" ]; then
    case "$RUNIT_AVAILABLE_DIR" in
      /etc/runit/sv|/etc/runit)
        RUNIT_ACTIVE_DIR="/run/runit/service"
        ;;
      /etc/sv)
        RUNIT_ACTIVE_DIR="/var/service"
        ;;
      /service)
        RUNIT_ACTIVE_DIR="/service"
        ;;
      /var/service)
        RUNIT_ACTIVE_DIR="/var/service"
        ;;
      *)
        RUNIT_ACTIVE_DIR="${RUNIT_ACTIVE_DIR_OVERRIDE:-/var/service}"
        ;;
    esac
  fi

  if pgrep -x runsvdir >/dev/null 2>&1 || pgrep -fa runsvdir >/dev/null 2>&1; then
    RUNIT_ACTIVE="yes"
  elif path_has_entries "$RUNIT_ACTIVE_DIR"; then
    RUNIT_ACTIVE="yes"
  fi
}

prompt_value() {
  local title="$1"
  local prompt="$2"
  local initial="${3:-}"
  local height="${4:-10}"
  local width="${5:-60}"
  local reply=""

  reply=$(whiptail --title "$title" --inputbox "$prompt" "$height" "$width" "$initial" 3>&1 1>&2 2>&3) || return 1
  printf '%s' "$reply"
}

prompt_password() {
  local title="$1"
  local prompt="$2"
  local reply=""

  reply=$(whiptail --title "$title" --passwordbox "$prompt" 9 60 3>&1 1>&2 2>&3) || return 1
  printf '%s' "$reply"
}

prompt_yesno() {
  local title="$1"
  local prompt="$2"

  if whiptail --title "$title" --yesno "$prompt" 9 60 3>&1 1>&2 2>&3; then
    printf 'yes'
  else
    printf 'no'
  fi
}

prompt_menu() {
  local title="$1"
  local prompt="$2"
  local default_choice="$3"
  shift 3
  local reply=""

  reply=$(whiptail --title "$title" --menu "$prompt" 20 70 8 "$@" 3>&1 1>&2 2>&3) || reply="$default_choice"
  printf '%s' "$reply"
}

show_msgbox() {
  local title="$1"
  local text="$2"

  whiptail --title "$title" --msgbox "$text" 20 70
}

get_action_password() {
  local action_label="$1"
  local pw=""

  if [ -z "$USE_SUDO" ]; then
    printf '%s' ""
    return 0
  fi

  pw=$(prompt_password "Sudo Required" "Enter your sudo password to ${action_label}.") || return 1
  [ -n "$pw" ] || return 1

  if ! printf '%s\n' "$pw" | sudo -S -p '' -v >/dev/null 2>&1; then
    show_msgbox "Authentication Failed" "Incorrect sudo password."
    return 1
  fi

  printf '%s' "$pw"
}

set_app_definition() {
  local app="$1"

  APP_ID=""
  APP_DESC=""
  APP_CMD=""
  APP_USER="root"
  APP_WORKDIR="/"
  APP_LOG="yes"
  APP_AUTOSTART="yes"

  case "$app" in
    rustdesk)
      APP_ID="rustdesk"
      APP_DESC="RustDesk background service"
      APP_CMD="rustdesk --service"
      APP_USER="root"
      APP_WORKDIR="/"
      ;;
    syncthing)
      APP_ID="syncthing"
      APP_DESC="Syncthing daemon"
      APP_CMD="syncthing serve --no-browser --no-restart"
      APP_USER="root"
      APP_WORKDIR="/root"
      ;;
	tlp)
      APP_ID="tlp"
      APP_DESC="tlp power management daemon"

	  # Dynamically find the absolute path to tlp
      TLP_PATH=$(command -v tlp 2>/dev/null || true)
      if [ -z "$TLP_PATH" ]; then
        show_msgbox "TLP not found" "The 'tlp' command is not in PATH.
Install TLP first, then try again."
        return 1
      fi

      APP_CMD="$TLP_PATH start"
      APP_USER="root"
      APP_WORKDIR="/root"
      ;;
    custom)
      create_custom_service_definition || return 1
      ;;
    *)
      die "Unknown app definition: $app"
      ;;
  esac
}

create_custom_service_definition() {
  local rawname desc cmd user workdir logging autostart

  rawname=$(prompt_value "Runit Custom service" "Service name" "custom-service") || return 1
  rawname=$(sanitize_name "$rawname")
  [ -n "$rawname" ] || die "Runit Custom service name cannot be empty."

  desc=$(prompt_value "Runit Custom service" "Description" "$rawname custom service") || return 1
  cmd=$(prompt_value "Runit Custom service" "Command to run") || return 1
  [ -n "$cmd" ] || die "Runit Command cannot be empty."

  user=$(prompt_value "Runit Custom service" "Run as user" "root") || return 1
  [ -n "$user" ] || user="root"

  workdir=$(prompt_value "Runit Custom service" "Working directory" "/") || return 1
  [ -n "$workdir" ] || workdir="/"

  logging=$(prompt_yesno "Runit Custom service" "Enable logging support?")
  autostart=$(prompt_yesno "Runit Custom service" "Enable service immediately after creation?")

  APP_ID="$rawname"
  APP_DESC="$desc"
  APP_CMD="$cmd"
  APP_USER="$user"
  APP_WORKDIR="$workdir"
  APP_LOG="$logging"
  APP_AUTOSTART="$autostart"
}

write_runit_service() {
  local password="$1"
  local name="$APP_ID"
  local svc_dir="$RUNIT_AVAILABLE_DIR/$name"
  local run_file="$svc_dir/run"
  local log_run_file="$svc_dir/log/run"

  run_cmd_auto "$password" mkdir -p "$svc_dir"

  if [ ! -f "$run_file" ]; then
    if [ -n "$USE_SUDO" ]; then
      printf '%s\n' "$password" | sudo -S -p '' tee "$run_file" >/dev/null <<EOF
#!/usr/bin/env bash
cd "${APP_WORKDIR}"
exec chpst -u "${APP_USER}" sh -c '$(shell_single_quote "$APP_CMD")'
EOF
    else
      tee "$run_file" >/dev/null <<EOF
#!/usr/bin/env bash
cd "${APP_WORKDIR}"
exec chpst -u "${APP_USER}" sh -c '$(shell_single_quote "$APP_CMD")'
EOF
    fi
    run_cmd_auto "$password" chmod +x "$run_file"
  fi

  if [ "$APP_LOG" = "yes" ]; then
    run_cmd_auto "$password" mkdir -p "$svc_dir/log/main"
    if [ ! -f "$log_run_file" ]; then
      if [ -n "$USE_SUDO" ]; then
        printf '%s\n' "$password" | sudo -S -p '' tee "$log_run_file" >/dev/null <<'EOF'
#!/usr/bin/env bash
exec svlogd -tt ./main
EOF
      else
        tee "$log_run_file" >/dev/null <<'EOF'
#!/usr/bin/env bash
exec svlogd -tt ./main
EOF
      fi
      run_cmd_auto "$password" chmod +x "$log_run_file"
    fi
  fi

  run_cmd_auto "$password" mkdir -p "$RUNIT_ACTIVE_DIR"

  if [ -L "$RUNIT_ACTIVE_DIR/$name" ] || [ -e "$RUNIT_ACTIVE_DIR/$name" ]; then
    run_cmd_auto "$password" rm -f "$RUNIT_ACTIVE_DIR/$name" || true
  fi

  run_cmd_auto "$password" ln -s "$svc_dir" "$RUNIT_ACTIVE_DIR/$name" || true

  if [ "$APP_AUTOSTART" = "yes" ] && have_cmd sv; then
    run_cmd_auto "$password" sv up "$RUNIT_ACTIVE_DIR/$name" || true
  fi
}

generate_services_menu() {
  local items=(
    "rustdesk"  "This service does not work"  OFF
    "syncthing" "Syncthing" OFF
	"tlp" "Power management daemon" OFF
  )
  local selections selection password=""

  selections=$(whiptail --title "Generate Runit Services" --checklist \
"Choose runit service definitions to create" 20 70 14 \
"${items[@]}" --separate-output 3>&1 1>&2 2>&3) || return 0

  [ -n "$selections" ] || return 0

  password=$(get_action_password "create the selected Runit services") || return 0

  while IFS= read -r selection; do
    [ -n "$selection" ] || continue
    set_app_definition "$selection"
    write_runit_service "$password"
  done <<< "$selections"

  show_msgbox "Generate Runit Services" "Finished generating selected Runit services."
}

create_custom_service_action() {
  local password=""

  create_custom_service_definition || return 0
  password=$(get_action_password "create ${APP_ID}") || return 0
  write_runit_service "$password"
  show_msgbox "Custom Runit Service" "Created: $APP_ID"
}

list_runit_services() {
  local path name
  [ -d "$RUNIT_AVAILABLE_DIR" ] || return 0

  for path in "$RUNIT_AVAILABLE_DIR"/*; do
    [ -e "$path" ] || continue
    [ -d "$path" ] || continue
    name=$(basename "$path")
    printf '%s|%s\n' "$name" "$path"
  done | sort
}

runit_service_action_menu() {
  local name="$1"
  local path="$2"
  local action password=""

  action=$(prompt_menu "Runit Service" "$name
$path" "enable" \
    enable "Enable" \
    disable "Disable" \
    delete "Delete") || return 0

  case "$action" in
    enable)
      password=$(get_action_password "enable ${name}") || return 0
      run_cmd_auto "$password" mkdir -p "$RUNIT_ACTIVE_DIR"
      if [ -L "$RUNIT_ACTIVE_DIR/$name" ] || [ -e "$RUNIT_ACTIVE_DIR/$name" ]; then
        run_cmd_auto "$password" rm -rf "$RUNIT_ACTIVE_DIR/$name"
      fi
      run_cmd_auto "$password" ln -s "$path" "$RUNIT_ACTIVE_DIR/$name"
      if have_cmd sv; then
        run_cmd_auto "$password" sv up "$RUNIT_ACTIVE_DIR/$name" || true
      fi
      show_msgbox "Runit Service" "Enabled $name"
      ;;
    disable)
      password=$(get_action_password "disable ${name}") || return 0
      run_cmd_auto "$password" rm -f "$RUNIT_ACTIVE_DIR/$name"
      show_msgbox "Runit Service" "Disabled $name"
      ;;
    delete)
      password=$(get_action_password "delete ${name}") || return 0
      run_cmd_auto "$password" rm -f "$RUNIT_ACTIVE_DIR/$name"
      run_cmd_auto "$password" rm -rf "$path"

      if [ -e "$path" ] || [ -e "$RUNIT_ACTIVE_DIR/$name" ]; then
        show_msgbox "Delete Failed" "Could not delete:
$RUNIT_ACTIVE_DIR/$name
$path"
      else
        show_msgbox "Runit Service" "Deleted $name"
      fi
      ;;
  esac
}

view_services_menu() {
  local entries=()
  local line name path choice

  while true; do
    entries=()
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      name="${line%%|*}"
      path="${line#*|}"
      entries+=("$name" "$path")
    done < <(list_runit_services)

    if [ "${#entries[@]}" -eq 0 ]; then
      show_msgbox "View Runit Services" "No Runit services found in $RUNIT_AVAILABLE_DIR"
      return 0
    fi

    choice=$(whiptail --title "View Runit Services" --menu \
"Select a Runit service (Cancel to go back)" 20 70 13 \
Exit "Back to main menu" \
"${entries[@]}" 3>&1 1>&2 2>&3) || return 0

    if [ "$choice" = "Exit" ]; then
      return 0
    fi

    runit_service_action_menu "$choice" "$RUNIT_AVAILABLE_DIR/$choice"
  done
}

show_reference() {
  local text
  text=$(cat <<EOF
Runit Installed/Active:
   $RUNIT_INSTALLED / $RUNIT_ACTIVE

runit commands reference:
   sudo sv status $RUNIT_ACTIVE_DIR/<SERVICE NAME>
   sudo sv up $RUNIT_ACTIVE_DIR/<SERVICE NAME>
   sudo sv down $RUNIT_ACTIVE_DIR/<SERVICE NAME>

   sudo rm -f $RUNIT_ACTIVE_DIR/<SERVICE NAME>
   sudo rm -rf $RUNIT_AVAILABLE_DIR/<SERVICE NAME>

Detected Locations:
   Available dir: $RUNIT_AVAILABLE_DIR
   Active dir:    $RUNIT_ACTIVE_DIR  
EOF
)
  show_msgbox "Runit Reference" "$text"
}

main_menu() {
  local choice

  while true; do
    choice=$(prompt_menu "Runit Services" "Choose an action" "view" \
      view     "View Services"      \
      generate "Generate Services"  \
      custom   "Custom Service"     \
      ref      "Reference"          \
      exit     "Exit")

    case "$choice" in
      view)     view_services_menu ;;
      generate) generate_services_menu ;;
      custom)   create_custom_service_action ;;
      ref)      show_reference ;;
      exit)     break ;;
      *)        break ;;
    esac
  done
}

main() {
  require_whiptail
  require_root_mode
  detect_runit_state
  main_menu
}

main "$@"