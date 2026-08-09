#!/bin/bash
#jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

script_title="XRDP Server"
target_user="${SUDO_USER:-$USER}"
target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
[ -n "$target_home" ] || target_home="$HOME"
xsession_path="$target_home/.xsession"

run_as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

choose() {
    local prompt="$1" result_var="$2"
    shift 2
    cursor_menu "$prompt" "$result_var" "$@"
}

xrdp_installed() {
    command -v xrdp >/dev/null 2>&1 || [ -x /usr/sbin/xrdp ]
}

install_xrdp() {
    if xrdp_installed; then
        echo "XRDP is already installed."
        return 0
    fi

    if [ "$(jsf_detect_distro_family)" = "debian" ]; then
        echo "Installing XRDP, xorgxrdp, and D-Bus session support..."
        run_as_root apt update && run_as_root apt install -y xrdp xorgxrdp dbus-x11 || return 1
    else
        echo "Installing XRDP from this distribution's package manager..."
        jsf_require_all --native xrdp || return 1
    fi

    xrdp_installed || {
        echo "XRDP installation finished, but the xrdp command was not found."
        return 1
    }

    echo "XRDP installed."
}

service_manager() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        echo "systemd"
    elif command -v sv >/dev/null 2>&1; then
        echo "runit"
    elif command -v rc-service >/dev/null 2>&1; then
        echo "openrc"
    elif command -v service >/dev/null 2>&1; then
        echo "sysv"
    else
        echo "unknown"
    fi
}

start_xrdp_service() {
    install_xrdp || return 1

    case "$(service_manager)" in
        systemd)
            run_as_root systemctl enable --now xrdp
            ;;
        runit)
            run_as_root sv up xrdp
            ;;
        openrc)
            run_as_root rc-update add xrdp default && run_as_root rc-service xrdp start
            ;;
        sysv)
            if command -v update-rc.d >/dev/null 2>&1; then
                run_as_root update-rc.d xrdp defaults
            elif command -v chkconfig >/dev/null 2>&1; then
                run_as_root chkconfig xrdp on
            fi
            run_as_root service xrdp start
            ;;
        *)
            echo "No supported service manager was detected. Start the xrdp service manually."
            return 1
            ;;
    esac
}

stop_xrdp_service() {
    case "$(service_manager)" in
        systemd) run_as_root systemctl disable --now xrdp ;;
        runit) run_as_root sv down xrdp ;;
        openrc) run_as_root rc-service xrdp stop && run_as_root rc-update del xrdp default ;;
        sysv)
            run_as_root service xrdp stop
            if command -v update-rc.d >/dev/null 2>&1; then run_as_root update-rc.d -f xrdp remove; fi
            if command -v chkconfig >/dev/null 2>&1; then run_as_root chkconfig xrdp off; fi
            ;;
        *) echo "No supported service manager was detected."; return 1 ;;
    esac
}

backup_xsession() {
    local backup_path
    [ -e "$xsession_path" ] || return 0

    backup_path="$target_home/.xsession.jsf-backup-$(date +%Y%m%d-%H%M%S)"
    cp -a "$xsession_path" "$backup_path" || return 1
    echo "Previous .xsession backed up as: $backup_path"
}

write_xsession() {
    local command="$1"
    backup_xsession || { echo "Could not back up the current .xsession."; return 1; }

    printf '%s\n' "$command" > "$xsession_path" || return 1
    chmod 700 "$xsession_path"

    if [ "$EUID" -eq 0 ] && [ "$target_user" != "root" ]; then
        chown "$target_user":"$(id -gn "$target_user")" "$xsession_path"
    fi

    echo "XRDP session command written to: $xsession_path"
    echo "Command: $command"
}

choose_desktop_session() {
    local selection command
    local options=(
        "XFCE (recommended)"
        "KDE Plasma X11"
        "MATE"
        "Cinnamon"
        "LXQt"
        "GNOME"
        "Custom command"
        "Cancel"
    )

    choose "Choose the desktop session for XRDP:" selection "${options[@]}"

    case "$selection" in
        "XFCE (recommended)") command="startxfce4" ;;
        "KDE Plasma X11") command="startplasma-x11" ;;
        "MATE") command="mate-session" ;;
        "Cinnamon") command="cinnamon-session" ;;
        "LXQt") command="startlxqt" ;;
        "GNOME") command="gnome-session" ;;
        "Custom command")
            read -r -p "Enter the XRDP desktop-session command: " command
            [ -n "$command" ] || { echo "No command entered."; return 1; }
            ;;
        *) return 0 ;;
    esac

    write_xsession "$command"
}

restore_xsession() {
    local backup_path
    backup_path="$(ls -1t "$target_home"/.xsession.jsf-backup-* 2>/dev/null | head -n 1)"

    if [ -z "$backup_path" ]; then
        echo "No JS-Forge .xsession backup was found for $target_user."
        return 1
    fi

    [ -e "$xsession_path" ] && backup_xsession
    cp -a "$backup_path" "$xsession_path" || return 1
    chmod 700 "$xsession_path"

    if [ "$EUID" -eq 0 ] && [ "$target_user" != "root" ]; then
        chown "$target_user":"$(id -gn "$target_user")" "$xsession_path"
    fi

    echo "Restored: $backup_path"
}

show_status() {
    clear
    echo "$script_title"
    divider
    echo "Target user: $target_user"
    echo "Target home: $target_home"
    echo "Service manager: $(service_manager)"

    if xrdp_installed; then echo "XRDP: installed"; else echo "XRDP: not installed"; fi

    if [ -r "$xsession_path" ]; then
        echo ""
        echo ".xsession command:"
        cat "$xsession_path"
    else
        echo ".xsession: not configured"
    fi

    if command -v ss >/dev/null 2>&1; then
        echo ""
        echo "RDP listener (port 3389):"
        ss -ltn 2>/dev/null | grep ':3389' || echo "No TCP listener was found on port 3389."
    fi
}

show_logs() {
    if [ -r /var/log/xrdp.log ]; then
        run_as_root tail -n 80 /var/log/xrdp.log
    elif command -v journalctl >/dev/null 2>&1; then
        run_as_root journalctl -u xrdp -n 80 --no-pager
    else
        echo "No XRDP log source was found."
    fi
}

menu() {
    local selection
    local options=(
        "Install XRDP"
        "Start and enable XRDP"
        "Stop and disable XRDP"
        "Set XRDP desktop session (.xsession)"
        "Restore previous .xsession"
        "Check XRDP status"
        "View XRDP logs"
        "Exit"
    )

    while true; do
        clear
        echo "$script_title"
        divider
        choose "Select an option:" selection "${options[@]}"

        case "$selection" in
            "Install XRDP") install_xrdp ;;
            "Start and enable XRDP") start_xrdp_service ;;
            "Stop and disable XRDP") stop_xrdp_service ;;
            "Set XRDP desktop session (.xsession)") choose_desktop_session ;;
            "Restore previous .xsession") restore_xsession ;;
            "Check XRDP status") show_status ;;
            "View XRDP logs") show_logs ;;
            "Exit") return 0 ;;
        esac

        [ "$selection" = "Exit" ] || { echo ""; entertocontinue; }
    done
}

menu
