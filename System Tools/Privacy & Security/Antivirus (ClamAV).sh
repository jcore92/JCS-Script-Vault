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
        "/usr/local/etc/clamd.conf"
    do
        [[ -f "$candidate" ]] && comment_example_if_present "$candidate"
    done
}

jsf_init_runtime_core

jsf_require_all \
  --native clamscan freshclam	\
  --flatpak io.github.linx_systems.ClamUI \

ensure_clamav_example_commented

flatpak override --user io.github.linx_systems.ClamUI --filesystem=host
flatpak override --user io.github.linx_systems.ClamUI --filesystem=host-os
flatpak override --user io.github.linx_systems.ClamUI --filesystem=host-etc
flatpak override --user io.github.linx_systems.ClamUI --filesystem=home

setsid flatpak run io.github.linx_systems.ClamUI >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0