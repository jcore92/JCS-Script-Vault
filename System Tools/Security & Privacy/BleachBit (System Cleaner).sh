#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

appimageinstall() {

	appimage_dir="${HOME}/AppImages"

	existing_appimage="$(
		find "$appimage_dir" -maxdepth 1 -type f \
			\( -iname 'bleachbit.appimage' -o -iname 'bleachbit*appimage' \) |
			head -n 1
	)"

	appimage_dir="${HOME}/AppImages"
	download_dir="${HOME}/Downloads"
	mkdir -p "$appimage_dir" "$download_dir"

	existing_appimage="$(
		find "$appimage_dir" -maxdepth 1 -type f \
			\( -iname 'bleachbit.appimage' -o -iname 'bleachbit*appimage' \) |
			head -n 1
	)"

	if [ -n "$existing_appimage" ] && [ -f "$existing_appimage" ]; then
		appimage_path="$existing_appimage"
	else
		bleachbit_appimage_url="$(
			curl -fsSL https://api.github.com/repos/bleachbit/bleachbit/releases/latest |
				jq -r '.assets[] | select(.name | test("BleachBit-.*-x86_64\\.AppImage$")) | .browser_download_url' |
				head -n 1
		)"

		download_path="$download_dir/$(basename "$bleachbit_appimage_url")"
		curl -fL "$bleachbit_appimage_url" -o "$download_path"
		chmod +x "$download_path"

		flatpak run it.mijorus.gearlever --integrate "$download_path"

		appimage_path="$(
			find "$appimage_dir" -maxdepth 1 -type f \
				\( -iname 'bleachbit.appimage' -o -iname 'bleachbit*appimage' \) |
				head -n 1
		)"
	fi

	[ -n "$appimage_path" ] || {
		echo "BleachBit AppImage could not be located after Gear Lever integration."
		exit 1
	}

	setsid "$appimage_path" >/dev/null 2>&1 &
	disown 2>/dev/null || true

}

jsf_init_runtime_core

jsf_require_all \
	--native bleachbit

if [ "$(jsf_detect_distro_family)" = "arch" ]; then

	appimageinstall

else
	setsid bleachbit >/dev/null 2>&1 &
	disown 2>/dev/null || true
fi

#exit 0
