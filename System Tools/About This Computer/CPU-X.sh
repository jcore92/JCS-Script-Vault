#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all \
  --flatpak io.github.thetumultuousunicornofdarkness.cpu-x \

# 1. Start Flatpak in a completely isolated session
setsid flatpak run io.github.thetumultuousunicornofdarkness.cpu-x >/dev/null 2>&1 &

# 2. Give the system a brief moment to map the process
sleep 0.2

# 3. Forcefully kill the parent script waiting on the "read" prompt
kill -9 "$PPID"

# 4. Exit this child script
exit 0