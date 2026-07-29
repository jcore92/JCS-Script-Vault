#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all \
  --flatpak io.github.hakandundar34coding.system-monitoring-center \

setsid flatpak run io.github.hakandundar34coding.system-monitoring-center >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0