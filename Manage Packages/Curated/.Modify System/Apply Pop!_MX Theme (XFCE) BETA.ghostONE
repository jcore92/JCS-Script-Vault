#!/bin/bash

cursor_menu() {
local prompt="$1" outvar="$2" options=("${@:3}")
local cur=0 count=${#options[@]}
local esc=$(echo -en "\e")

printf "$prompt\n"
while true; do
local index=0
for o in "${options[@]}"; do
    if [ $index -eq $cur ]; then
        echo -e " >\e[7m$o\e[0m"
    else
        echo "  $o"
    fi
    ((index++))
done

read -s -n3 key
case "$key" in
    "$esc[A") ((cur--)); ((cur < 0)) && cur=0 ;;
    "$esc[B") ((cur++)); ((cur >= count)) && cur=$((count - 1)) ;;
    "") break ;;
esac
echo -en "\e[${count}A"
done

printf -v "$outvar" "${options[$cur]}"
}

entertocontinue () {

entertocontinue=(
""
"Press enter to continue"
)

# Get the terminal width
term_width=$(tput cols)

# Function to center a line
center_line() {
    local line="$1"
    local line_length=${#line}
    local padding=$(( (term_width - line_length) / 2 ))
    printf "%${padding}s%s%${padding}s\n" "" "$line" ""
}

# Center each line of the image
for line in "${entertocontinue[@]}"; do
    center_line "$line"
done

read -p ""

}

mkdir $app_temp_loc 2>/dev/null

tool_to_pkg_name() {
case "$1" in
"nextcloud") echo "nextcloud-desktop" ;;
*)     echo "$1" ;;
esac
}

check_programs() {
#ksystemlog calibre
local missing=()
local programs=("tar")  # Add more here
#export PATH="$PATH:/usr/sbin"

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

check_programs

mkdir /tmp/'Pop!_MX Theme' ; tar -xzvf "$APPDIR/Modify System/Pop!_MX Theme/xfce-full-backup.tar.gz" -C /tmp/'Pop!_MX Theme'

cp -rvf /tmp/'Pop!_MX Theme'/home/*/.config /tmp/'Pop!_MX Theme'/home/*/.local /tmp/'Pop!_MX Theme'/home/*/.bash_aliases /tmp/'Pop!_MX Theme'/home/*/.bashrc /home/$USER/

mkdir -p ~/.config/autostart
cp /etc/xdg/autostart/xfce-superkey.desktop ~/.config/autostart/
echo "Hidden=true" >> ~/.config/autostart/xfce-superkey.desktop
