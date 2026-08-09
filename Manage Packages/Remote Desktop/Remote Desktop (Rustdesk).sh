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

script_title="RustDesk"
rustdesk_autostart_dir="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
rustdesk_autostart_file="$rustdesk_autostart_dir/jsf-rustdesk-kdocker.desktop"

run_as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

choose() {
    local prompt="$1" result_var="$2"
    shift 2
    cursor_menu "$prompt" "$result_var" "$@"
}

rustdesk_installed() { command -v rustdesk >/dev/null 2>&1; }
kdocker_installed() { command -v kdocker >/dev/null 2>&1; }

rustdesk_asset_suffix() {
    local architecture
    architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "$architecture" in
        amd64|x86_64) printf '%s\n' '-x86_64.deb' ;;
        arm64|aarch64) printf '%s\n' '-aarch64.deb' ;;
        *) echo "Unsupported RustDesk .deb architecture: $architecture" >&2; return 1 ;;
    esac
}

install_rustdesk_debian() {
    local suffix url package_file
    suffix="$(rustdesk_asset_suffix)" || return 1

    echo "Finding the current official RustDesk .deb package..."
    url="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | jq -r --arg suffix "$suffix" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' | head -n 1)"

    if [ -z "$url" ] || [ "$url" = "null" ]; then
        echo "No matching RustDesk .deb asset was found for this architecture."
        return 1
    fi

    package_file="$(mktemp --suffix=.deb)" || return 1
    trap 'rm -f "$package_file"' RETURN

    echo "Downloading: $(basename "$url")"
    curl -fL --proto '=https' --tlsv1.2 "$url" -o "$package_file" || {
        echo "RustDesk download failed."
        return 1
    }

    echo "Installing RustDesk..."
    run_as_root apt update && run_as_root apt install -y "$package_file" || {
        echo "RustDesk installation failed."
        return 1
    }

    rm -f "$package_file"
    trap - RETURN
}

install_rustdesk() {
    if rustdesk_installed; then
        echo "RustDesk is already installed: $(rustdesk --version 2>/dev/null || command -v rustdesk)"
        return 0
    fi

    if [ "$(jsf_detect_distro_family)" = "debian" ]; then
        install_rustdesk_debian || return 1
    else
        echo "Installing RustDesk from this distribution's package manager..."
        jsf_require_all --native rustdesk || return 1
    fi

    rustdesk_installed || {
        echo "RustDesk installation finished, but the rustdesk command was not found."
        return 1
    }

    echo "RustDesk installed: $(rustdesk --version 2>/dev/null || command -v rustdesk)"
}

launch_rustdesk() {
    rustdesk_installed || { echo "RustDesk is not installed."; return 1; }

    if pgrep -u "$USER" -x rustdesk >/dev/null 2>&1; then
        echo "RustDesk is already running."
        return 0
    fi

    setsid rustdesk >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
    echo "RustDesk started."
}

install_kdocker() {
    if kdocker_installed; then
        echo "KDocker is already installed."
        return 0
    fi

    echo "Installing KDocker from this distribution's package manager..."
    jsf_require_all --native kdocker || return 1

    kdocker_installed || {
        echo "KDocker installation finished, but the kdocker command was not found."
        return 1
    }

    echo "KDocker installed."
}

enable_kdocker_autostart() {
    rustdesk_installed || { echo "Install RustDesk before enabling KDocker startup."; return 1; }
    install_kdocker || return 1

    mkdir -p "$rustdesk_autostart_dir" || return 1

    cat > "$rustdesk_autostart_file" <<'EOF'
[Desktop Entry]
Type=Application
Name=RustDesk (minimized)
Comment=Start RustDesk and dock it to the system tray with KDocker
Exec=kdocker -f rustdesk
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

    echo "KDocker startup is enabled."
    echo "At your next graphical login, KDocker will start RustDesk and dock it to the system tray."
}

disable_kdocker_autostart() {
    if [ -e "$rustdesk_autostart_file" ]; then
        rm -f "$rustdesk_autostart_file"
        echo "KDocker/RustDesk graphical-login startup was disabled."
    else
        echo "KDocker/RustDesk graphical-login startup is not enabled."
    fi
}

show_status() {
    clear
    echo "$script_title"
    divider

    if rustdesk_installed; then
        echo "RustDesk: installed ($(rustdesk --version 2>/dev/null || command -v rustdesk))"
    else
        echo "RustDesk: not installed"
    fi

    if pgrep -u "$USER" -x rustdesk >/dev/null 2>&1; then
        echo "RustDesk process: running"
    else
        echo "RustDesk process: not running"
    fi

    if kdocker_installed; then echo "KDocker: installed"; else echo "KDocker: not installed"; fi
    if [ -f "$rustdesk_autostart_file" ]; then echo "KDocker startup: enabled"; else echo "KDocker startup: disabled"; fi
}

menu() {
    local selection
    local options=(
        "Install RustDesk"
        "Launch RustDesk"
        "Install KDocker"
        "Enable KDocker startup (RustDesk minimized)"
        "Disable KDocker startup"
        "Check status"
        "Exit"
    )

    while true; do
        clear
        echo "$script_title"
        divider
        choose "Select an option:" selection "${options[@]}"

        case "$selection" in
            "Install RustDesk") install_rustdesk ;;
            "Launch RustDesk") launch_rustdesk ;;
            "Install KDocker") install_kdocker ;;
            "Enable KDocker startup (RustDesk minimized)") enable_kdocker_autostart ;;
            "Disable KDocker startup") disable_kdocker_autostart ;;
            "Check status") show_status ;;
            "Exit") return 0 ;;
        esac

        [ "$selection" = "Exit" ] || { echo ""; entertocontinue; }
    done
}

menu
