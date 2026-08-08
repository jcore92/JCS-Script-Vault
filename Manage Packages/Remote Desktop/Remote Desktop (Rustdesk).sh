#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

if [ "$(jsf_detect_distro_family)" = "debian" ]; then

echo "Attempting to install package(s): '${missing[*]}'" ; var="$(curl -sL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | jq -r .assets[].browser_download_url | grep x86_64.deb)" ; cd ~/Downloads ; wget $var ; var2=$(basename "$var") ; printf " 🔐 " ; sudo apt install ~/Downloads/$var2 

else

jsf_require_all \
  --native rustdesk \

setsid rustdesk >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0

fi