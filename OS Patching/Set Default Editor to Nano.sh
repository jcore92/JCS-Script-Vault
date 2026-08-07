#!/bin/bash
#jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

jsf_init_runtime_core

jsf_require_all \
	--native nano

if [ -f "$HOME/.bash_profile" ]; then
    profile_file="$HOME/.bash_profile"
else
    profile_file="$HOME/.bashrc"
fi

grep -qxF 'export EDITOR=nano' "$profile_file" || \
    echo 'export EDITOR=nano' >> "$profile_file"

grep -qxF 'export VISUAL=nano' "$profile_file" || \
    echo 'export VISUAL=nano' >> "$profile_file"

export EDITOR=nano
export VISUAL=nano

echo "Nano set as default editor in: $profile_file"
echo "Please log out and then back in again (or reboot) for changes to take affect"
