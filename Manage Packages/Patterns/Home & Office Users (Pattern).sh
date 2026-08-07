#!/bin/bash
#jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all \
  --native libreoffice thunderbird \
  --flatpak com.ylsoftware.qmmp.Qmmp org.videolan.VLC org.musicbrainz.Picard org.kde.digikam io.github.xiaoyifang.goldendict_ng info.bibletime.BibleTime org.jeffvli.feishin com.bitwarden.desktop com.ulduzsoft.Birdtray com.discordapp.Discord org.telegram.desktop \
