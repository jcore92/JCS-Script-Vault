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

echo "Warning!: This script was only designed for apt usage and needs to be updated for full support of other package managers."

entertocontinue

tool_to_pkg_name() {
case "$1" in
"nextcloud") echo "nextcloud-desktop" ;;
*)     echo "$1" ;;
esac
}

loop="1"
choices=("Vivaldi" "Brave" "Librewolf" "Exit")
while [ $loop -eq 1 ]; do
clear ; echo "Pick a Web Browser to install:"
cursor_menu " " selected "${choices[@]}"

if [ "$selected" == "Vivaldi" ]; then

check_programs() {
#ksystemlog calibre
local missing=()
local programs=("vivaldi")  # Add more here

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
xdg-open https://vivaldi.com/download/ &> /dev/null
echo "Download the latest .deb version of Vivaldi." ; entertocontinue
selected_file=$(zenity --file-selection --title="Choose the Vivaldi .deb you downloaded.")

echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; sudo apt install "$selected_file"
fi
}


if check_programs; then
sleep 1
else
exit
fi
fi

if [ "$selected" == "Brave" ]; then
check_programs() {
#ksystemlog calibre
local missing=()
local programs=("brave-browser")  # Add more here

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
echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; curl -fsS https://dl.brave.com/install.sh | sh
fi
}


if check_programs; then
sleep 1
else
exit
fi
fi

if [ "$selected" == "Librewolf" ]; then
check_programs() {
#ksystemlog calibre
local missing=()
local programs=("librewolf")  # Add more here

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
echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; sudo apt update && sudo apt install extrepo -y ; sudo extrepo enable librewolf ; sudo apt update && sudo apt install librewolf -y
fi
}


if check_programs; then
sleep 1
else
exit
fi
fi

if [ "$selected" == "Exit" ]; then
loop="0"
fi

done
