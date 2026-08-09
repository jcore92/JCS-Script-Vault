#!/bin/bash
#jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core
jsf_require_all --native curl

script_title="Container Runtime Installer"
selected_runtime=""

run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

choose() {
    local prompt="$1" result_var="$2"
    shift 2
    cursor_menu "$prompt" "$result_var" "$@"
}

runtime_status() {
    local podman_found=0 docker_found=0

    command -v podman >/dev/null 2>&1 && podman_found=1
    command -v docker >/dev/null 2>&1 && docker_found=1

    if [ "$podman_found" -eq 1 ] && [ "$docker_found" -eq 1 ]; then
        selected_runtime="podman"
        return 0
    fi

    if [ "$podman_found" -eq 1 ]; then
        selected_runtime="podman"
        return 0
    fi

    if [ "$docker_found" -eq 1 ]; then
        selected_runtime="docker"
        return 0
    fi

    selected_runtime=""
    return 1
}

show_status() {
    clear
    echo "$script_title"
    divider

    if command -v podman >/dev/null 2>&1; then
        echo "Podman: installed ($(podman --version 2>/dev/null || echo available))"
    else
        echo "Podman: not installed"
    fi

    if command -v docker >/dev/null 2>&1; then
        echo "Docker: installed ($(docker --version 2>/dev/null || echo available))"
    else
        echo "Docker: not installed"
    fi

    echo ""
    if runtime_status; then
        echo "JS-Forge will use: $selected_runtime"
        if command -v podman >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
            echo "Both runtimes are installed; JS-Forge deliberately prefers Podman."
        fi
    else
        echo "No supported container runtime is installed."
    fi
}

install_podman() {
    echo "Installing Podman using the system package manager..."

    case "$package_manager" in
        apt)
            run_as_root apt update && run_as_root apt install -y podman
            ;;
        dnf)
            run_as_root dnf install -y podman
            ;;
        yum)
            run_as_root yum install -y podman
            ;;
        pacman)
            run_as_root pacman -Syu --noconfirm podman
            ;;
        zypper)
            run_as_root zypper --non-interactive install podman
            ;;
        *)
            echo "No supported package manager was detected."
            return 1
            ;;
    esac

    command -v podman >/dev/null 2>&1 || {
        echo "Podman installation finished, but the podman command was not found."
        return 1
    }

    selected_runtime="podman"
    echo "Podman is ready: $(podman --version 2>/dev/null || echo podman)"
}

start_docker_service() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "Docker was installed, but systemctl is unavailable. Start the Docker daemon using your system's service manager."
        return 0
    fi

    if run_as_root systemctl enable --now docker; then
        echo "Docker service is enabled and running."
    else
        echo "Docker was installed, but its service could not be started automatically."
        echo "Check it with: sudo systemctl status docker"
        return 1
    fi
}

install_docker() {
    local choice installer
    local options=("Install Docker Engine" "Cancel")

    clear
    echo "$script_title"
    divider
    echo "Docker will be installed using Docker's official convenience script."
    echo "The script is downloaded over HTTPS, saved temporarily, then run as root."
    echo ""
    echo "This changes system packages and may add Docker's package repository."
    echo ""
    choose "Continue?" choice "${options[@]}"
    [ "$choice" = "Install Docker Engine" ] || return 0

    installer="$(mktemp)" || return 1
    trap 'rm -f "$installer"' RETURN

    echo "Downloading Docker's official installer..."
    curl -fsSL --proto '=https' --tlsv1.2 https://get.docker.com -o "$installer" || {
        echo "Docker's installer could not be downloaded."
        return 1
    }

    echo "Running Docker's installer..."
    run_as_root sh "$installer" || {
        echo "Docker installation failed."
        return 1
    }

    rm -f "$installer"
    trap - RETURN

    command -v docker >/dev/null 2>&1 || {
        echo "Docker's installer completed, but the docker command was not found."
        return 1
    }

    selected_runtime="docker"
    echo "Docker is installed: $(docker --version 2>/dev/null || echo docker)"

    options=("Enable and start Docker now" "Leave service stopped")
    choose "Docker needs its service running before JS-Forge can use it." choice "${options[@]}"
    [ "$choice" = "Enable and start Docker now" ] && start_docker_service
}

install_runtime() {
    local choice
    local options=("Install Podman (recommended)" "Install Docker Engine" "Cancel")

    if runtime_status; then
        echo "A supported container runtime is already installed: $selected_runtime"
        echo "No installation was performed."
        return 0
    fi

    clear
    echo "$script_title"
    divider
    echo "No supported container runtime was found."
    echo ""
    echo "Podman is the recommended default and works directly with JS-Forge."
    echo "Docker is available if you specifically prefer it."
    echo ""

    choose "Choose a runtime:" choice "${options[@]}"
    case "$choice" in
        "Install Podman (recommended)") install_podman ;;
        "Install Docker Engine") install_docker ;;
        *) return 0 ;;
    esac
}

menu() {
    local selection
    local options=("Check installed runtimes" "Install a container runtime" "Exit")

    while true; do
        clear
        echo "$script_title"
        divider
        choose "Select an option:" selection "${options[@]}"

        case "$selection" in
            "Check installed runtimes") show_status ;;
            "Install a container runtime") install_runtime ;;
            "Exit") return 0 ;;
        esac

        [ "$selection" = "Exit" ] || {
            echo ""
            entertocontinue
        }
    done
}

menu
