#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ "$(jsf_detect_distro_family)" = "suse" ]; then

jsf_require_all \
  --native ufw yast2 \

setsid xdg-su -c '/sbin/yast2 firewall' >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0

else

jsf_require_all \
  --native ufw gufw \

setsid gufw >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0
fi
