#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core


install_vivaldi_download() {
    local package_type="$1"
    local selected_file=""

    xdg-open "https://vivaldi.com/download/" >/dev/null 2>&1

    echo "Download the latest .${package_type} version of Vivaldi."
    entertocontinue

    selected_file="$(zenity --file-selection \
        --title="Choose the Vivaldi .${package_type} you downloaded." 2>/dev/null)" || return 0

		echo "Select the .${package_type} of Vivaldi that you just downloaded."

    [ -n "$selected_file" ] || return 0

    echo "Installing Vivaldi..."
    printf " 🔐 "

    case "$package_type" in
        deb)
            sudo apt install "$selected_file"
            ;;
        rpm-dnf)
            sudo dnf install "$selected_file"
            ;;
        rpm-zypper)
            sudo zypper --no-gpg-checks --non-interactive install "$selected_file"
            ;;
    esac

	echo "Operation complete"

}


install_vivaldi() {
    local family="$1"

    case "$family" in
        mandriva)
            jsf_require_all \
                --native vivaldi
            ;;

        suse)
            install_vivaldi_download "rpm-zypper"
            ;;

        rhel)
            install_vivaldi_download "rpm-dnf"
            ;;

        arch)
            jsf_require_all \
                --flatpak com.vivaldi.Vivaldi
            ;;

        debian)
            install_vivaldi_download "deb"
            ;;

        *)
            echo "No Vivaldi installation path is configured for: $family"
            ;;
    esac

	echo "Operation complete"

}


install_brave() {
    local family="$1"

    case "$family" in
        mandriva)
            jsf_require_all \
                --native brave-browser
            ;;

        suse|rhel|debian)
            echo "Installing Brave Browser..."
            printf " 🔐 "
            curl -fsS https://dl.brave.com/install.sh | sh
            ;;

        arch)
            jsf_require_all \
                --flatpak com.brave.Browser
            ;;

        *)
            echo "No Brave installation path is configured for: $family"
            ;;
    esac

	echo "Operation complete"

}


install_librewolf() {
    local family="$1"

    case "$family" in
        mandriva)
            jsf_require_all \
                --native librewolf
            ;;

        suse)
            sudo rpm --import https://repo.librewolf.net/pubkey.gpg

            sudo zypper ar -ef \
                https://repo.librewolf.net \
                librewolf

            sudo zypper ref

            jsf_require_all \
                --native librewolf
            ;;

        rhel)
            sudo dnf install -y dnf-plugins-core

            if command -v dnf5 >/dev/null 2>&1; then
                sudo dnf config-manager addrepo \
                    --from-repofile=https://repo.librewolf.net/librewolf.repo
            else
                sudo dnf config-manager --add-repo \
                    https://repo.librewolf.net/librewolf.repo
            fi

            jsf_require_all \
                --native librewolf
            ;;

        arch)
            jsf_require_all \
                --native librewolf
            ;;

        debian)
            echo "Installing LibreWolf..."
            printf " 🔐 "

            sudo apt update
            sudo apt install extrepo -y
            sudo extrepo enable librewolf
            sudo apt update
            sudo apt install librewolf -y
            ;;

        *)
            echo "No LibreWolf installation path is configured for: $family"
            ;;
    esac

	echo "Operation complete"

}


loop="1"
choices=("Vivaldi" "Brave" "Librewolf" "Exit")

while [ "$loop" -eq 1 ]; do
    clear
    echo "Pick a Web Browser to install:"

    cursor_menu " " selected "${choices[@]}"

    family="$(jsf_detect_distro_family)"

    case "$selected" in
        Vivaldi)
            install_vivaldi "$family"
            entertocontinue
            ;;

        Brave)
            install_brave "$family"
            entertocontinue
            ;;

        Librewolf)
            install_librewolf "$family"
            entertocontinue
            ;;

        Exit)
            loop="0"
            ;;
    esac
done