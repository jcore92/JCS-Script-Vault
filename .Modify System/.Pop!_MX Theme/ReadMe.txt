Run these commands below to backup the XFCE icons, themes, and the XFCE config files:
==================================================================================================
tar -czvf xfce-themes-icons.tar.gz ~/.local/share/themes ~/.local/share/icons
tar -czvf xfce-config.tar.gz ~/.config/xfce4

Run these commands below to restore the XFCE icons, themes, and the XFCE config files to Home:
==================================================================================================
tar -xzvf xfce-themes-icons.tar.gz -C ~/
tar -xzvf xfce-config.tar.gz -C ~/   



Run the command below to BACKUP ALL XFCE icons/themes and ALL XFCE config files incl bash prefs:
==================================================================================================
tar -czvf xfce-full-backup.tar.gz \
  ~/.local/share/themes \
  ~/.local/share/icons \
  ~/.config/xfce4 \
  ~/.config/bash-config \
  ~/.bashrc \
  ~/.bash_aliases \
  ~/.dircolors \
  ~/.local/share/xfce4/terminal/colorschemes

Run the command below to RESTORE ALL XFCE icons/themes and ALL XFCE config files incl bash prefs:
==================================================================================================
#tar -xzvf xfce-full-backup.tar.gz -C ~/
#tar -xzvf xfce-full-backup.tar.gz -C /home/$USER

mkdir '/tmp/Pop!_MX_Theme' ; tar -xzvf xfce-full-backup.tar.gz -C '/tmp/Pop!_MX_Theme'

cp -rvf /tmp/Pop\!_MX_Theme/home/*/.config /tmp/Pop\!_MX_Theme/home/*/.local /tmp/Pop\!_MX_Theme/home/*/.bash_aliases /tmp/Pop\!_MX_Theme/home/*/.bashrc /home/$USER/

mkdir -p ~/.config/autostart
cp /etc/xdg/autostart/xfce-superkey.desktop ~/.config/autostart/
echo "Hidden=true" >> ~/.config/autostart/xfce-superkey.desktop   
