#!/bin/sh -e
#
# Copyright (c) 2014-2016 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			echo "Patching: /etc/profile"
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

	echo "" >> /etc/securetty
	echo "#USB Gadget Serial Port" >> /etc/securetty
	echo "ttyGS0" >> /etc/securetty

    	#add a2dp users to root group
    	usermod -a -G bluetooth root
    	usermod -a -G pulse root
   	usermod -a -G pulse-access root    
}
setup_network () {
	wfile="/etc/NetworkManager/NetworkManager.conf"
	echo "Patching: ${wfile}"
	echo "[main]" > ${wfile}
	echo "plugins=ifupdown,keyfile" >>  ${wfile}
	echo "" >>  ${wfile}
	echo "[ifupdown]" >>  ${wfile}
	echo "managed=false" >>  ${wfile}
	echo ""  >>  ${wfile}
	echo "[device]" >>  ${wfile}
	echo "wifi.scan-rand-mac-address=no" >>  ${wfile}
	echo ""  >>  ${wfile}
	echo "[keyfile]" >> ${wfile}
	echo "unmanaged-devices=interface-name:wlan1" >> ${wfile}
}
setup_dhcp_server () {
	echo "use wlan1 and access point network interface"
	sed -i -e 's:INTERFACESv4="":INTERFACESv4="wlan1":g' /etc/default/isc-dhcp-server
	wfile="/etc/dhcp/dhcpd.conf"
	sed -i -e 's:option domain-name "example.org";::g' ${wfile}
	sed -i -e 's:option domain-name-servers ns1.example.org, ns2.example.org;::g' ${wfile}
	sed -i -e 's:#authoritative;:authoritative;:g' ${wfile}
	echo "subnet 192.168.42.0 netmask 255.255.255.0 {" >> ${wfile}
	echo "range 192.168.42.10 192.168.42.50;"    >>  ${wfile}
	echo "option broadcast-address 192.168.42.255;"    >>  ${wfile}
	echo "option routers 192.168.42.1;"    >>  ${wfile}
	echo "default-lease-time 600;"    >>  ${wfile}
	echo "max-lease-time 7200;"    >>  ${wfile}
	echo "option domain-name \"local\";"    >>  ${wfile}
	echo "option domain-name-servers 8.8.8.8, 8.8.4.4;"    >>  ${wfile}
	echo "}"    >>  ${wfile}
	
}
setup_desktop () {
	if [ -d /etc/X11/ ] ; then
		wfile="/etc/X11/xorg.conf"
		echo "Patching: ${wfile}"
		echo "Section \"Monitor\"" > ${wfile}
		echo "        Identifier      \"Builtin Default Monitor\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"Device\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default fbdev Device 0\"" >> ${wfile}

#		echo "        Driver          \"modesetting\"" >> ${wfile}
#		echo "        Option          \"AccelMethod\"   \"none\"" >> ${wfile}
		echo "        Driver          \"fbdev\"" >> ${wfile}

		echo "#HWcursor_false        Option          \"HWcursor\"          \"false\"" >> ${wfile}

		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"Screen\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default fbdev Screen 0\"" >> ${wfile}
		echo "        Device          \"Builtin Default fbdev Device 0\"" >> ${wfile}
		echo "        Monitor         \"Builtin Default Monitor\"" >> ${wfile}
		echo "#DefaultDepth        DefaultDepth    16" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"ServerLayout\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default Layout\"" >> ${wfile}
		echo "        Screen          \"Builtin Default fbdev Screen 0\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
	fi

	wfile="/etc/lightdm/lightdm.conf"
	if [ -f ${wfile} ] ; then
		echo "Patching: ${wfile}"
		sed -i -e 's:#autologin-user=:autologin-user='$rfs_username':g' ${wfile}
		sed -i -e 's:#autologin-session=:autologin-session='$rfs_default_desktop':g' ${wfile}
		sed -i "s|^#autologin-user-timeout=.*|autologin-user-timeout=0|" ${wfile}
		if [ -f /opt/scripts/3rdparty/xinput_calibrator_pointercal.sh ] ; then
			sed -i -e 's:#display-setup-script=:display-setup-script=/opt/scripts/3rdparty/xinput_calibrator_pointercal.sh:g' ${wfile}
		fi
	fi

	#Disable dpms mode and screen blanking
	#Better fix for missing cursor
	wfile="/home/${rfs_username}/.xsessionrc"
	echo "#!/bin/sh" > ${wfile}
	echo "" >> ${wfile}
	echo "xset -dpms" >> ${wfile}
	echo "xset s off" >> ${wfile}
	echo "xsetroot -cursor_name left_ptr" >> ${wfile}
	chown -R ${rfs_username}:${rfs_username} ${wfile}

#	#Disable LXDE's screensaver on autostart
#	if [ -f /etc/xdg/lxsession/LXDE/autostart ] ; then
#		sed -i '/xscreensaver/s/^/#/' /etc/xdg/lxsession/LXDE/autostart
#	fi

	#echo "CAPE=cape-bone-proto" >> /etc/default/capemgr

#	#root password is blank, so remove useless application as it requires a password.
#	if [ -f /usr/share/applications/gksu.desktop ] ; then
#		rm -f /usr/share/applications/gksu.desktop || true
#	fi

#	#lxterminal doesnt reference .profile by default, so call via loginshell and start bash
#	if [ -f /usr/bin/lxterminal ] ; then
#		if [ -f /usr/share/applications/lxterminal.desktop ] ; then
#			sed -i -e 's:Exec=lxterminal:Exec=lxterminal -l -e bash:g' /usr/share/applications/lxterminal.desktop
#			sed -i -e 's:TryExec=lxterminal -l -e bash:TryExec=lxterminal:g' /usr/share/applications/lxterminal.desktop
#		fi
#	fi

}
setup_bluetooth_audio(){
    wfile="/etc/dbus-1/system.d/ofono.conf"
    #delete busconfig first
    sed -i 's:</busconfig>::g' ${wfile}

    #At the end of an additional
    sed -i '$a <policy user="pulse">' ${wfile}
    
    #At the end of an additional
    sed -i '$a     <allow send_destination="org.ofono"/>' ${wfile}

    #At the end of an additional
    sed -i '$a     </policy>' ${wfile}

    #At the end of an additional
    sed -i '$a     </busconfig>' ${wfile}
}

setup_x11vnc (){
	echo "install x11vnc service"
	wfile="/lib/systemd/system/x11vnc.service"
	echo "[Unit]"  >> ${wfile}
	echo "Description=Start x11vnc at startup."  >> ${wfile}
	echo "After=multi-user.target" >> ${wfile}
	echo " "  >> ${wfile}
	echo "[Service] "  >> ${wfile}
	echo "Type=simple"  >> ${wfile}
	echo "ExecStartPre=/usr/bin/x11vnc -storepasswd respeaker /etc/vncpasswd"  >> ${wfile}
	echo "ExecStart=/usr/bin/x11vnc  -auth guess -forever -loop -noxdamage -noxrecord -repeat -rfbauth /etc/vncpasswd -rfbport 5900 -shared"  >> ${wfile}
	echo " "  >> ${wfile}
	echo "[Install]"   >> ${wfile}
	echo "WantedBy=multi-user.target"  >> ${wfile}
	if [ -f /etc/lightdm/lightdm.conf ] ; then
		systemctl enable x11vnc.service || true
	fi	
}
setup_pulseaudio () {
    #add pulseaudio service
	echo "setup pulseaudio"
    wfile="/lib/systemd/system/pulseaudio.service"
    echo "[Unit]" > ${wfile}
    echo "Description=Pulse Audio" >> ${wfile}
    echo "After=bluetooth.service " >> ${wfile}
    echo "[Service]" >> ${wfile}
    echo "Type=simple" >> ${wfile}
    echo "ExecStart=/usr/bin/pulseaudio --system --disallow-exit --disable-shm" >> ${wfile}
    echo "[Install]" >> ${wfile}
    echo "WantedBy=multi-user.target" >> ${wfile}
   
   	if [ ! -f /etc/lightdm/lightdm.conf ] ; then
		 systemctl enable pulseaudio.service || true
	fi	 	
	echo "add default pulseaudio setting"
	unset wfile
	wfile="/etc/pulse/daemon.conf"
	sed -i -e 's:; default-sample-rate = 44100:default-sample-rate = 48000:g' ${wfile}
	sed -i -e 's:; alternate-sample-rate = 48000:default-sample-rate = 48000:g' ${wfile}

}
install_git_repos () {
	echo "install_git_repos: do nothing"
}

install_build_pkgs () {
	cd /opt/
	cd /
}

other_source_links () {
	echo "other_source_links"
	echo "install python-bluezero"
	cd /opt/
	git clone https://github.com/ukBaz/python-bluezero
	cd python-bluezero
	pip3 install -U .
	cd ../ && rm -rf /opt/python-bluezero 
}

unsecure_root () {
#	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
#	sed -i -e 's:'$root_password'::g' /etc/shadow

#	if [ -f /etc/ssh/sshd_config ] ; then
#		#Make ssh root@beaglebone work..
#		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
#		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
#		#Starting with Jessie:
#		sed -i -e 's:PermitRootLogin without-password:PermitRootLogin yes:g' /etc/ssh/sshd_config
#	fi

	if [ -d /etc/sudoers.d/ ] ; then
		#Don't require password for sudo access
		echo "${rfs_username} ALL=NOPASSWD: ALL" >/etc/sudoers.d/${rfs_username}
		chmod 0440 /etc/sudoers.d/${rfs_username}
	fi
}

setup_os_release () {
	wfile="/etc/os-release"
	echo "BOARD_NAME=\"ReSpeaker V2\"" >> ${wfile}
	echo "BOARD=respeakerv2" >> ${wfile}
	echo "BOARDFAMILY=rockchip" >> ${wfile}
	echo "VERSION=9" >> ${wfile}
	echo "LINUXFAMILY=rockchip" >> ${wfile}
	echo "BRANCH=default" >> ${wfile}
	echo "ARCH=arm" >> ${wfile}
	echo "IMAGE_TYPE=stable" >> ${wfile}
	echo "BOARD_TYPE=conf" >> ${wfile}
}


is_this_qemu

setup_system
setup_network
setup_desktop
setup_bluetooth_audio
setup_x11vnc
setup_pulseaudio
setup_dhcp_server
setup_os_release

if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
fi
#install_build_pkgs
other_source_links
#unsecure_root
#
