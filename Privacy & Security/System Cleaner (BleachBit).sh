#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

set -u

choose_bleachbit_target() {
    local choice

    if command -v zenity >/dev/null 2>&1; then
        choice=$(zenity --list \
            --title="BleachBit launch mode" \
            --text="How do you want to open BleachBit?" \
            --radiolist \
            --column="Pick" --column="Mode" \
            TRUE "User BleachBit" \
            FALSE "Root BleachBit" \
            FALSE "Cancel" \
            --width=420 --height=260) || return 1
    elif command -v xmessage >/dev/null 2>&1; then
        if xmessage -center -buttons "User:0,Root:1,Cancel:2" "Open user BleachBit or root BleachBit?"; then
            choice="User BleachBit"
        else
            choice="Cancel"
        fi
    else
        printf 'Choose BleachBit mode:\n1) User\n2) Root\n3) Cancel\n> '
        read -r choice_num
        case "$choice_num" in
            1) choice="User BleachBit" ;;
            2) choice="Root BleachBit" ;;
            *) choice="Cancel" ;;
        esac
    fi

    case "$choice" in
        "User BleachBit") printf '%s\n' "user" ;;
        "Root BleachBit") printf '%s\n' "root" ;;
        *) return 1 ;;
    esac
}

launch_bleachbit_user() {
    local user_name="${SUDO_USER:-${USER:-$(id -un)}}"
    local user_cmd

    user_cmd="$(command -v bleachbit 2>/dev/null || true)"
    [ -n "$user_cmd" ] || user_cmd="/usr/bin/bleachbit"

    exec pkexec --user "$user_name" "$user_cmd"
}

launch_bleachbit_root() {
    local root_cmd

    root_cmd="$(command -v bleachbit-root 2>/dev/null || true)"
    if [ -z "$root_cmd" ]; then
        root_cmd="$(command -v bleachbit 2>/dev/null || true)"
    fi
    [ -n "$root_cmd" ] || root_cmd="/usr/bin/bleachbit"

    exec pkexec "$root_cmd"
}

main() {
    local mode
    mode="$(choose_bleachbit_target)" || exit 0

    case "$mode" in
        user) launch_bleachbit_user ;;
        root) launch_bleachbit_root ;;
    esac
}

jsf_init_runtime_core

if [ "$(jsf_detect_distro_family)" = "arch" ]; then

	jsf_require_all \
		--native bleachbit
	main "$@"

elif [ "$(jsf_detect_distro_family)" = "mandriva" ]; then

	jsf_require_all \
		--native bleachbit
	main "$@"

else

	jsf_require_all \
		--native bleachbit
	main "$@"

fi

#exit 0
