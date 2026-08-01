#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

comment_example_if_present() {
	local conf="$1"

	[[ -f "$conf" ]] || {
		echo "Config not found: $conf"
		return 1
	}

	echo "Checking $conf for bare 'Example' line"

	# Show current lines with 'Example'
	grep -n 'Example' "$conf" || echo "(no Example lines)"

	# Match a line that is just 'Example' (with optional spaces/tabs)
	if grep -Eq $'^[ \t]*Example[ \t]*$' "$conf"; then
		echo "Commenting out 'Example' in $conf"
		sudo sed -i.bak $'/^[ \t]*Example[ \t]*$/s/^[ \t]*/# /' "$conf"
	else
		echo "No bare 'Example' line to comment in $conf"
	fi

	echo "After edit:"
	grep -n 'Example' "$conf" || echo "(no Example lines)"
}

ensure_clamav_example_commented() {
	# Freshclam: most important
	comment_example_if_present "/etc/freshclam.conf"

	# clamd.conf: still good to fix if present
	for candidate in \
		"/etc/clamav/clamd.conf" \
		"/etc/clamd.conf" \
		"/usr/local/etc/clamd.conf"; do
		[[ -f "$candidate" ]] && comment_example_if_present "$candidate"
	done
}

jsf_detect_desktop_environment() {
	local de="${XDG_CURRENT_DESKTOP:-}"

	if [ -z "$de" ]; then
		de="$(echo "$XDG_DATA_DIRS" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/' 2>/dev/null)"
	fi

	de="$(printf '%s' "$de" | tr '[:upper:]' '[:lower:]')"
	printf '%s\n' "$de"
}

jsf_patch_clamui_desktop_categories() {
	local run_only_if_patched="0"
	local desktop="$HOME/.local/share/flatpak/exports/share/applications/io.github.linx_systems.ClamUI.desktop"
	local mandriva_cat="X-MandrivaLinux-System-Configuration"

	if [ ! -f "$desktop" ]; then
		echo "Gear Lever desktop file not found at $desktop"
		return 0
	fi

	if grep -q "$mandriva_cat" "$desktop"; then
		echo "Mandriva category already present in Gear Lever desktop file"
	else
		echo "Patching Gear Lever desktop file"
		local run_only_if_patched="1"

		if grep -q '^Categories=' "$desktop"; then
			sed -i.bak \
				-e "/^Categories=/{
                    s/;[[:space:]]*$//;
                    s/$/;${mandriva_cat};/
                }" \
				"$desktop"
		else
			sed -i.bak \
				-e "/^\[Desktop Entry\]/a Categories=${mandriva_cat};" \
				"$desktop"
		fi
	fi
}

jsf_refresh_xfce_menu_cache() {
	pkill xfce4-appfinder 2>/dev/null || true
	rm -rf "$HOME/.cache/xfce4/appfinder"
	rm -rf "$HOME/.cache/menu-cache"
	update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
	xfce4-panel -r 2>/dev/null || true
}

jsf_init_runtime_core

jsf_require_all \
	--native clamscan freshclam \
	--flatpak io.github.linx_systems.ClamUI

ensure_clamav_example_commented

if [ "$(jsf_detect_distro_family)" = "mandriva" ]; then
	case "$(jsf_detect_desktop_environment)" in
	xfce)
		jsf_patch_clamui_desktop_categories
		if [ "run_only_if_patched" == "1" ]; then
			jsf_refresh_xfce_menu_cache
		fi
		;;
	kde)
		# add KDE-specific refresh logic later if needed
		;;
	esac
fi

flatpak override --user io.github.linx_systems.ClamUI --filesystem=host
flatpak override --user io.github.linx_systems.ClamUI --filesystem=host-os
flatpak override --user io.github.linx_systems.ClamUI --filesystem=host-etc
flatpak override --user io.github.linx_systems.ClamUI --filesystem=home

setsid flatpak run io.github.linx_systems.ClamUI >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0
