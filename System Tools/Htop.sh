#!/bin/bash

tool_to_pkg_name() {
case "$1" in
"nextcloud") echo "nextcloud-desktop" ;;
*)     echo "$1" ;;
esac
}

check_programs() {
#ksystemlog calibre
local missing=()
local programs=("htop")  # Add more here

for prog in "${programs[@]}"; do
if ! command -v "$prog" &>/dev/null; then
echo -e " ✕ $prog is not installed" | print_red
missing+=("$(tool_to_pkg_name "$prog")")
#missing+=("$prog")
else
echo -e " ✓ $prog is installed"
fi
done

if [ ${#missing[@]} -ne 0 ]; then
echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; sudo apt update ; sudo $pkgmngr_install ${missing[*]}
echo "Please install missing packages using this command, then restart $programname Action:"
echo "sudo $pkgmngr_install ${missing[*]}"
#return 1
entertocontinue
exit
fi
}

check_programs ; htop
