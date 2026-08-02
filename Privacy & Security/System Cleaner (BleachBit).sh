#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

jsf_init_runtime_core

if [ "$(jsf_detect_distro_family)" = "arch" ]; then

	jsf_require_all \
		--native bleachbit

	cursor_menu "Choose BleachBit mode:" choice "User BleachBit" "Root BleachBit"

	case "$choice" in
	"User BleachBit")
		pkexec --user "$USER" bleachbit
		;;
	"Root BleachBit")
		pkexec bleachbit
		;;
	esac

elif [ "$(jsf_detect_distro_family)" = "mandriva" ]; then

	jsf_require_all \
		--native bleachbit

	cursor_menu "Choose BleachBit mode:" choice "User BleachBit" "Root BleachBit"

	case "$choice" in
	"User BleachBit")
		pkexec --user "$USER" bleachbit
		;;
	"Root BleachBit")
		pkexec bleachbit
		;;
	esac

else

	jsf_require_all \
		--native bleachbit

	cursor_menu "Choose BleachBit mode:" choice "User BleachBit" "Root BleachBit"

	case "$choice" in
	"User BleachBit")
		pkexec --user "$USER" bleachbit
		;;
	"Root BleachBit")
		pkexec bleachbit
		;;
	esac

fi

#exit 0
