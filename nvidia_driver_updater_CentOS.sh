#!/bin/bash

usage() {
         echo "Usage: $0 [-u|--uninstall] [-h|--help]"
         echo
         echo "-u, --uninstall		undo everything this script does"
         echo "-h, --help		display this usage guide"
}

uninstall() {
	[ -e /usr/src/nvidia/nvidia_update.sh ] && sudo rm /usr/src/nvidia/nvidia_update.sh
	[ -e /etc/kernel/postinst.d/nvidia ] && sudo rm /etc/kernel/postinst.d/nvidia
	#Will only delete /etc/kernel/* if it's empty which it will be if the user added no
	#extra scripts to the directory
	[ -d /etc/kernel/postinst.d/ ] && sudo rmdir /etc/kernel/postinst.d 2>/dev/null
	[ -d /etc/kernel/ ] && sudo rmdir /etc/kernel 2>/dev/null

	#Delete rc.local changes
	sed -i --follow-symlinks '/nvidia/d' /etc/rc.local

	#Undo grub.conf changes
	GRUB_CONF=$(find /boot/grub/ -iname "*.orig")
	if [[ -n $GRUB_CONF ]]
	then
		rm ${GRUB_CONF%.orig}
		mv ${GRUB_CONF} ${GRUB_CONF%.orig}
	fi

	if [ -e /usr/src/nvidia/nvidia-driver ]
	then
		echo -n "Do you want to remove the NVIDIA driver that you downloaded and renamed (/usr/src/nvidia/nvidia-driver)? [Y/n]: " | fmt -w `tput cols`
		read answer
	
		case "$answer" in
			""|y|Y)
			echo "Removing /usr/src/nvidia/nvidia-driver"
			sudo rm /usr/src/nvidia/nvidia-driver
			;;
			*)
			echo "You chose NOT to remove /usr/src/nvidia/nvidia-driver. If you chose to do so manually in the future, you can safely remove /usr/src/nvidia, as this is a folder this script created." | fmt -w `tput cols`
			DNR='true'
			;;
		esac
	fi

	if [[ "$DNR" != "true" ]]
	then
		[ -d /usr/src/nvidia ] && sudo rmdir /usr/src/nvidia 2>/dev/null
	fi

	echo "Uninstall complete"
}

#Check number of arguments
if [[ "$#" -gt 1 ]]
then
	usage
	exit 1
fi

#Check options
case "$1" in
	"")
	;;
	--uninstall|-u)
	uninstall
	exit 0
	;;
	--help|-h)
	usage
	exit 0
	;;
	*)
	echo "Unknown argument: $1"
	usage
	exit 1
	;;
esac


clear
[ ! -d /usr/src/nvidia/ ] && sudo mkdir /usr/src/nvidia/

[ -e /usr/src/nvidia/nvidia-driver ] || { echo 'You must first download the right NVIDIA driver from http://www.nvidia.com/Download/index.aspx. It will be named something similar to "NVIDIA-Linux-x86_64-319.17.run". Rename the file to "nvidia-driver" and move it to /usr/src/nvidia/. Once you have done this, run this script again.' | fmt -w `tput cols`; exit 1; }

sudo chmod a+x /usr/src/nvidia/nvidia-driver

(
cat << 'nvidia_update'
#!/bin/bash
/usr/src/nvidia/nvidia-driver --update
echo "If the driver installed fine, you should reboot now"
sleep 5
#Undo grub.conf changes
GRUB_CONF=$(find /boot/grub/ -iname "*.orig")
if [[ -n $GRUB_CONF ]]
then
	rm ${GRUB_CONF%.orig}
	mv ${GRUB_CONF} ${GRUB_CONF%.orig}
fi
#Delete rc.local changes
sed -i --follow-symlinks '/nvidia/d' /etc/rc.local
nvidia_update
) | sudo tee /usr/src/nvidia/nvidia_update.sh >/dev/null

sudo chmod a+x /usr/src/nvidia/nvidia_update.sh

sudo mkdir -p /etc/kernel/postinst.d/

(
cat << 'postinst'
#!/bin/bash
echo '/usr/src/nvidia/nvidia_update.sh' >> /etc/rc.local
sed -i.orig -e 's/ quiet//g' -e 's/ rhgb//g' -e 's/ splash//g' $(find /boot/grub/ ! -type l -name 'grub.cfg' -o ! -type l -name 'menu.lst' -o ! -type l -name 'grub.conf')
postinst
) | sudo tee /etc/kernel/postinst.d/nvidia >/dev/null

sudo chmod a+x /etc/kernel/postinst.d/nvidia

echo "Installation complete. The next time your kernel updates, as soon as you reboot, the latest nvidia driver will be downloaded and installed. Note, although this script attempts to temporarily disable the splash screen on some distributions so that you can actually see the driver installing and answer its questions, you may need to hit Esc on some distros after the reboot to disable the splash screen manually." | fmt -w `tput cols`