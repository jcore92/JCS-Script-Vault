#!/bin/bash

# 1. Start Flatpak in a completely isolated session
setsid xdg-open https://www.arunsundaram.com/gwent-classic-app/ >/dev/null 2>&1 &

# 2. Give the system a brief moment to map the process
sleep 0.2

# 3. Forcefully kill the parent script waiting on the "read" prompt
kill -9 "$PPID"

# 4. Exit this child script
exit 0