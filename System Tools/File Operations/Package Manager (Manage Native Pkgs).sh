#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

case "${DISTRO_FAMILY:-$(jsf_detect_distro_family)}" in
    debian)
        jsf_require_all \
          --native synaptic

        pkexec /usr/sbin/synaptic #>/dev/null 2>&1 &
        disown 2>/dev/null || true
        ;;

    rhel)
        jsf_require_all \
          --native dnfdragora

        pkexec dnfdragora #>/dev/null 2>&1 &
        disown 2>/dev/null || true
        ;;

    suse)
        jsf_require_all \
          --native yast2-packager

        pkexec /usr/lib/YaST2/bin/sw_single_wrapper #>/dev/null 2>&1 &
        disown 2>/dev/null || true
        ;;

    arch)
        jsf_require_all \
          --native octopi

        pkexec octopi #>/dev/null 2>&1 &
        disown 2>/dev/null || true
        ;;

    *)
        echo "Unsupported distro family: ${DISTRO_FAMILY:-unknown}"
        exit 1
        ;;
esac

#exit 0
