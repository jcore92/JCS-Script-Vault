#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

ensure_clamd_example_commented() {
    local conf="/etc/clamav/clamd.conf"

    [[ -f "$conf" ]] || {
        echo "clamd.conf not found: $conf"
        return 1
    }

    if grep -Eq '^[[:space:]]*Example[[:space:]]*$' "$conf"; then
        echo "Commenting out uncommented 'Example' line in $conf"
        sed -i 's/^[[:space:]]*Example[[:space:]]*$/#Example/' "$conf"
    else
        echo "'Example' is already commented out or not present in $conf"
    fi
}

jsf_init_runtime_core

jsf_require_all \
  --native clamscan freshclam	\
  --flatpak io.github.linx_systems.ClamUI \

ensure_clamd_example_commented

flatpak override --user io.github.linx_systems.ClamUI --filesystem=host
flatpak override --user io.github.linx_systems.ClamUI --filesystem=host-os
flatpak override --user io.github.linx_systems.ClamUI --filesystem=host-etc
flatpak override --user io.github.linx_systems.ClamUI --filesystem=home

setsid flatpak run io.github.linx_systems.ClamUI >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0