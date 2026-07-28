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
    printf '%s\n' "Simple TLP setup and preset helper" | center
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

say() {
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

detect_tlpui_method() {
    if command -v tlpui >/dev/null 2>&1; then
        echo "command"
        return
    fi

    if command -v flatpak >/dev/null 2>&1; then
        if flatpak list --app --columns=application 2>/dev/null | grep -Fxq "$flatpak_app_id"; then
            echo "flatpak"
            return
        fi
    fi

    if command -v python3 >/dev/null 2>&1; then
        if python3 -c 'import tlpui' >/dev/null 2>&1; then
            echo "python"
            return
        fi
    fi

    echo "none"
}

launch_tlpui() {
    local method
    method="$(detect_tlpui_method)"

    show_header

    case "$method" in
        command)
            say "Starting TLPUI..."
            tlpui >/dev/null 2>&1 & disown
            ;;
        flatpak)
            say "Starting TLPUI..."
            flatpak run "$flatpak_app_id" >/dev/null 2>&1 & disown
            ;;
        python)
            say "Starting TLPUI..."
            python3 -m tlpui >/dev/null 2>&1 & disown
            ;;
        *)
            say "TLPUI was not found."
            say "Install it first from the install menu."
            entertocontinue
            return 1
            ;;
    esac

    say "Launch command sent."
    entertocontinue
}

ensure_tlp_dropin_dir() {
    run_priv mkdir -p /etc/tlp.d
}

backup_managed_conf() {
    if run_priv test -f "$managed_conf"; then
        run_priv cp -a "$managed_conf" "${managed_conf}.${backup_suffix}"
        say "Backup created."
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
        saver)
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
        basic)
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
        speed)
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
            say "Unknown preset."
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

    say "Preset saved."
    say "$managed_conf"
}

remove_managed_conf() {
    if run_priv test -f "$managed_conf"; then
        backup_managed_conf
        run_priv rm -f "$managed_conf"
        if need_command tlp; then
            run_priv tlp start >/dev/null 2>&1 || true
        fi
        say "Saved preset removed."
    else
        say "No saved preset was found."
    fi
}

install_tlp_only() {
    show_header
    say "Installing TLP..."
    jsf_require_all --native tlp || return 1
    if need_command systemctl; then
        run_priv systemctl enable tlp >/dev/null 2>&1 || true
        run_priv systemctl restart tlp >/dev/null 2>&1 || true
    elif need_command service; then
        run_priv service tlp restart >/dev/null 2>&1 || true
    fi
    say "TLP install finished."
}

install_tlpui_native() {
    show_header
    say "Installing TLP and TLPUI..."
    jsf_require_all --native tlp python3 python3-pip tlpui || true
    say "Native install attempt finished."
}

install_tlpui_flatpak() {
    show_header
    say "Installing TLP and TLPUI..."
    jsf_require_all --native tlp flatpak || return 1
    jsf_require_all --flatpak "$flatpak_app_id" || return 1
    say "Flatpak install finished."
}

install_tlpui_python() {
    show_header
    say "Installing TLP and TLPUI..."
    jsf_require_all --native tlp python3 python3-pip || return 1
    ${sudocmd}python3 -m pip install --upgrade tlp-ui
    say "Python install finished."
}

remove_tlpui_python() {
    show_header
    ${sudocmd}python3 -m pip uninstall -y tlp-ui || true
    say "Python uninstall attempt finished."
}

remove_tlpui_flatpak() {
    show_header
    flatpak uninstall -y "$flatpak_app_id" || true
    say "Flatpak uninstall attempt finished."
}

remove_tlp_native() {
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
    say "Native uninstall attempt finished."
}

show_status() {
    local tlpui_method
    local tlp_status="Not found"
    local tlpui_status="Not found"

    need_command tlp && tlp_status="Installed"

    tlpui_method="$(detect_tlpui_method)"
    case "$tlpui_method" in
        command) tlpui_status="Installed (app command)" ;;
        flatpak) tlpui_status="Installed (Flatpak)" ;;
        python) tlpui_status="Installed (Python)" ;;
        *) tlpui_status="Not found" ;;
    esac

    say "TLP: $tlp_status"
    say "TLPUI: $tlpui_status"
    if run_priv test -f "$managed_conf"; then
        say "Saved preset file found."
    else
        say "No saved preset file found."
    fi
    divider
}

install_menu() {
    local selection
    while true; do
        show_header
        show_status
        cursor_menu "Choose install option:" selection \
            "Install TLP only" \
            "Install TLPUI with system package" \
            "Install TLPUI with Flatpak" \
            "Install TLPUI with Python" \
            "Back"

        case "$selection" in
            "Install TLP only") install_tlp_only; entertocontinue ;;
            "Install TLPUI with system package") install_tlpui_native; entertocontinue ;;
            "Install TLPUI with Flatpak") install_tlpui_flatpak; entertocontinue ;;
            "Install TLPUI with Python") install_tlpui_python; entertocontinue ;;
            "Back") return ;;
        esac
    done
}

preset_menu() {
    local selection
    while true; do
        show_header
        show_status
        cursor_menu "Choose preset:" selection \
            "Battery saver" \
            "Basic" \
            "High speed" \
            "Remove saved preset" \
            "Back"

        case "$selection" in
            "Battery saver") show_header; apply_preset saver; entertocontinue ;;
            "Basic") show_header; apply_preset basic; entertocontinue ;;
            "High speed") show_header; apply_preset speed; entertocontinue ;;
            "Remove saved preset") show_header; remove_managed_conf; entertocontinue ;;
            "Back") return ;;
        esac
    done
}

remove_menu() {
    local selection
    while true; do
        show_header
        show_status
        cursor_menu "Choose remove option:" selection \
            "Remove saved preset" \
            "Remove Python TLPUI" \
            "Remove Flatpak TLPUI" \
            "Remove system package TLP/TLPUI" \
            "Back"

        case "$selection" in
            "Remove saved preset") remove_managed_conf; entertocontinue ;;
            "Remove Python TLPUI") remove_tlpui_python; entertocontinue ;;
            "Remove Flatpak TLPUI") remove_tlpui_flatpak; entertocontinue ;;
            "Remove system package TLP/TLPUI") remove_tlp_native; entertocontinue ;;
            "Back") return ;;
        esac
    done
}

main_menu() {
    local selection
    local tlpui_method

    while true; do
        show_header
        show_status

        tlpui_method="$(detect_tlpui_method)"
        if [ "$tlpui_method" = "none" ]; then
            cursor_menu "Choose action:" selection \
                "Install" \
                "Easy setup" \
                "Remove" \
                "Exit"
        else
            cursor_menu "Choose action:" selection \
                "Open TLPUI" \
                "Install" \
                "Easy setup" \
                "Remove" \
                "Exit"
        fi

        case "$selection" in
            "Open TLPUI") launch_tlpui ;;
            "Install") install_menu ;;
            "Easy setup") preset_menu ;;
            "Remove") remove_menu ;;
            "Exit") clear_screen; exit 0 ;;
        esac
    done
}

main_menu
