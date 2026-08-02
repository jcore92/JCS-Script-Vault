#!/bin/bash
jsf_no_pause="1"

setsid xdg-open https://www.arunsundaram.com/gwent-classic-app/ >/dev/null 2>&1 &
disown 2>/dev/null || true

#exit 0