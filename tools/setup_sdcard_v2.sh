#!/bin/bash -e
# 
# 
# Author: Baozhu Zuo<zuobaozhu@gmail.com>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 


#REQUIREMENTS:
#uEnv.txt bootscript support


#Defaults
ROOTFS_TYPE=ext4

DIR="$PWD"
TEMPDIR=$(mktemp -d)

keep_net_alive () {
	while : ; do
		echo "syncing media... $*"
		sleep 300
	done
}
keep_net_alive & KEEP_NET_ALIVE_PID=$!
cleanup_keep_net_alive () {
	[ -e /proc/$KEEP_NET_ALIVE_PID ] && kill $KEEP_NET_ALIVE_PID
}
trap cleanup_keep_net_alive EXIT

is_element_of () {
	testelt=$1
	for validelt in $2 ; do
		[ $testelt = $validelt ] && return 0
	done
	return 1
}

#########################################################################
#
#  Define valid "--rootfs" root filesystem types.
#
#########################################################################

VALID_ROOTFS_TYPES="ext2 ext3 ext4"

is_valid_rootfs_type () {
	if is_element_of $1 "${VALID_ROOTFS_TYPES}" ] ; then
		return 0
	else
		return 1
	fi
}

check_root () {
	if ! [ $(id -u) = 0 ] ; then
		echo "$0 must be run as sudo user or root"
		exit 1
	fi
}

find_issue () {
	check_root

	ROOTFS=$(ls "${DIR}/" | grep rootfs)
	if [ "x${ROOTFS}" != "x" ] ; then
		echo "Debug: ARM rootfs: ${ROOTFS}"
	else
		echo "Error: no armel-rootfs-* file"
		echo "Make sure your in the right dir..."
		exit
	fi

	unset has_uenvtxt
	unset check
	check=$(ls "${DIR}/" | grep uEnv.txt | grep -v post-uEnv.txt | head -n 1)
	if [ "x${check}" != "x" ] ; then
		echo "Debug: image has pre-generated uEnv.txt file"
		has_uenvtxt=1
	fi

	unset has_post_uenvtxt
	unset check
	check=$(ls "${DIR}/" | grep post-uEnv.txt | head -n 1)
	if [ "x${check}" != "x" ] ; then
		echo "Debug: image has post-uEnv.txt file"
		has_post_uenvtxt="enable"
	fi
}

check_for_command () {
	if ! which "$1" > /dev/null ; then
		echo -n "You're missing command $1"
		NEEDS_COMMAND=1
		if [ -n "$2" ] ; then
			echo -n " (consider installing package $2)"
		fi
		echo
	fi
}

detect_software () {
	unset NEEDS_COMMAND

	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command git git
	check_for_command partprobe parted

	if [ "x${build_img_file}" = "xenable" ] ; then
		check_for_command kpartx kpartx
	fi

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Debian/Ubuntu: sudo apt-get install dosfstools git-core kpartx wget parted"
		echo "Fedora: yum install dosfstools dosfstools git-core wget"
		echo "Gentoo: emerge dosfstools git wget"
		echo ""
		exit
	fi

	unset test_sfdisk
	test_sfdisk=$(LC_ALL=C sfdisk -v 2>/dev/null | grep 2.17.2 | awk '{print $1}')
	if [ "x${test_sdfdisk}" = "xsfdisk" ] ; then
		echo ""
		echo "Detected known broken sfdisk:"
		echo ""
		exit
	fi

	unset wget_version
	wget_version=$(LC_ALL=C wget --version | grep "GNU Wget" | awk '{print $3}' | awk -F '.' '{print $2}' || true)
	case "${wget_version}" in
	12|13)
		#wget before 1.14 in debian does not support sni
		echo "wget: [`LC_ALL=C wget --version | grep \"GNU Wget\" | awk '{print $3}' || true`]"
		echo "wget: [this version of wget does not support sni, using --no-check-certificate]"
		echo "wget: [http://en.wikipedia.org/wiki/Server_Name_Indication]"
		dl="wget --no-check-certificate"
		;;
	*)
		dl="wget"
		;;
	esac

	dl_continue="${dl} -c"
	dl_quiet="${dl} --no-verbose"
}



usage () {
	echo "usage: sudo $(basename $0) --mmc /dev/sdX --dtb <dev board>"
	#tabed to match 
		cat <<-__EOF__
			-----------------------------
			Required Options:
			--mmc </dev/sdX> or --img <filename.img>

			--dtb <dev board>

			Additional Options:
			        -h --help

			--probe-mmc
			        <list all partitions: sudo ./setup_sdcard.sh --probe-mmc>

			__EOF__
	exit
}

checkparm () {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}


check_dtb_board () {
	error_invalid_dtb=1

	#/hwpack/${dtb_board}.conf
	unset leading_slash
	leading_slash=$(echo ${dtb_board} | grep "/" || unset leading_slash)
	if [ "${leading_slash}" ] ; then
		dtb_board=$(echo "${leading_slash##*/}")
	fi

	#${dtb_board}.conf
	dtb_board=$(echo ${dtb_board} | awk -F ".conf" '{print $1}')
	if [ -f "${DIR}"/hwpack/${dtb_board}.conf ] ; then
		. "${DIR}"/hwpack/${dtb_board}.conf

		unset error_invalid_dtb
	else
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--dtb ${dtb_board}] option..
			Please rerun $(basename $0) with a valid [--dtb <device>] option from the list below:
			-----------------------------
		__EOF__
		cat "${DIR}"/hwpack/*.conf | grep supported
		echo "-----------------------------"
		exit
	fi
}

dl_bootloader () {
	echo ""
	echo "Downloading ${dtb_board}'s Bootloader to ${TEMPDIR}/dl/"
	echo "-----------------------------"	

	mkdir -p ${TEMPDIR}/dl/
	cp ${DIR}/dl/*.img ${TEMPDIR}/dl/

	# ${dl} --directory-prefix="${TEMPDIR}/dl/" ${conf_bl_http}/${idbloader_name}
	# echo "-----------------------------------------------------------------------------"	
	# echo "blank_idbloader Bootloader: ${idbloader_name}"

	# ${dl} --directory-prefix="${TEMPDIR}/dl/" ${conf_bl_http}/${uboot_name}
	# echo "-----------------------------------------------------------------------------"
	# echo "blank_uboot Bootloader: ${uboot_name}"

	# ${dl} --directory-prefix="${TEMPDIR}/dl/" ${conf_bl_http}/${trust_name}
	# echo "-----------------------------------------------------------------------------"
	# echo "blank_trust Bootloader: ${trust_name}"

}

populate_loaders(){
	echo "Populating idbloader trust uboot Partition"
	echo "-----------------------------------------------------------------------------"

	echo "dd if=${TEMPDIR}/dl/${idbloader_name} of=${media} seek=${idbloader_start}"
	dd if=${TEMPDIR}/dl/${idbloader_name} of=${media} seek=${idbloader_start}
	echo "-----------------------------------------------------------------------------"

	echo "dd if=${TEMPDIR}/dl/${uboot_name} of=${media} seek=${uboot_start}"
	dd if=${TEMPDIR}/dl/${uboot_name} of=${media} seek=${uboot_start}
	echo "-----------------------------------------------------------------------------"

	echo "dd if=${TEMPDIR}/dl/${trust_name} of=${media} seek=${trust_start}"
	dd if=${TEMPDIR}/dl/${trust_name} of=${media} seek=${trust_start}
	echo "-----------------------------------------------------------------------------"

	echo "Finished populating idbloader trust  uboot Partition"
	echo "-----------------------------------------------------------------------------"
}

sfdisk_partition_layout () {

	sfdisk_options="--force --in-order --Linux --unit M"
	sfdisk_boot_startmb="${conf_boot_startmb}"
	sfdisk_boot_size_mb="${conf_boot_sizemb}"
	sfdisk_var_size_mb="${conf_var_startmb}"
	if [ "x${option_ro_root}" = "xenable" ] ; then
		sfdisk_var_startmb=$(($sfdisk_boot_startmb + $sfdisk_boot_size_mb))
		sfdisk_rootfs_startmb=$(($sfdisk_var_startmb + $sfdisk_var_size_mb))
	else
		sfdisk_rootfs_startmb=$(($sfdisk_boot_startmb + $sfdisk_boot_size_mb))
	fi
	echo "sfdisk_rootfs_startmb: ${sfdisk_rootfs_startmb}M"

	test_sfdisk=$(LC_ALL=C sfdisk --help | grep -m 1 -e "--in-order" || true)
	if [ "x${test_sfdisk}" = "x" ] ; then
		echo "log: sfdisk: 2.26.x or greater detected"
		sfdisk_options="--force ${sfdisk_gpt}"
		sfdisk_boot_startmb="${sfdisk_boot_startmb}M"
		sfdisk_boot_size_mb="${sfdisk_boot_size_mb}M"
		sfdisk_var_startmb="${sfdisk_var_startmb}M"
		sfdisk_var_size_mb="${sfdisk_var_size_mb}M"
		sfdisk_rootfs_startmb="${sfdisk_rootfs_startmb}M"
	fi


	echo "sfdisk: [$(LC_ALL=C sfdisk --version)]"
	echo "sfdisk: [${sfdisk_options} ${media}]"
	echo "sfdisk: [${sfdisk_boot_startmb},${sfdisk_boot_size_mb},${sfdisk_fstype},*]"
	echo "sfdisk: [${sfdisk_rootfs_startmb},,,-]"

	LC_ALL=C sfdisk ${sfdisk_options} "${media}" <<-__EOF__
		${sfdisk_boot_startmb},${sfdisk_boot_size_mb},${sfdisk_fstype},*
		${sfdisk_rootfs_startmb},,,-
	__EOF__
	sync
}

format_partition_error () {
	echo "LC_ALL=C ${mkfs} ${mkfs_partition} ${mkfs_label}"
	echo "Failure: formating partition"
	exit
}

format_partition_try2 () {
	unset mkfs_options
	if [ "x${mkfs}" = "xmkfs.ext4" ] ; then
		mkfs_options="${ext4_options}"
	fi

	echo "-----------------------------"
	echo "BUG: [${mkfs_partition}] was not available so trying [${mkfs}] again in 5 seconds..."
	partprobe ${media}
	sync
	sleep 5
	echo "-----------------------------"

	echo "Formating with: [${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label}]"
	echo "-----------------------------"
	LC_ALL=C ${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label} || format_partition_error
	sync
}

format_partition () {
	unset mkfs_options
	if [ "x${mkfs}" = "xmkfs.ext4" ] ; then
		mkfs_options="${ext4_options}"
	fi

	echo "Formating with: [${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label}]"
	echo "-----------------------------"
	LC_ALL=C ${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label} || format_partition_try2
	sync
}

format_boot_partition () {
	mkfs_partition="${media_prefix}${media_boot_partition}"

	if [ "x${conf_boot_fstype}" = "xfat" ] ; then
		mount_partition_format="vfat"
		mkfs="mkfs.vfat -F 16"
		mkfs_label="-n ${BOOT_LABEL}"
	else
		mount_partition_format="${conf_boot_fstype}"
		mkfs="mkfs.${conf_boot_fstype}"
		mkfs_label="-L ${BOOT_LABEL}"
	fi

	format_partition
}

format_rootfs_partition () {
	if [ "x${option_ro_root}" = "xenable" ] ; then
		mkfs="mkfs.ext2"
	else
		mkfs="mkfs.${ROOTFS_TYPE}"
	fi
	mkfs_partition="${media_prefix}${media_rootfs_partition}"
	mkfs_label="-L ${ROOTFS_LABEL}"

	format_partition

	rootfs_drive="${conf_root_device}p${media_rootfs_partition}"

	if [ "x${option_ro_root}" = "xenable" ] ; then

		mkfs="mkfs.${ROOTFS_TYPE}"
		mkfs_partition="${media_prefix}${media_rootfs_var_partition}"
		mkfs_label="-L var"

		format_partition
		rootfs_var_drive="${conf_root_device}p${media_rootfs_var_partition}"
	fi
}


create_partitions () {
	unset bootloader_installed
	unset sfdisk_gpt

	media_boot_partition=1
	media_rootfs_partition=2

	unset ext4_options

	if [ ! "x${uboot_supports_csum}" = "xtrue" ] ; then
		#Debian Stretch, mfks.ext4 default to metadata_csum, 64bit disable till u-boot works again..
		unset ext4_options
		unset test_mke2fs
		LC_ALL=C mkfs.ext4 -V &> /tmp/mkfs
		test_mkfs=$(cat /tmp/mkfs | grep mke2fs | grep 1.43 || true)
		if [ "x${test_mkfs}" = "x" ] ; then
			unset ext4_options
		else
			ext4_options="-O ^metadata_csum,^64bit"
		fi
	fi


	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"

	conf_boot_endmb=${conf_boot_endmb:-"96"}
	conf_boot_fstype=${conf_boot_fstype:-"fat"}
	sfdisk_fstype=${sfdisk_fstype:-"0xE"}
	BOOT_LABEL=${config_boot_label:-"BOOT"}
	ROOTFS_LABEL=${config_rootfs_label:-"ROOTFS"}
	sfdisk_partition_layout


	echo "Partition Setup:"
	echo "-----------------------------"
	LC_ALL=C fdisk -l "${media}"
	echo "-----------------------------"

	if [ "x${build_img_file}" = "xenable" ] ; then
		media_loop=$(losetup -f || true)
		if [ ! "${media_loop}" ] ; then
			echo "losetup -f failed"
			echo "Unmount some via: [sudo losetup -a]"
			echo "-----------------------------"
			losetup -a
			echo "sudo kpartx -d /dev/loopX ; sudo losetup -d /dev/loopX"
			echo "-----------------------------"
			exit
		fi

		losetup ${media_loop} "${media}"
		kpartx -av ${media_loop}
		sleep 1
		sync
		test_loop=$(echo ${media_loop} | awk -F'/' '{print $3}')
		if [ -e /dev/mapper/${test_loop}p${media_boot_partition} ] && [ -e /dev/mapper/${test_loop}p${media_rootfs_partition} ] ; then
			media_prefix="/dev/mapper/${test_loop}p"
		else
			ls -lh /dev/mapper/
			echo "Error: not sure what to do (new feature)."
			exit
		fi
	else
		partprobe ${media}
	fi

	if [ "x${media_boot_partition}" = "x${media_rootfs_partition}" ] ; then
		mount_partition_format="${ROOTFS_TYPE}"
		format_rootfs_partition
	else
		format_boot_partition
		format_rootfs_partition
	fi
}

kernel_detection () {
	unset has_respeaker_kernel
	unset check
	check=$(ls "${dir_check}" | grep vmlinuz- | grep respeaker | head -n 1)
	if [ "x${check}" != "x" ] ; then
		select_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep respeaker | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${select_kernel}"
		has_respeaker_kernel="enable"
	fi	
}

populate_rootfs () {
	echo "Populating rootfs Partition"
	echo "Please be patient, this may take a few minutes, as its transfering a lot of data.."
	echo "-----------------------------"

	if [ ! -d ${TEMPDIR}/disk ] ; then
		mkdir -p ${TEMPDIR}/disk
	fi

	partprobe ${media}
	if ! mount -t ${ROOTFS_TYPE} ${media_prefix}${media_rootfs_partition} ${TEMPDIR}/disk; then

		echo "-----------------------------"
		echo "BUG: [${media_prefix}${media_rootfs_partition}] was not available so trying to mount again in 5 seconds..."
		partprobe ${media}
		sync
		sleep 5
		echo "-----------------------------"

		if ! mount -t ${ROOTFS_TYPE} ${media_prefix}${media_rootfs_partition} ${TEMPDIR}/disk; then
			echo "-----------------------------"
			echo "Unable to mount ${media_prefix}${media_rootfs_partition} at ${TEMPDIR}/disk to complete populating rootfs Partition"
			echo "Please retry running the script, sometimes rebooting your system helps."
			echo "-----------------------------"
			exit
		fi
	fi

	lsblk | grep -v sr0
	echo "-----------------------------"

	if [ -f "${DIR}/${ROOTFS}" ] ; then
		if which pv > /dev/null ; then
			pv "${DIR}/${ROOTFS}" | tar --numeric-owner --preserve-permissions -xf - -C ${TEMPDIR}/disk/
		else
			echo "pv: not installed, using tar verbose to show progress"
			tar --numeric-owner --preserve-permissions  -xf "${DIR}/${ROOTFS}" -C ${TEMPDIR}/disk/
		fi

		echo "Transfer of data is Complete, now syncing data to disk..."
		echo "Disk Size"
		du -sh ${TEMPDIR}/disk/
		sync
		sync

		echo "-----------------------------"
		if [ -f /usr/bin/stat ] ; then
			echo "-----------------------------"
			echo "Checking [${TEMPDIR}/disk/] permissions"
			/usr/bin/stat ${TEMPDIR}/disk/
			echo "-----------------------------"
		fi

		echo "Setting [${TEMPDIR}/disk/] chown root:root"
		chown root:root ${TEMPDIR}/disk/
		echo "Setting [${TEMPDIR}/disk/] chmod 755"
		chmod 755 ${TEMPDIR}/disk/

		if [ -f /usr/bin/stat ] ; then
			echo "-----------------------------"
			echo "Verifying [${TEMPDIR}/disk/] permissions"
			/usr/bin/stat ${TEMPDIR}/disk/
		fi
		echo "-----------------------------"
	fi

	dir_check="${TEMPDIR}/disk/boot/"
	kernel_detection

	wfile="${TEMPDIR}/disk/boot/uEnv.txt"

	echo "uname_r=${select_kernel}" >> ${wfile}
	echo "#uuid=" >> ${wfile}

	if [ ! "x${dtb}" = "x" ] ; then
		echo "dtb=${dtb}" >> ${wfile}
		echo "#dtb=" >> ${wfile}
	fi
	
	if [  "x${conf_board}" = "xrespeaker_v2" ] ; then
		cmdline="coherent_pool=1M quiet"
	fi
	
	cmdline="${cmdline} init=/lib/systemd/systemd"
	echo "cmdline=${cmdline}" >> ${wfile}


	if [ ! "x${oem_flasher_script}" = "x" ] ; then
		echo "cmdline=init=/opt/scripts/${oem_flasher_script}" >> ${wfile}
	else
		echo "##enable  Flasher:" >> ${wfile}
		echo "##make sure, these tools are installed: dosfstools rsync" >> ${wfile}
		echo "#cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-respeaker.sh" >> ${wfile}
	fi

	board=${conf_board}


	echo "/boot/uEnv.txt---------------"
	cat ${wfile}
	echo "-----------------------------"

	wfile="${TEMPDIR}/disk/boot/SOC.sh"
	cp "${DIR}"/hwpack/${dtb_board}.conf ${wfile}
	echo "/dev/mmcblk1" > ${TEMPDIR}/disk/resizerootfs

	#RootStock-NG
	if [ -f ${TEMPDIR}/disk/etc/rcn-ee.conf ] ; then
		. ${TEMPDIR}/disk/etc/rcn-ee.conf

		mkdir -p ${TEMPDIR}/disk/boot/uboot || true

		wfile="${TEMPDIR}/disk/etc/fstab"
		echo "# /etc/fstab: static file system information." > ${wfile}
		echo "#" >> ${wfile}
		echo "# Auto generated by RootStock-NG: setup_sdcard.sh" >> ${wfile}
		echo "#" >> ${wfile}

		if [ "x${distro}" = "xDebian" ] ; then
			#/etc/inittab is gone in Jessie with systemd...
			if [ -f ${TEMPDIR}/disk/etc/inittab ] ; then
				wfile="${TEMPDIR}/disk/etc/inittab"
				serial_num=$(echo -n "${SERIAL}"| tail -c -1)
				echo "" >> ${wfile}
				echo "T${serial_num}:23:respawn:/sbin/getty -L ${SERIAL} 115200 vt102" >> ${wfile}
				echo "" >> ${wfile}
			fi
		fi

		if [ "x${distro}" = "xUbuntu" ] ; then
			wfile="${TEMPDIR}/disk/etc/init/serial.conf"
			echo "start on stopped rc RUNLEVEL=[2345]" > ${wfile}
			echo "stop on runlevel [!2345]" >> ${wfile}
			echo "" >> ${wfile}
			echo "respawn" >> ${wfile}
			echo "exec /sbin/getty 115200 ${SERIAL}" >> ${wfile}
		fi

		if [ -f ${TEMPDIR}/disk/var/www/index.html ] ; then
			rm -f ${TEMPDIR}/disk/var/www/index.html || true
		fi

		if [ -f ${TEMPDIR}/disk/var/www/html/index.html ] ; then
			rm -f ${TEMPDIR}/disk/var/www/html/index.html || true
		fi
		sync

	fi #RootStock-NG

	if [ ! "x${uboot_name}" = "x" ] ; then
		echo "Backup version of u-boot: /opt/backup/uboot/"
		mkdir -p ${TEMPDIR}/disk/opt/backup/uboot/
		cp -v ${TEMPDIR}/dl/${uboot_name} ${TEMPDIR}/disk/opt/backup/uboot/${uboot_name}
		cp -v ${TEMPDIR}/dl/${idbloader_name} ${TEMPDIR}/disk/opt/backup/uboot/${idbloader_name}
		cp -v ${TEMPDIR}/dl/${atf_name} ${TEMPDIR}/disk/opt/backup/uboot/${atf_name}
	fi

	if [  "x${conf_board}" = "xrespeaker_v2" ] ; then 
		if [ ! -f ${TEMPDIR}/disk/opt/scripts/init-eMMC-flasher-respeaker.sh ] ; then
			mkdir -p  ${TEMPDIR}/disk/opt/scripts/
			git clone https://github.com/Pillar1989/flasher-scripts ${TEMPDIR}/disk/opt/scripts/ --depth 1
			sudo chown -R 1000:1000 ${TEMPDIR}/disk/opt/scripts/
		else
			cd ${TEMPDIR}/disk/opt/scripts/
			git pull
			cd -
			sudo chown -R 1000:1000 ${TEMPDIR}/disk/opt/scripts/
		fi
	fi
	if [ "x${conf_board}" = "xrespeaker_v2" ]; then
		wfile="${TEMPDIR}/disk/lib/udev/rules.d/90-pulseaudio.rules"
		sed -i '/0x384e/a#\ Seeed\ Voicecard' ${wfile}
		sed -i '/Voicecard/aATTR{id}=="seeed8micvoicec",ATTR{number}=="0",ENV{PULSE_PROFILE_SET}="seeed-voicecard.conf"' ${wfile}
	fi





	if [ ! "x${new_hostname}" = "x" ] ; then
		echo "Updating Image hostname too: [${new_hostname}]"

		wfile="/etc/hosts"
		echo "127.0.0.1	localhost" > ${TEMPDIR}/disk${wfile}
		echo "127.0.1.1	${new_hostname}.localdomain	${new_hostname}" >> ${TEMPDIR}/disk${wfile}
		echo "" >> ${TEMPDIR}/disk${wfile}
		echo "# The following lines are desirable for IPv6 capable hosts" >> ${TEMPDIR}/disk${wfile}
		echo "::1     localhost ip6-localhost ip6-loopback" >> ${TEMPDIR}/disk${wfile}
		echo "ff02::1 ip6-allnodes" >> ${TEMPDIR}/disk${wfile}
		echo "ff02::2 ip6-allrouters" >> ${TEMPDIR}/disk${wfile}

		wfile="/etc/hostname"
		echo "${new_hostname}" > ${TEMPDIR}/disk${wfile}
	fi

	# setuid root ping+ping6 - capabilities does not survive tar
	if [ -x  ${TEMPDIR}/disk/bin/ping ] ; then
		echo "making ping/ping6 setuid root"
		chmod u+s ${TEMPDIR}/disk//bin/ping ${TEMPDIR}/disk//bin/ping6
	fi

	cd ${TEMPDIR}/disk/
	sync
	sync

	if [ ! -d ${TEMPDIR}/boot ] ; then
		mkdir -p ${TEMPDIR}/boot
	fi

	if [ "${conf_board}" = "respeaker_v2" ] ; then
		sed -i "s|/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games|/usr/local/bin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games|g" ${TEMPDIR}/disk/etc/profile  
		mv ${TEMPDIR}/disk/boot/* ${TEMPDIR}/boot
	fi



	cd "${DIR}/"

	if [ "x${option_ro_root}" = "xenable" ] ; then
		umount ${TEMPDIR}/disk/var || true
	fi

	umount ${TEMPDIR}/disk || true


	echo "Finished populating rootfs Partition"
	echo "-----------------------------"

	echo "setup_sdcard.sh script complete"
	if [ -f "${DIR}/user_password.list" ] ; then
		echo "-----------------------------"
		echo "The default user:password for this image:"
		cat "${DIR}/user_password.list"
		echo "-----------------------------"
	fi
}

# parse commandline options
while [ ! -z "$1" ] ; do
	case $1 in
	-h|--help)
		usage
		media=1
		;;
	--hostname)
		checkparm $2
		new_hostname="$2"
		;;
	--img|--img-[12468]gb)
		checkparm $2
		name=${2:-image}
		gsize=$(echo "$1" | sed -ne 's/^--img-\([[:digit:]]\+\)gb$/\1/p')
		# --img defaults to --img-2gb
		gsize=${gsize:-2}
		imagename=${name%.img}-${gsize}gb.img
		media="${DIR}/${imagename}"
		build_img_file="enable"
		check_root
		if [ -f "${media}" ] ; then
			rm -rf "${media}" || true
		fi
		#FIXME: (should fit most microSD cards)
		#eMMC: (dd if=/dev/mmcblk1 of=/dev/null bs=1M #MB)
		#Micron   3744MB (bbb): 3925868544 bytes -> 3925.86 Megabyte
		#Kingston 3688MB (bbb): 3867148288 bytes -> 3867.15 Megabyte
		#Kingston 3648MB (x15): 3825205248 bytes -> 3825.21 Megabyte (3648)
		#
		### seek=$((1024 * (700 + (gsize - 1) * 1000)))
		## 1000 1GB = 700 #2GB = 1700 #4GB = 3700
		##  990 1GB = 700 #2GB = 1690 #4GB = 3670
		#
		### seek=$((1024 * (gsize * 850)))
		## x 850 (85%) #1GB = 850 #2GB = 1700 #4GB = 3400
		#
		echo "dd if=/dev/zero of="${media}" bs=1024 count=0 seek=$((1024 * (gsize * 850)))"
		echo "_____________________________________________________________________________"
		dd if=/dev/zero of="${media}" bs=1024 count=0 seek=$((1024 * (gsize * 850)))
		;;
	--dtb)
		checkparm $2
		dtb="$2"
		;;
	--board)
		checkparm $2
		dtb_board="$2"
		dir_check="${DIR}/"
		check_dtb_board
		;;
	--oem-flasher-script)
		checkparm $2
		oem_flasher_script="$2"
		;;
	esac
	shift
done


find_issue
detect_software
dl_bootloader
create_partitions
populate_loaders
populate_rootfs






# if [ "${idbloader_name}" ] || [ "${trust_name}" ] ; then
# 	dl_v2_bootloader
# fi


# if [ ! "x${build_img_file}" = "xenable" ] ; then
# 	unmount_all_drive_partitions
# fi

# if [ "${conf_board}" = "respeaker_v2" ] ; then
# 	create_v2_partitions
# else
# 	create_partitions
# fi  

# if [ ! "x${build_img_file}" = "xenable" ] ; then
# 	unmount_all_drive_partitions
# fi
# populate_loaders
# populate_rootfs
# populate_boot

exit 0
#
