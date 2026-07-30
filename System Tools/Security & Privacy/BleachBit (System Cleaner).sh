#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

appimageinstall() {

	bleachbit_appimage_url="$(
		curl -fsSL https://api.github.com/repos/bleachbit/bleachbit/releases/latest |
			jq -r '.assets[]?.browser_download_url // empty' |
			grep -i 'appimage' |
			grep -i 'x86_64' |
			head -n 1
	)"

	if [ -z "$bleachbit_appimage_url" ]; then
		echo "Failed to locate BleachBit AppImage URL from GitHub releases."
		exit 1
	fi

	download_path="${HOME}/Downloads/$(basename "$bleachbit_appimage_url")"

	curl -fL "$bleachbit_appimage_url" -o "$download_path" || {
		echo "Failed to download BleachBit AppImage."
		exit 1
	}

	chmod +x "$download_path"

	[ -f "$download_path" ] || {
		echo "Downloaded AppImage file not found."
		exit 1
	}

	flatpak run it.mijorus.gearlever --integrate "$download_path"

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
