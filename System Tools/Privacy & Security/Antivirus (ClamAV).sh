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

    # 1. Find clamd.conf in common locations
    for candidate in \
        /etc/clamav/clamd.conf \
        /etc/clamd.conf \
        /usr/local/etc/clamd.conf
    do
        if [[ -f "$candidate" ]]; then
            conf="$candidate"
            break
        fi
    done

    if [[ -z "$conf" ]]; then
        echo "clamd.conf not found in known locations"
        return 1
    fi

    echo "Using clamd.conf at: $conf"

    # 2. Show any lines containing 'Example'
    echo "Lines containing 'Example' before edit:"
    grep -n 'Example' "$conf" || echo "(none)"

    # 3. Comment out a bare 'Example' line if present
    #    - match start of line, optional spaces/tabs, 'Example', optional spaces, end of line
    if grep -Eq $'^[ \t]*Example[ \t]*$' "$conf"; then
        echo "Commenting out bare 'Example' line in $conf"
        sudo sed -i.bak $'/^[ \t]*Example[ \t]*$/s/^[ \t]*/# /' "$conf"
    else
        echo "No bare 'Example' line found to comment in $conf"
    fi

    # 4. Show result
    echo "Lines containing 'Example' after edit:"
    grep -n 'Example' "$conf" || echo "(none)"
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