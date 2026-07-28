#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime." >&2
    exit 1
}

jsf_init_runtime_core

gui_flag="0"
tui_flag="1"

script_name="TLP Manager"
managed_conf="/etc/tlp.d/99-jsforge-tlp.conf"
backup_suffix="$(date +%Y%m%d-%H%M%S).bak"
flatpak_app_id="com.github.d4nj1.tlpui"

clear_screen() {
    clear 2>/dev/null || true
    printf '\033c' 2>/dev/null || true
}

show_header() {
    clear_screen
    printf '%s\n' "$script_name" | center
    printf '%s\n' "Runtime-Core Aware Power Helper" | center
    divider
}

need_command() {
    command -v "$1" >/dev/null 2>&1
}

run_priv() {
    if [ -n "${sudocmd:-}" ]; then
        ${sudocmd} "$@"
    else
        "$@"
    fi
}

write_priv_file() {
    local target="$1"
    cat | ${sudocmd}tee "$target" >/dev/null
}

append_status() {
    printf '%s\n' "$1" | center
}

detect_gpu_vendor() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -Ei 'vga|3d|display' | grep -qi 'intel'; then
            echo "intel"
            return
        fi
        if lspci | grep -Ei 'vga|3d|display' | grep -Eqi 'amd|radeon|advanced micro devices'; then
            echo "amd"
            return
        fi
    fi
    echo "unknown"
}

ensure_tlp_dropin_dir() {
    run_priv mkdir -p /etc/tlp.d
}

backup_managed_conf() {
    if run_priv test -f "$managed_conf"; then
        run_priv cp -a "$managed_conf" "${managed_conf}.${backup_suffix}"
        append_status "Backup created: ${managed_conf}.${backup_suffix}"
    fi
}

apply_preset() {
    local preset="$1"
    local gpu_vendor
    local platform_ac="balanced"
    local platform_bat="low-power"
    local platform_sav="low-power"
    local cpu_ac="balance_performance"
    local cpu_bat="balance_power"
    local cpu_sav="power"
    local tlp_default_mode="BAT"
    local persistent_default="1"
    local intel_ac="balance_performance"
    local intel_bat="balance_power"
    local intel_sav="power"
    local amd_perf_ac="auto"
    local amd_perf_bat="low"
    local amd_perf_sav="low"
    local amd_state_ac="performance"
    local amd_state_bat="battery"
    local amd_state_sav="battery"

    case "$preset" in
        powersave)
            platform_ac="balanced"
            platform_bat="low-power"
            platform_sav="low-power"
            cpu_ac="balance_power"
            cpu_bat="power"
            cpu_sav="power"
            intel_ac="balance_power"
            intel_bat="power"
            intel_sav="power"
            amd_perf_ac="low"
            amd_perf_bat="low"
            amd_perf_sav="low"
            amd_state_ac="battery"
            amd_state_bat="battery"
            amd_state_sav="battery"
            ;;
        medium)
            platform_ac="balanced"
            platform_bat="balanced"
            platform_sav="low-power"
            cpu_ac="balance_performance"
            cpu_bat="balance_power"
            cpu_sav="power"
            intel_ac="balance_performance"
            intel_bat="balance_power"
            intel_sav="power"
            amd_perf_ac="auto"
            amd_perf_bat="auto"
            amd_perf_sav="low"
            amd_state_ac="balanced"
            amd_state_bat="battery"
            amd_state_sav="battery"
            ;;
        performance)
            platform_ac="performance"
            platform_bat="balanced"
            platform_sav="low-power"
            cpu_ac="performance"
            cpu_bat="balance_performance"
            cpu_sav="balance_power"
            intel_ac="performance"
            intel_bat="balance_performance"
            intel_sav="balance_power"
            amd_perf_ac="high"
            amd_perf_bat="auto"
            amd_perf_sav="low"
            amd_state_ac="performance"
            amd_state_bat="balanced"
            amd_state_sav="battery"
            ;;
        *)
            append_status "Unknown preset: $preset"
            return 1
            ;;
    esac

    gpu_vendor="$(detect_gpu_vendor)"

    ensure_tlp_dropin_dir
    backup_managed_conf

    {
        echo "# ----------------------------------------------------------------------"
        echo "# JS-Forge managed TLP preset"
        echo "# Preset: $preset"
        echo "# Generated: $(date)"
        echo "# GPU detected: $gpu_vendor"
        echo "# ----------------------------------------------------------------------"
        echo "TLP_DEFAULT_MODE=$tlp_default_mode"
        echo "TLP_PERSISTENT_DEFAULT=$persistent_default"
        echo "CPU_ENERGY_PERF_POLICY_ON_AC=$cpu_ac"
        echo "CPU_ENERGY_PERF_POLICY_ON_BAT=$cpu_bat"
        echo "CPU_ENERGY_PERF_POLICY_ON_SAV=$cpu_sav"
        echo "PLATFORM_PROFILE_ON_AC=$platform_ac"
        echo "PLATFORM_PROFILE_ON_BAT=$platform_bat"
        echo "PLATFORM_PROFILE_ON_SAV=$platform_sav"
        case "$gpu_vendor" in
            intel)
                echo "INTEL_GPU_POWER_PROFILE_ON_AC=$intel_ac"
                echo "INTEL_GPU_POWER_PROFILE_ON_BAT=$intel_bat"
                echo "INTEL_GPU_POWER_PROFILE_ON_SAV=$intel_sav"
                ;;
            amd)
                echo "RADEON_DPM_PERF_LEVEL_ON_AC=$amd_perf_ac"
                echo "RADEON_DPM_PERF_LEVEL_ON_BAT=$amd_perf_bat"
                echo "RADEON_DPM_PERF_LEVEL_ON_SAV=$amd_perf_sav"
                echo "RADEON_DPM_STATE_ON_AC=$amd_state_ac"
                echo "RADEON_DPM_STATE_ON_BAT=$amd_state_bat"
                echo "RADEON_DPM_STATE_ON_SAV=$amd_state_sav"
                ;;
            *)
                echo "# No supported GPU-specific preset written."
                ;;
        esac
    } | write_priv_file "$managed_conf"

    if need_command tlp; then
        run_priv tlp start >/dev/null 2>&1 || true
    fi

    append_status "Applied preset: $preset"
    append_status "Config written to: $managed_conf"
}

remove_managed_conf() {
    if run_priv test -f "$managed_conf"; then
        backup_managed_conf
        run_priv rm -f "$managed_conf"
        if need_command tlp; then
            run_priv tlp start >/dev/null 2>&1 || true
        fi
        append_status "Removed managed config."
    else
        append_status "No managed config present."
    fi
}

install_tlp_base() {
    show_header
    append_status "Installing TLP base dependencies..."
    jsf_require_all --native tlp python3 python3-pip || return 1
    if need_command systemctl; then
        run_priv systemctl enable tlp >/dev/null 2>&1 || true
        run_priv systemctl restart tlp >/dev/null 2>&1 || true
    elif need_command service; then
        run_priv service tlp restart >/dev/null 2>&1 || true
    fi
    append_status "Base install complete."
}

install_tlpui_native() {
    show_header
    append_status "Installing TLP + native TLPUI attempt..."
    jsf_require_all --native tlp python3 python3-pip tlpui || true
    append_status "Native install attempt finished."
}

install_tlpui_flatpak() {
    show_header
    append_status "Installing TLP + Flatpak TLPUI..."
    jsf_require_all --native tlp flatpak || return 1
    jsf_require_all --flatpak "$flatpak_app_id" || return 1
    append_status "Flatpak install complete."
}

install_tlpui_pip3() {
    show_header
    append_status "Installing TLP + pip3 TLPUI..."
    jsf_require_all --native tlp python3 python3-pip || return 1
    ${sudocmd}python3 -m pip install --upgrade tlp-ui
    append_status "pip3 install complete."
}

uninstall_menu() {
    local selection
    while true; do
        show_header
        cursor_menu "Choose uninstall action:" selection \
            "Remove JS-Forge managed TLP preset" \
            "Uninstall pip3 TLPUI" \
            "Uninstall Flatpak TLPUI" \
            "Uninstall native TLP/TLPUI attempt" \
            "Back"

        case "$selection" in
            "Remove JS-Forge managed TLP preset")
                show_header
                remove_managed_conf
                entertocontinue
                ;;
            "Uninstall pip3 TLPUI")
                show_header
                ${sudocmd}python3 -m pip uninstall -y tlp-ui || true
                append_status "pip3 uninstall attempt complete."
                entertocontinue
                ;;
            "Uninstall Flatpak TLPUI")
                show_header
                flatpak uninstall -y "$flatpak_app_id" || true
                append_status "Flatpak uninstall attempt complete."
                entertocontinue
                ;;
            "Uninstall native TLP/TLPUI attempt")
                show_header
                if [ "$package_manager" = "dnf" ] || [ "$package_manager" = "yum" ]; then
                    ${sudocmd}$package_manager remove -y tlp tlpui || true
                elif [ "$package_manager" = "apt" ]; then
                    ${sudocmd}$package_manager remove -y tlp tlpui || true
                elif [ "$package_manager" = "pacman" ]; then
                    ${sudocmd}$package_manager -Rns --noconfirm tlp tlpui || true
                elif [ "$package_manager" = "zypper" ]; then
                    ${sudocmd}$package_manager remove -y tlp tlpui || true
                fi
                append_status "Native uninstall attempt complete."
                entertocontinue
                ;;
            "Back")
                return
                ;;
        esac
    done
}

preset_menu() {
    local selection
    while true; do
        show_header
        cursor_menu "Choose a TLP preset:" selection \
            "Power save" \
            "Medium" \
            "High performance" \
            "Remove managed preset" \
            "Back"

        case "$selection" in
            "Power save")
                show_header
                apply_preset powersave
                entertocontinue
                ;;
            "Medium")
                show_header
                apply_preset medium
                entertocontinue
                ;;
            "High performance")
                show_header
                apply_preset performance
                entertocontinue
                ;;
            "Remove managed preset")
                show_header
                remove_managed_conf
                entertocontinue
                ;;
            "Back")
                return
                ;;
        esac
    done
}

install_menu() {
    local selection
    while true; do
        show_header
        cursor_menu "Choose install method:" selection \
            "Install TLP only" \
            "Install TLP + TLPUI native" \
            "Install TLP + TLPUI Flatpak" \
            "Install TLP + TLPUI pip3" \
            "Back"

        case "$selection" in
            "Install TLP only")
                install_tlp_base
                entertocontinue
                ;;
            "Install TLP + TLPUI native")
                install_tlpui_native
                entertocontinue
                ;;
            "Install TLP + TLPUI Flatpak")
                install_tlpui_flatpak
                entertocontinue
                ;;
            "Install TLP + TLPUI pip3")
                install_tlpui_pip3
                entertocontinue
                ;;
            "Back")
                return
                ;;
        esac
    done
}

main_menu() {
    local selection
    while true; do
        show_header
        cursor_menu "Choose an action:" selection \
            "Install TLP / TLPUI" \
            "Apply easy preset" \
            "Uninstall / rollback" \
            "Exit"

        case "$selection" in
            "Install TLP / TLPUI") install_menu ;;
            "Apply easy preset") preset_menu ;;
            "Uninstall / rollback") uninstall_menu ;;
            "Exit") clear_screen; exit 0 ;;
        esac
    done
}

main_menu
