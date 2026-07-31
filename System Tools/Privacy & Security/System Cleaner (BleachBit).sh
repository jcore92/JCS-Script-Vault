#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

ensure_python_modules() {
    local missing_python_pkgs=()

    need_python_module() {
        local modulename="$1"
        local pkgname="$2"

        if python3 -c "import ${modulename}" >/dev/null 2>&1; then
            echo "Python module '${modulename}' already present"
        else
            echo "Python module '${modulename}' missing -> queueing '${pkgname}'"
            missing_python_pkgs+=("$pkgname")
        fi
    }

    need_python_module chardet  python-chardet
    need_python_module psutil   python-psutil
    need_python_module requests python-requests
    need_python_module urllib3  python-urllib3

    if ((${#missing_python_pkgs[@]})); then
        echo "Installing required Python packages: ${missing_python_pkgs[*]}"
        jsf_require_all \
            --native "${missing_python_pkgs[@]}"
    else
        echo "All required Python modules are already installed."
    fi
}

appimageinstall() {

	get_bleachbit_url() {
		curl -fsSL https://api.github.com/repos/bleachbit/bleachbit/releases |
			jq -r '
      .[] 
      | .assets[]?.browser_download_url
      | select(test("(?i)appimage") and test("(?i)x86_64"))
    ' |
			head -n 1
	}

	#!/usr/bin/env bash
	set -euo pipefail

	appimage_dir="${HOME}/AppImages"
	download_dir="${HOME}/Downloads"

	mkdir -p "$appimage_dir" "$download_dir"

	echo "Checking for existing BleachBit AppImage managed by Gear Lever..."

	existing_appimage="$(
		find "$appimage_dir" -maxdepth 1 -type f \
			\( -iname 'bleachbit.appimage' -o -iname 'bleachbit*appimage' \) |
			head -n 1
	)"

	if [ -n "${existing_appimage:-}" ] && [ -f "$existing_appimage" ]; then
		echo "Found existing BleachBit AppImage: $existing_appimage"
		appimage_path="$existing_appimage"
	else
		echo "No existing managed BleachBit AppImage, downloading latest..."

		bleachbit_appimage_url="$(get_bleachbit_url || true)"

		if [ -z "${bleachbit_appimage_url:-}" ]; then
			echo "Failed to locate any BleachBit x86_64 AppImage in GitHub releases."
			exit 1
		fi

		echo "Using URL: $bleachbit_appimage_url"

		download_path="$download_dir/$(basename "$bleachbit_appimage_url")"

		curl -fL "$bleachbit_appimage_url" -o "$download_path" || {
			echo "Failed to download BleachBit AppImage."
			exit 1
		}

		chmod +x "$download_path"

		echo "Integrating with Gear Lever..."
		flatpak run it.mijorus.gearlever --integrate "$download_path"

		echo "Locating Gear-Lever-managed BleachBit in $appimage_dir..."
		appimage_path="$(
			find "$appimage_dir" -maxdepth 1 -type f \
				\( -iname 'bleachbit.appimage' -o -iname 'bleachbit*appimage' \) |
				head -n 1
		)"
	fi

	if [ -z "${appimage_path:-}" ] || [ ! -f "$appimage_path" ]; then
		echo "BleachBit AppImage could not be located after Gear Lever integration."
		exit 1
	fi

	echo "Launching BleachBit: $appimage_path"
	setsid "$appimage_path" >/dev/null 2>&1 &
	disown 2>/dev/null || true

}

jsf_init_runtime_core

if [ "$(jsf_detect_distro_family)" = "arch" ]; then

	ensure_python_modules
	appimageinstall

elif [ "$(jsf_detect_distro_family)" = "mandriva" ]; then

	jsf_require_all \
		--native bleachbit
	setsid bleachbit >/dev/null 2>&1 &
	disown 2>/dev/null || true
	echo "opening BleachBit is currently not possible on this OS. Please open it from your OS menu."
	entertocontinue

else

	jsf_require_all \
		--native bleachbit
	setsid bleachbit >/dev/null 2>&1 &
	disown 2>/dev/null || true

fi

#exit 0
