#!/bin/bash
jsf_no_pause="1"

setsid xdg-open https://github.com/jcore92/JS-Forge/issues >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0