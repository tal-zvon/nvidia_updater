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
	sudo sed -i --follow-symlinks '/chvt/d' /etc/rc.local

	#Delete /root/.bash_profile changes
	sed -i '/nvidia_update/d' /root/.bash_profile

	#Delete /bin/auto-login
	[ -e /bin/auto-login ] && sudo rm -f /bin/auto-login

	#Delete the actual nvidia driver that was downloaded from the nvidia website
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
			echo "You chose NOT to remove /usr/src/nvidia/nvidia-driver. If you want to do so manually in the future, you can safely remove /usr/src/nvidia, as this is a folder this script created." | fmt -w `tput cols`
			DNR='true'
			;;
		esac
	fi

	#If the driver was removed, delete the /usr/src/nvidia folder that this script created
	if [[ "$DNR" != "true" ]]
	then
		[ -d /usr/src/nvidia ] && sudo rmdir /usr/src/nvidia 2>/dev/null
	fi

	echo
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

[ -e /usr/src/nvidia/nvidia-driver ] || { echo 'You must first download the right NVIDIA driver from http://www.nvidia.com/Download/index.aspx. It will be named something similar to "NVIDIA-Linux-x86_64-319.17.run". Rename the file to "nvidia-driver" and move it to /usr/src/nvidia/. Once you have done this, run this script again. There is no need to keep this file up to date since the script will download the newest version of it from the NVIDIA website if it is outdated.' | fmt -w `tput cols`; exit 1; }

sudo chmod a+x /usr/src/nvidia/nvidia-driver

#The auto-login script. Needed to automatically login to root on tty instead of asking for user/pass
(
cat << 'auto-login'
#include <unistd.h>
int main(void) 
{
   execlp("login", "login", "-f", "root", NULL);
}
auto-login
) | sudo tee /usr/src/nvidia/auto-login.c >/dev/null

sudo gcc -O3 -o /bin/auto-login /usr/src/nvidia/auto-login.c && sudo rm -f /usr/src/nvidia/auto-login.c

#The actual update script
(
cat << 'nvidia_update'
#!/bin/bash

#The --update arg downloads the latest version of the driver from NVIDIA
#if this one is outdated
/usr/src/nvidia/nvidia-driver --update

#Undo tty.conf changes
TTY_CONF=/etc/init/tty.conf.orig
if [[ -e $TTY_CONF ]]
then
        rm ${TTY_CONF%.orig}
        mv ${TTY_CONF} ${TTY_CONF%.orig}
fi

#Delete rc.local changes
sed -i --follow-symlinks '/chvt/d' /etc/rc.local

#Delete /root/.bash_profile changes
sed -i '/nvidia_update/d' /root/.bash_profile

#Reboot
echo -n "Do you want to reboot? [Y/n]: " | fmt -w `tput cols`
read answer
	
case "$answer" in
	""|y|Y)
	reboot
	;;
	*)
	/usr/bin/chvt 3
	;;
esac
nvidia_update
) | sudo tee /usr/src/nvidia/nvidia_update.sh >/dev/null

sudo chmod a+x /usr/src/nvidia/nvidia_update.sh

#The /etc/kernel/postinst.d/ directory contains scripts that automatically get run
#immediately after a new kernel has been installed
sudo mkdir -p /etc/kernel/postinst.d/

(
cat << 'postinst'
#!/bin/bash

#Make OS switch to tty2 on boot. tty2 is where the nvidia driver will be installed from
#The "sleep 5" bit is necessary because without it, CentOS runs the GUI on tty2
echo '{ /bin/sleep 5; /usr/bin/chvt 2; } &' >> /etc/rc.local

sed -i.orig '/mingetty/d' /etc/init/tty.conf

#Modify tty2 to run the nvidia_update.sh script instead of asking for login credentials
(
cat << "TTY_CODE"
script
	if [ "$TTY" = "/dev/tty2" ]
	then
		/sbin/agetty -8 38400 ${TTY#/dev/} -n -l /bin/auto-login
	else
		exec /sbin/mingetty $TTY
	fi
end script
TTY_CODE
) >> /etc/init/tty.conf


#Modify /root/.bash_profile to run nvidia_update script
echo '[ `tty` = '/dev/tty2' ] && /usr/src/nvidia/nvidia_update.sh' >> /root/.bash_profile
postinst
) | sudo tee /etc/kernel/postinst.d/nvidia >/dev/null

sudo chmod a+x /etc/kernel/postinst.d/nvidia

echo "Installation complete. The next time your kernel updates, as soon as you reboot, the latest nvidia driver will be downloaded and installed. Note, although this script attempts to temporarily disable the splash screen on some distributions so that you can actually see the driver installing and answer its questions, you may need to hit Esc on some distros after the reboot to disable the splash screen manually." | fmt -w `tput cols`
