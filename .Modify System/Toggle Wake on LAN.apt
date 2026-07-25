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
local programs=("ethtool")  # Add more here
export PATH="$PATH:/usr/sbin"

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

#interface=$(ip -br link | awk '/^en/ {print $1; exit}')
interface=$(ip -br link | awk '/^(en|eth)/ {print $1; exit}')
service_file_temp="$app_temp_loc/wol.service"
service_file="/etc/systemd/system/wol.service"
mac=$(cat /sys/class/net/$interface/address)

if [ -f "$service_file" ]; then
    echo " ✓ Wake on LAN is enabled."
    cursor_menu " " choice "Disable and remove Wake on LAN" "Edit Service File" "Keep enabled"
    if [ "$choice" = "Disable and remove Wake on LAN" ]; then
        #sudo systemctl stop wol.service 2>/dev/null || true
        #sudo systemctl disable wol.service
        #sudo rm "$service_file"
        #sudo ethtool -s "$interface" wol d
        printf " 🔐 " ; sudo systemctl stop wol.service 2>/dev/null || true ; sudo systemctl disable wol.service ; sudo rm "$service_file" ; sudo ethtool -s "$interface" wol d
        echo "Wake on LAN disabled and service deleted."
    fi

    if [ "$choice" = "Edit Service File" ]; then
        echo "List of Interfaces:"
        ip -br link
        echo "Wake on LAN probably on interface: $interface" ; sleep 1 ; printf " 🔐 " ; sudo nano "$service_file"
        echo "Service File Successfully Edited."
    fi
else
    echo " ✕ Wake on LAN is not enabled."
    cursor_menu " " choice "Enable Wake on LAN" "Cancel"
    if [ "$choice" = "Enable Wake on LAN" ]; then
        echo "[Unit]
Description=Enable Wake-on-LAN
After=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -s $interface wol g

[Install]
WantedBy=network-online.target" | tee "$service_file_temp" > /dev/null
        #sudo systemctl daemon-reload
        #sudo systemctl enable wol.service
        printf " 🔐 " ; sudo mv -f $service_file_temp $service_file ; sudo systemctl daemon-reload ; sudo systemctl enable wol.service
        echo "Interface: $interface, MAC: $mac"
        echo "Wake on LAN service created and enabled on ethernet port."
    fi
fi
