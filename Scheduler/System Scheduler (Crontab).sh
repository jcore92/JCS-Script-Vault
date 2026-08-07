#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

jsf_init_runtime_core

jsf_require_all \
	--native nano crontab

crontab_cursor_menu() {
    local choice

    cursor_menu "Choose crontab to edit:" choice \
        "User crontab (crontab -e)" \
        "Root crontab (sudo crontab -e)" \
        "Cancel"

    case "$choice" in
        "User crontab (crontab -e)")
            env VISUAL=nano EDITOR=nano crontab -e
            ;;
        "Root crontab (sudo crontab -e)")
            sudo env VISUAL=nano EDITOR=nano crontab -e
            ;;
        "Cancel"|"")
            return 0
            ;;
    esac
}

crontab_cursor_menu