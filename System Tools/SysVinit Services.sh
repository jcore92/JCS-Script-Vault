#!/usr/bin/env bash

source "$JSF_RUNTIME_CORE_PATH" || {
    echo "Fatal: failed to source JS-Forge runtime." >&2
    exit 1
}

set -euo pipefail

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

USE_SUDO=""
SYSV_DIR="/etc/init.d"
SYSV_INSTALLED="no"
SYSV_ACTIVE="no"

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

detect_sysv_state() {
  SYSV_INSTALLED="no"
  SYSV_ACTIVE="no"

  if [ -d "$SYSV_DIR" ]; then
    SYSV_INSTALLED="yes"
  fi

  if [ -d /etc/rc.d ] || [ -d /etc/rc0.d ] || [ -d /etc/rc1.d ] || [ -d /etc/rc2.d ] || [ -d /etc/rc3.d ] || [ -d /etc/rc4.d ] || [ -d /etc/rc5.d ] || [ -d /etc/rc6.d ]; then
    SYSV_ACTIVE="yes"
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

  reply=$(whiptail --title "$title" --menu "$prompt" 20 70 8 "$@" 3>&1 1>&2 2>&3) || return 1
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
  	runit-supervisor)
      APP_ID="runit"
      APP_DESC="runit process supervisor"
      APP_CMD="runsvdir -P /var/service"
      APP_USER="root"
      APP_WORKDIR="/"
	  APP_LOG="no"        # simple stdout only
	  APP_AUTOSTART="yes"
      ;;
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

  rawname=$(prompt_value "Custom SysVinit service" "Service name" "custom-service") || return 1
  rawname=$(sanitize_name "$rawname")
  [ -n "$rawname" ] || die "Custom service name cannot be empty."

  desc=$(prompt_value "Custom SysVinit service" "Description" "$rawname custom service") || return 1
  cmd=$(prompt_value "Custom service" "Command to run") || return 1
  [ -n "$cmd" ] || die "Command cannot be empty."

  user=$(prompt_value "Custom SysVinit service" "Run as user" "root") || return 1
  [ -n "$user" ] || user="root"

  workdir=$(prompt_value "Custom SysVinit service" "Working directory" "/") || return 1
  [ -n "$workdir" ] || workdir="/"

  logging=$(prompt_yesno "Custom SysVinit service" "Enable logging support?")
  autostart=$(prompt_yesno "Custom SysVinit service" "Enable service immediately after creation?")

  APP_ID="$rawname"
  APP_DESC="$desc"
  APP_CMD="$cmd"
  APP_USER="$user"
  APP_WORKDIR="$workdir"
  APP_LOG="$logging"
  APP_AUTOSTART="$autostart"
}

write_sysv_service() {
  local password="$1"
  local name="$APP_ID"
  local script_path="$SYSV_DIR/$name"
  local log_target

  if [ "$APP_LOG" = "yes" ]; then
    log_target="/var/log/${name}.log"
  else
    log_target="/dev/null"
  fi

  if [ ! -f "$script_path" ]; then
    if [ -n "$USE_SUDO" ]; then
      printf '%s\n' "$password" | sudo -S -p '' tee "$script_path" >/dev/null <<EOF
#!/usr/bin/env bash
### BEGIN INIT INFO
# Provides:          ${name}
# Required-Start:    \$remote_fs \$syslog \$network
# Required-Stop:     \$remote_fs \$syslog \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${APP_DESC}
# Description:       ${APP_DESC}
### END INIT INFO

NAME='${APP_ID}'
DESC='${APP_DESC}'
COMMAND='$(shell_single_quote "$APP_CMD")'
RUN_AS='${APP_USER}'
WORKDIR='${APP_WORKDIR}'
PIDFILE="/var/run/\${NAME}.pid"
LOGFILE="${log_target}"

is_running() {
  [ -f "\$PIDFILE" ] || return 1
  local pid
  pid="\$(cat "\$PIDFILE" 2>/dev/null || true)"
  [ -n "\$pid" ] || return 1
  kill -0 "\$pid" 2>/dev/null
}

start_service() {
  echo "Starting \$NAME"
  if is_running; then
    echo "\$NAME already running"
    return 0
  fi

  mkdir -p /var/run >/dev/null 2>&1 || true
  if [ "\$LOGFILE" != "/dev/null" ]; then
    mkdir -p /var/log >/dev/null 2>&1 || true
    touch "\$LOGFILE" >/dev/null 2>&1 || true
  fi

  cd "\$WORKDIR"
  if [ "\$RUN_AS" = "root" ]; then
    nohup /bin/sh -c "\$COMMAND" >>"\$LOGFILE" 2>&1 &
  else
    nohup su -s /bin/sh -c "\$COMMAND" "\$RUN_AS" >>"\$LOGFILE" 2>&1 &
  fi
  echo \$! > "\$PIDFILE"
  sleep 1
}

stop_service() {
  echo "Stopping \$NAME"
  if is_running; then
    local pid
    pid="\$(cat "\$PIDFILE")"
    kill "\$pid" 2>/dev/null || true
    sleep 1
    kill -9 "\$pid" 2>/dev/null || true
    rm -f "\$PIDFILE"
  else
    echo "\$NAME is not running"
    rm -f "\$PIDFILE" >/dev/null 2>&1 || true
  fi
}

status_service() {
  if is_running; then
    local pid
    pid="\$(cat "\$PIDFILE")"
    echo "\$NAME is running (pid \$pid)"
    exit 0
  fi
  echo "\$NAME is not running"
  exit 1
}

case "\${1:-}" in
  start) start_service ;;
  stop) stop_service ;;
  restart) stop_service; sleep 1; start_service ;;
  status) status_service ;;
  *) echo "Usage: $script_path {start|stop|restart|status}"; exit 1 ;;
esac
EOF
    else
      tee "$script_path" >/dev/null <<EOF
#!/usr/bin/env bash
### BEGIN INIT INFO
# Provides:          ${name}
# Required-Start:    \$remote_fs \$syslog \$network
# Required-Stop:     \$remote_fs \$syslog \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${APP_DESC}
# Description:       ${APP_DESC}
### END INIT INFO

NAME='${APP_ID}'
DESC='${APP_DESC}'
COMMAND='$(shell_single_quote "$APP_CMD")'
RUN_AS='${APP_USER}'
WORKDIR='${APP_WORKDIR}'
PIDFILE="/var/run/\${NAME}.pid"
LOGFILE="${log_target}"

is_running() {
  [ -f "\$PIDFILE" ] || return 1
  local pid
  pid="\$(cat "\$PIDFILE" 2>/dev/null || true)"
  [ -n "\$pid" ] || return 1
  kill -0 "\$pid" 2>/dev/null
}

start_service() {
  echo "Starting \$NAME"
  if is_running; then
    echo "\$NAME already running"
    return 0
  fi

  mkdir -p /var/run >/dev/null 2>&1 || true
  if [ "\$LOGFILE" != "/dev/null" ]; then
    mkdir -p /var/log >/dev/null 2>&1 || true
    touch "\$LOGFILE" >/dev/null 2>&1 || true
  fi

  cd "\$WORKDIR"
  if [ "\$RUN_AS" = "root" ]; then
    nohup /bin/sh -c "\$COMMAND" >>"\$LOGFILE" 2>&1 &
  else
    nohup su -s /bin/sh -c "\$COMMAND" "\$RUN_AS" >>"\$LOGFILE" 2>&1 &
  fi
  echo \$! > "\$PIDFILE"
  sleep 1
}

stop_service() {
  echo "Stopping \$NAME"
  if is_running; then
    local pid
    pid="\$(cat "\$PIDFILE")"
    kill "\$pid" 2>/dev/null || true
    sleep 1
    kill -9 "\$pid" 2>/dev/null || true
    rm -f "\$PIDFILE"
  else
    echo "\$NAME is not running"
    rm -f "\$PIDFILE" >/dev/null 2>&1 || true
  fi
}

status_service() {
  if is_running; then
    local pid
    pid="\$(cat "\$PIDFILE")"
    echo "\$NAME is running (pid \$pid)"
    exit 0
  fi
  echo "\$NAME is not running"
  exit 1
}

case "\${1:-}" in
  start) start_service ;;
  stop) stop_service ;;
  restart) stop_service; sleep 1; start_service ;;
  status) status_service ;;
  *) echo "Usage: $script_path {start|stop|restart|status}"; exit 1 ;;
esac
EOF
    fi
    run_cmd_auto "$password" chmod +x "$script_path"
  fi

  if [ "$APP_AUTOSTART" = "yes" ]; then
    if have_cmd update-rc.d; then
      run_cmd_auto "$password" update-rc.d "$name" defaults || true
    elif have_cmd chkconfig; then
      run_cmd_auto "$password" chkconfig --add "$name" || true
      run_cmd_auto "$password" chkconfig "$name" on || true
    fi
    run_cmd_auto "$password" "$script_path" start || true
  fi
}

generate_services_menu() {
  local items=(
	"runit-supervisor" "SysV script for runit supervisor (runsvdir)" OFF
    "rustdesk"  "This service does not work"  OFF
    "syncthing" "Syncthing" OFF
	"tlp" "Power management daemon" OFF
  )
  local selections selection password=""

  selections=$(whiptail --title "Generate SysVinit Services" --checklist \
"Choose SysVinit service definitions to create" 20 70 14 \
"${items[@]}" --separate-output 3>&1 1>&2 2>&3) || return 0

  [ -n "$selections" ] || return 0

  password=$(get_action_password "create the selected SysVinit services") || return 0

  while IFS= read -r selection; do
    [ -n "$selection" ] || continue
    set_app_definition "$selection"
    write_sysv_service "$password"
  done <<< "$selections"

  show_msgbox "Generate SysVinit Services" "Finished generating selected SysVinit services."
}

create_custom_service_action() {
  local password=""

  create_custom_service_definition || return 0
  password=$(get_action_password "create ${APP_ID}") || return 0
  write_sysv_service "$password"
  show_msgbox "Custom SysVinit Service" "Created: $APP_ID"
}

list_sysv_services() {
  local path name
  [ -d "$SYSV_DIR" ] || return 0

  for path in "$SYSV_DIR"/*; do
    [ -e "$path" ] || continue
    [ -f "$path" ] || continue
    name=$(basename "$path")
    case "$name" in
      README|functions|halt|reboot|single)
        continue
        ;;
    esac
    printf '%s|%s\n' "$name" "$path"
  done | sort
}

sysv_service_action_menu() {
  local name="$1"
  local path="$2"
  local action password=""

  action=$(prompt_menu "SysVinit Service" "$name
$path" "enable" \
    enable "Enable" \
    disable "Disable" \
    delete "Delete") || return 0

  case "$action" in
    enable)
      password=$(get_action_password "enable ${name}") || return 0
      if have_cmd update-rc.d; then
        run_cmd_auto "$password" update-rc.d "$name" defaults || true
      elif have_cmd chkconfig; then
        run_cmd_auto "$password" chkconfig --add "$name" || true
        run_cmd_auto "$password" chkconfig "$name" on || true
      fi
      run_cmd_auto "$password" "$path" start || true
      show_msgbox "SysVinit Service" "Enabled $name"
      ;;
    disable)
      password=$(get_action_password "disable ${name}") || return 0
      run_cmd_auto "$password" "$path" stop || true
      if have_cmd update-rc.d; then
        run_cmd_auto "$password" update-rc.d -f "$name" remove || true
      elif have_cmd chkconfig; then
        run_cmd_auto "$password" chkconfig "$name" off || true
      fi
      show_msgbox "SysVinit Service" "Disabled $name"
      ;;
    delete)
      password=$(get_action_password "delete ${name}") || return 0
      run_cmd_auto "$password" "$path" stop || true
      if have_cmd update-rc.d; then
        run_cmd_auto "$password" update-rc.d -f "$name" remove || true
      elif have_cmd chkconfig; then
        run_cmd_auto "$password" chkconfig "$name" off || true
        run_cmd_auto "$password" chkconfig --del "$name" || true
      fi
      run_cmd_auto "$password" rm -f "$path"

      if [ -e "$path" ]; then
        show_msgbox "Delete Failed" "Could not delete:
$path"
      else
        show_msgbox "SysVinit Service" "Deleted $name"
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
    done < <(list_sysv_services)

    if [ "${#entries[@]}" -eq 0 ]; then
      show_msgbox "View SysVinit Services" "No SysVinit services found in $SYSV_DIR"
      return 0
    fi

    choice=$(whiptail --title "View SysVinit Services" --menu \
"Select a SysVinit service (Cancel to go back)" 20 70 13 \
Exit "Back to main menu" \
"${entries[@]}" 3>&1 1>&2 2>&3) || return 0

    if [ "$choice" = "Exit" ]; then
      return 0
    fi

    sysv_service_action_menu "$choice" "$SYSV_DIR/$choice"
  done
}

show_reference() {
  local text
  text=$(cat <<EOF
SysVinit Directories Installed/Active ($SYSV_DIR):
   $SYSV_INSTALLED / $SYSV_ACTIVE

SysVinit commands reference:
   sudo $SYSV_DIR/<SERVICE NAME> status
   sudo $SYSV_DIR/<SERVICE NAME> start
   sudo $SYSV_DIR/<SERVICE NAME> stop
   sudo $SYSV_DIR/<SERVICE NAME> restart

   sudo update-rc.d <SERVICE NAME> defaults
   sudo update-rc.d -f <SERVICE NAME> remove
   sudo chkconfig --add <SERVICE NAME>
   sudo chkconfig <SERVICE NAME> on
   sudo chkconfig <SERVICE NAME> off
EOF
)
  show_msgbox "SysVinit Reference" "$text"
}

main_menu() {
  local choice

  while true; do
    choice=$(prompt_menu "SysVinit Services" "Choose an action" "view" \
      view     "View Services"      \
      generate "Generate Services"  \
      custom   "Custom Service"     \
      ref      "Reference"          \
      exit     "Exit") || break

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
  detect_sysv_state
  main_menu
}

main "$@"