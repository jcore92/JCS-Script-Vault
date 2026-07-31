#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

ensure_clamd_example_commented() {
    local conf=""

    for candidate in /etc/clamav/clamd.conf /etc/clamd.conf; do
        [[ -f "$candidate" ]] && conf="$candidate" && break
    done

    [[ -n "$conf" ]] || {
        echo "clamd.conf not found"
        return 1
    }

    if grep -Eq '^[[:space:]]*#?[[:space:]]*Example[[:space:]]*\r?$' "$conf"; then
        if grep -Eq '^[[:space:]]*#[[:space:]]*Example[[:space:]]*\r?$' "$conf"; then
            echo "'Example' already commented in $conf"
        else
            echo "Commenting out 'Example' in $conf"
            sudo sed -i.bak '/^[[:space:]]*Example[[:space:]]*\r\?$/ s/^[[:space:]]*/#/' "$conf"
        fi
    else
        echo "No standalone 'Example' line found in $conf"
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