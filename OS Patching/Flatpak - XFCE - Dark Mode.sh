#!/bin/bash
#jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

#jsf_init_runtime_core

#jsf_require_all \
#	--flatpak it.mijorus.gearlever

xfce_flatpak_dark_mode () {

	flatpak override --user --env=GTK_THEME=Adwaita-dark --env=GTK_THEME_VARIANT=dark --env=ADW_DEBUG_COLOR_SCHEME=prefer-dark

}

jsf_detect_desktop_environment() {
	local de="${XDG_CURRENT_DESKTOP:-}"

	if [ -z "$de" ]; then
		de="$(echo "$XDG_DATA_DIRS" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/' 2>/dev/null)"
	fi

	de="$(printf '%s' "$de" | tr '[:upper:]' '[:lower:]')"
	printf '%s\n' "$de"
}

#if [ "$(jsf_detect_distro_family)" = "mandriva" ]; then
	case "$(jsf_detect_desktop_environment)" in
	xfce)
		xfce_flatpak_dark_mode
		;;
	kde)
		# add KDE-specific refresh logic later if needed
		;;
	esac
#fi
