Для того, чтобы установить DEB-пакеты NavDat в ручном режиме необходимо сделать сдежующее:

1. Установить зависимости:
				sudo apt-get update
				sudo apt-get install lightdm mc vim-nox libcairo2-dev xmlto asciidoc cmake lua5.1 lua-ldoc \ 
				libxcb-xtest0-dev libxcb-icccm4-dev libxcb-randr0-dev libxcb-keysyms1-dev libxcb-xinerama0-dev \ 
				libxcb-xrm-dev liblua5.1-dev libdbus-1-dev libxdg-basedir-dev libstartup-notification0-dev \ 
				imagemagick libxcb1-dev libxcb-shape0-dev libxcb-util0-dev libxcb-cursor-dev libgdk-pixbuf2.0-dev \ 
				libglib2.0-dev awesome-extra compton gnome-screensaver gnome-session gnome-settings-daemon \ 
				gnome-themes-standard network-manager-gnome unity-control-center unity-settings-daemon zenity \ 
				python-dbus python-glade2 python-gtk2 xfonts-75dpi xfonts-100dpi unicode libpng12-0 libpng-dev \ 
				autotools-dev debhelper dh-autoreconf g++ libgtk2.0-dev libpng12-dev libx11-dev libxcursor-dev libxext-dev

2. Затем необходимо распокавать архив bortNFVSEGEI и проделать следующие шаги:
				cd bortNFVSEGEI
				sudo dpkg -i libfox-gt_1.6.0-2navdat1_amd64.deb libfox-gt-dev_1.6.0-2navdat1_amd64.deb fox-gt_1.6.0-2navdat1_amd64.deb \ navdat-bortd_0.2.12_amd64.deb navdat-help_0.2.12_all.deb navdat-bortcfg_0.2.12_all.deb \ navdat-clients-tvisor_0.2.12_amd64.deb navdat-clients-specview_0.2.12_amd64.deb navdat-clients-gtmag_0.2.12_amd64.deb \ 
				navdat-clients-equator_0.2.12_amd64.deb navdat-clients-common_0.2.12_amd64.deb navdat-full_0.2.12_all.deb \ 
				libxcb-xrm0_1.0-0~xenial0ubuntu1_amd64.deb libxcb-xrm-dev_1.0-0~xenial0ubuntu1_amd64.deb lua-lgi_0.9.1-1navdat1_amd64.deb \ 
				lua-lgi-dbg_0.9.1-1navdat1_amd64.deb lua-lgi-dev_0.9.1-1navdat1_amd64.deb awesome_4.2.0-0navdat0_amd64.deb \ 
				navdat-awesome-config_0.0.4ubuntu2_all.deb navdat-awesome-config_0.0.5_all.deb navdat-user_0.6.1ubuntu10_all.deb

ПОСЛЕ ПОЛНОЙ УСТАНОВКИ НЕОБХОДИМО ПЕРЕЗАГРУЗИТЬ КОМПЬЮТЕР 