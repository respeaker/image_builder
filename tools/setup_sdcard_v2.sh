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
		respeaker_dt_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep respeaker | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${respeaker_dt_kernel}"
		has_respeaker_kernel="enable"
	fi	
}

kernel_select () {
	unset select_kernel

	if [ "x${conf_kernel}" = "xrespeaker" ] ; then
		if [ "x${has_respeaker_kernel}" = "xenable" ] ; then
			select_kernel="${respeaker_dt_kernel}"
		fi
	fi

	if [ "${select_kernel}" ] ; then
		echo "Debug: using: v${select_kernel}"
	else
		echo "Error: [conf_kernel] not defined [armv7_lpae,armv7,respeaker]..."
		exit
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
	kernel_select

	wfile="${TEMPDIR}/disk/boot/uEnv.txt"
	#echo "#Docs: http://elinux.org/Beagleboard:U-boot_partitioning_layout_2.0" > ${wfile}
	#echo "" >> ${wfile}

	if [ "x${kernel_override}" = "x" ] ; then
		echo "uname_r=${select_kernel}" >> ${wfile}
	else
		echo "uname_r=${kernel_override}" >> ${wfile}
	fi

	echo "#uuid=" >> ${wfile}

	if [ ! "x${dtb}" = "x" ] ; then
		echo "dtb=${dtb}" >> ${wfile}
	else

		if [ ! "x${forced_dtb}" = "x" ] ; then
			echo "dtb=${forced_dtb}" >> ${wfile}
		else
			echo "#dtb=" >> ${wfile}
		fi

		if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] || [ "x${conf_board}" = "xam335x_blank_bbbw" ] ; then
			echo "" >> ${wfile}

			if [ ! "x${uboot_cape_overlays}" = "xenable" ] ; then
				echo "##BeagleBone Black/Green dtb's for v4.1.x (BeagleBone White just works..)" >> ${wfile}

				echo "" >> ${wfile}
				echo "##BeagleBone Black: HDMI (Audio/Video) disabled:" >> ${wfile}
				echo "#dtb=am335x-boneblack-emmc-overlay.dtb" >> ${wfile}

				echo "" >> ${wfile}
				echo "##BeagleBone Black: eMMC disabled:" >> ${wfile}
				echo "#dtb=am335x-boneblack-hdmi-overlay.dtb" >> ${wfile}

				echo "" >> ${wfile}
				echo "##BeagleBone Black: HDMI Audio/eMMC disabled:" >> ${wfile}
				echo "#dtb=am335x-boneblack-nhdmi-overlay.dtb" >> ${wfile}

				echo "" >> ${wfile}
				echo "##BeagleBone Black: HDMI (Audio/Video)/eMMC disabled:" >> ${wfile}
				echo "#dtb=am335x-boneblack-overlay.dtb" >> ${wfile}

				echo "" >> ${wfile}
				echo "##BeagleBone Black: wl1835" >> ${wfile}
				echo "#dtb=am335x-boneblack-wl1835mod.dtb" >> ${wfile}

				echo "" >> ${wfile}
				echo "##BeagleBone Green: eMMC disabled" >> ${wfile}
				echo "#dtb=am335x-bonegreen-overlay.dtb" >> ${wfile}
			fi

			echo "" >> ${wfile}
			echo "###U-Boot Overlays###" >> ${wfile}
			echo "###Documentation: http://elinux.org/Beagleboard:BeagleBoneBlack_Debian#U-Boot_Overlays" >> ${wfile}
			echo "###Master Enable" >> ${wfile}
			if [ "x${uboot_cape_overlays}" = "xenable" ] ; then
				echo "enable_uboot_overlays=1" >> ${wfile}
			else
				echo "#enable_uboot_overlays=1" >> ${wfile}
			fi
			echo "###" >> ${wfile}
			echo "###Overide capes with eeprom" >> ${wfile}
			echo "#uboot_overlay_addr0=/lib/firmware/<file0>.dtbo" >> ${wfile}
			echo "#uboot_overlay_addr1=/lib/firmware/<file1>.dtbo" >> ${wfile}
			echo "#uboot_overlay_addr2=/lib/firmware/<file2>.dtbo" >> ${wfile}
			echo "#uboot_overlay_addr3=/lib/firmware/<file3>.dtbo" >> ${wfile}
			echo "###" >> ${wfile}
			echo "###Additional custom capes" >> ${wfile}
			echo "#uboot_overlay_addr4=/lib/firmware/<file4>.dtbo" >> ${wfile}
			echo "#uboot_overlay_addr5=/lib/firmware/<file5>.dtbo" >> ${wfile}
			echo "#uboot_overlay_addr6=/lib/firmware/<file6>.dtbo" >> ${wfile}
			echo "#uboot_overlay_addr7=/lib/firmware/<file7>.dtbo" >> ${wfile}
			echo "###" >> ${wfile}
			echo "###Custom Cape" >> ${wfile}
			echo "#dtb_overlay=/lib/firmware/<file8>.dtbo" >> ${wfile}
			echo "###" >> ${wfile}
			echo "###Disable auto loading of virtual capes (emmc/video/wireless/adc)" >> ${wfile}
			echo "#disable_uboot_overlay_emmc=1" >> ${wfile}
			echo "#disable_uboot_overlay_video=1" >> ${wfile}
			echo "#disable_uboot_overlay_audio=1" >> ${wfile}
			echo "#disable_uboot_overlay_wireless=1" >> ${wfile}
			echo "#disable_uboot_overlay_adc=1" >> ${wfile}
			echo "###" >> ${wfile}
			echo "###PRUSS OPTIONS" >> ${wfile}
			if [ "x${uboot_pru_rproc_44ti}" = "xenable" ] ; then
				echo "###pru_rproc (4.4.x-ti kernel)" >> ${wfile}
				echo "uboot_overlay_pru=/lib/firmware/AM335X-PRU-RPROC-4-4-TI-00A0.dtbo" >> ${wfile}
				echo "###pru_uio (4.4.x-ti & mainline/bone kernel)" >> ${wfile}
				echo "#uboot_overlay_pru=/lib/firmware/AM335X-PRU-UIO-00A0.dtbo" >> ${wfile}
			else
				echo "###pru_rproc (4.4.x-ti kernel)" >> ${wfile}
				echo "#uboot_overlay_pru=/lib/firmware/AM335X-PRU-RPROC-4-4-TI-00A0.dtbo" >> ${wfile}
				echo "###pru_uio (4.4.x-ti & mainline/bone kernel)" >> ${wfile}
				echo "uboot_overlay_pru=/lib/firmware/AM335X-PRU-UIO-00A0.dtbo" >> ${wfile}
			fi
			echo "###" >> ${wfile}
			echo "###Cape Universal Enable" >> ${wfile}
			if [ "x${uboot_cape_overlays}" = "xenable" ] ; then
				echo "enable_uboot_cape_universal=1" >> ${wfile}
			else
				echo "#enable_uboot_cape_universal=1" >> ${wfile}
			fi
			echo "###" >> ${wfile}
			echo "###Debug: disable uboot autoload of Cape" >> ${wfile}
			echo "#disable_uboot_overlay_addr0=1" >> ${wfile}
			echo "#disable_uboot_overlay_addr1=1" >> ${wfile}
			echo "#disable_uboot_overlay_addr2=1" >> ${wfile}
			echo "#disable_uboot_overlay_addr3=1" >> ${wfile}
			echo "###" >> ${wfile}
			echo "###U-Boot fdt tweaks..." >> ${wfile}
			echo "#uboot_fdt_buffer=0x60000" >> ${wfile}
			echo "###U-Boot Overlays###" >> ${wfile}

			echo "" >> ${wfile}
		fi
	fi
	
	if [  "x${conf_board}" = "xrespeaker_v2" ] ; then
		cmdline="coherent_pool=1M quiet"
	else
		cmdline="coherent_pool=1M net.ifnames=0 quiet"
	fi
	
	if [ "x${enable_systemd}" = "xenabled" ] ; then
		cmdline="${cmdline} init=/lib/systemd/systemd"
	fi

	if [ "x${enable_cape_universal}" = "xenable" ] ; then
		cmdline="${cmdline} cape_universal=enable"
	fi

	unset kms_video

	drm_device_identifier=${drm_device_identifier:-"HDMI-A-1"}
	drm_device_timing=${drm_device_timing:-"1024x768@60e"}
	if [ ! "x${conf_board}" = "xrespeaker_v2" ] ; then
		if [ "x${drm_read_edid_broken}" = "xenable" ] ; then
			cmdline="${cmdline} video=${drm_device_identifier}:${drm_device_timing}"
			echo "cmdline=${cmdline}" >> ${wfile}
			echo "" >> ${wfile}
		else
			echo "cmdline=${cmdline}" >> ${wfile}
			echo "" >> ${wfile}

			echo "#In the event of edid real failures, uncomment this next line:" >> ${wfile}
			echo "#cmdline=${cmdline} video=${drm_device_identifier}:${drm_device_timing}" >> ${wfile}
			echo "" >> ${wfile}
		fi
	else
		echo "cmdline=${cmdline}" >> ${wfile}
	fi

	if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] ; then
		echo "##Example v3.8.x" >> ${wfile}
		echo "#cape_disable=capemgr.disable_partno=" >> ${wfile}
		echo "#cape_enable=capemgr.enable_partno=" >> ${wfile}
		echo "" >> ${wfile}
	fi

	if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] || [ "x${conf_board}" = "xam335x_blank_bbbw" ] ; then
		echo "##Example v4.1.x" >> ${wfile}
		echo "#cape_disable=bone_capemgr.disable_partno=" >> ${wfile}
		echo "#cape_enable=bone_capemgr.enable_partno=" >> ${wfile}
		echo "" >> ${wfile}

		if [ ! "x${has_post_uenvtxt}" = "x" ] ; then
			cat "${DIR}/post-uEnv.txt" >> ${wfile}
			echo "" >> ${wfile}
		fi

		if [ "x${usb_flasher}" = "xenable" ] ; then
			if [ ! "x${oem_flasher_script}" = "x" ] ; then
				echo "cmdline=init=/opt/scripts/tools/eMMC/${oem_flasher_script}" >> ${wfile}
			else
				echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-from-usb-media.sh" >> ${wfile}
			fi
		elif [ "x${emmc_flasher}" = "xenable" ] ; then
			echo "##enable Generic eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh" >> ${wfile}
		elif [ "x${bbg_flasher}" = "xenable" ] ; then
			echo "##enable BBG: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-bbg.sh" >> ${wfile}
		elif [ "x${bbgw_flasher}" = "xenable" ] ; then
			echo "##enable BBG: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-bbgw.sh" >> ${wfile}
		elif [ "x${m10a_flasher}" = "xenable" ] ; then
			echo "##enable m10a: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-m10a.sh" >> ${wfile}
		elif [ "x${me06_flasher}" = "xenable" ] ; then
			echo "##enable me06: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-me06.sh" >> ${wfile}
		elif [ "x${bbbl_flasher}" = "xenable" ] ; then
			echo "##enable bbbl: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-bbbl.sh" >> ${wfile}
		elif [ "x${bbbw_flasher}" = "xenable" ] ; then
			echo "##enable bbbw: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-bbbw.sh" >> ${wfile}
		elif [ "x${bp00_flasher}" = "xenable" ] ; then
			echo "##enable bp00: eeprom Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-bp00.sh" >> ${wfile}
		elif [ "x${a335_flasher}" = "xenable" ] ; then
			echo "##enable a335: eeprom Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-a335.sh" >> ${wfile}
		else
			echo "##enable Generic eMMC Flasher:" >> ${wfile}
			echo "##make sure, these tools are installed: dosfstools rsync" >> ${wfile}
			echo "#cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh" >> ${wfile}
		fi
		echo "" >> ${wfile}
	else
		if [ "x${usb_flasher}" = "xenable" ] ; then
			if [ ! "x${oem_flasher_script}" = "x" ] ; then
				echo "cmdline=init=/opt/scripts/${oem_flasher_script}" >> ${wfile}
			else
				echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-from-usb-media.sh" >> ${wfile}
			fi
		elif [ "x${emmc_flasher}" = "xenable" ] ; then
			echo "##enable Generic eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-no-eeprom.sh" >> ${wfile}
		elif [ "x${bp00_flasher}" = "xenable" ] ; then
			echo "##enable bp00: eeprom Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-bp00.sh" >> ${wfile}
		elif [ "x${a335_flasher}" = "xenable" ] ; then
			echo "##enable a335: eeprom Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-a335.sh" >> ${wfile}
		else
			if [ "x${conf_board}" = "xrespeaker_v2" ] ; then
				echo "##enable respeaker: eMMC Flasher:" >> ${wfile}
				echo "##make sure, these tools are installed: dosfstools rsync" >> ${wfile}
				echo "#cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-respeaker.sh" >> ${wfile}
			fi
		fi
	fi

	#oob out of box experience:
	if [ ! "x${oobe_cape}" = "x" ] ; then
		echo "" >> ${wfile}
		echo "dtb=am335x-boneblack-overlay.dtb" >> ${wfile}
		echo "cape_enable=bone_capemgr.enable_partno=${oobe_cape}" >> ${wfile}
	fi

	#am335x_boneblack is a custom u-boot to ignore empty factory eeproms...
	if [ "x${conf_board}" = "xam335x_boneblack" ] ; then
		board="am335x_evm"
	else
		board=${conf_board}
	fi

	echo "/boot/uEnv.txt---------------"
	cat ${wfile}
	echo "-----------------------------"

	wfile="${TEMPDIR}/disk/boot/SOC.sh"
	if [ "x${conf_board}" = "xrespeaker_v2" ] ; then 
		cp "${DIR}"/hwpack/${dtb_board}.conf ${wfile}
		echo "/dev/mmcblk1" > ${TEMPDIR}/disk/resizerootfs
	else	
		generate_soc
	fi	

	#RootStock-NG
	if [ -f ${TEMPDIR}/disk/etc/rcn-ee.conf ] ; then
		. ${TEMPDIR}/disk/etc/rcn-ee.conf

		mkdir -p ${TEMPDIR}/disk/boot/uboot || true

		wfile="${TEMPDIR}/disk/etc/fstab"
		echo "# /etc/fstab: static file system information." > ${wfile}
		echo "#" >> ${wfile}
		echo "# Auto generated by RootStock-NG: setup_sdcard.sh" >> ${wfile}
		echo "#" >> ${wfile}

		if [ "x${conf_board}" = "xrespeaker_v2" ] ; then
			echo "LABEL=${BOOT_LABEL}       /boot vfat   rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0      2" >>  ${wfile}
		else
			if [ "x${option_ro_root}" = "xenable" ] ; then
				echo "#With read only rootfs, we need to boot once as rw..." >> ${wfile}
				echo "${rootfs_drive}  /  ext2  noatime,errors=remount-ro  0  1" >> ${wfile}
				echo "#" >> ${wfile}
				echo "#Switch to read only rootfs:" >> ${wfile}
				echo "#${rootfs_drive}  /  ext2  noatime,ro,errors=remount-ro  0  1" >> ${wfile}
				echo "#" >> ${wfile}
				echo "${rootfs_var_drive}  /var  ${ROOTFS_TYPE}  noatime  0  2" >> ${wfile}
			else
				echo "${rootfs_drive}  /  ${ROOTFS_TYPE}  noatime,errors=remount-ro  0  1" >> ${wfile}
			fi

			echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> ${wfile}

		fi

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

		if [ "x${DISABLE_ETH}" != "xskip" ] ; then
			wfile="${TEMPDIR}/disk/etc/network/interfaces"
			echo "# This file describes the network interfaces available on your system" > ${wfile}
			echo "# and how to activate them. For more information, see interfaces(5)." >> ${wfile}
			echo "" >> ${wfile}
			echo "# The loopback network interface" >> ${wfile}
			echo "auto lo" >> ${wfile}
			echo "iface lo inet loopback" >> ${wfile}
			echo "" >> ${wfile}
			echo "# The primary network interface" >> ${wfile}

			if [ "${DISABLE_ETH}" ] ; then
				echo "#auto eth0" >> ${wfile}
				echo "#iface eth0 inet dhcp" >> ${wfile}
			else
				echo "auto eth0"  >> ${wfile}
				echo "iface eth0 inet dhcp" >> ${wfile}
			fi

			#if we have systemd & wicd-gtk, disable eth0 in /etc/network/interfaces
			if [ -f ${TEMPDIR}/disk/lib/systemd/systemd ] ; then
				if [ -f ${TEMPDIR}/disk/usr/bin/wicd-gtk ] ; then
					sed -i 's/auto eth0/#auto eth0/g' ${wfile}
					sed -i 's/allow-hotplug eth0/#allow-hotplug eth0/g' ${wfile}
					sed -i 's/iface eth0 inet dhcp/#iface eth0 inet dhcp/g' ${wfile}
				fi
			fi

			#if we have connman, disable eth0 in /etc/network/interfaces
			if [ -f ${TEMPDIR}/disk/etc/init.d/connman ] ; then
				sed -i 's/auto eth0/#auto eth0/g' ${wfile}
				sed -i 's/allow-hotplug eth0/#allow-hotplug eth0/g' ${wfile}
				sed -i 's/iface eth0 inet dhcp/#iface eth0 inet dhcp/g' ${wfile}
			fi

			echo "# Example to keep MAC address between reboots" >> ${wfile}
			echo "#hwaddress ether DE:AD:BE:EF:CA:FE" >> ${wfile}

			echo "" >> ${wfile}

			echo "##connman: ethX static config" >> ${wfile}
			echo "#connmanctl services" >> ${wfile}
			echo "#Using the appropriate ethernet service, tell connman to setup a static IP address for that service:" >> ${wfile}
			echo "#sudo connmanctl config <service> --ipv4 manual <ip_addr> <netmask> <gateway> --nameservers <dns_server>" >> ${wfile}

			echo "" >> ${wfile}

			echo "##connman: WiFi" >> ${wfile}
			echo "#" >> ${wfile}
			echo "#connmanctl" >> ${wfile}
			echo "#connmanctl> tether wifi off" >> ${wfile}
			echo "#connmanctl> enable wifi" >> ${wfile}
			echo "#connmanctl> scan wifi" >> ${wfile}
			echo "#connmanctl> services" >> ${wfile}
			echo "#connmanctl> agent on" >> ${wfile}
			echo "#connmanctl> connect wifi_*_managed_psk" >> ${wfile}
			echo "#connmanctl> quit" >> ${wfile}

			echo "" >> ${wfile}

			echo "# Ethernet/RNDIS gadget (g_ether)" >> ${wfile}
			echo "# Used by: /opt/scripts/boot/autoconfigure_usb0.sh" >> ${wfile}
			echo "iface usb0 inet static" >> ${wfile}
			echo "    address 192.168.7.2" >> ${wfile}
			echo "    netmask 255.255.255.252" >> ${wfile}
			echo "    network 192.168.7.0" >> ${wfile}
			echo "    gateway 192.168.7.1" >> ${wfile}
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

	if [ ! "x${spl_uboot_name}" = "x" ] ; then
		mkdir -p ${TEMPDIR}/disk/opt/backup/uboot/
		cp -v ${TEMPDIR}/dl/${SPL} ${TEMPDIR}/disk/opt/backup/uboot/${spl_uboot_name}
	fi

	if [ ! -f ${TEMPDIR}/etc/udev/rules.d/60-omap-tty.rules ] ; then
		file="/etc/udev/rules.d/60-omap-tty.rules"
		echo "#from: http://arago-project.org/git/meta-ti.git?a=commit;h=4ce69eff28103778508d23af766e6204c95595d3" > ${TEMPDIR}/disk${file}
		echo "" > ${TEMPDIR}/disk${file}
		echo "# Backward compatibility with old OMAP UART-style ttyO0 naming" > ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
		echo "SUBSYSTEM==\"tty\", ATTR{uartclk}!=\"0\", KERNEL==\"ttyS[0-9]\", SYMLINK+=\"ttyO%n\"" >> ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
	fi

	if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] || [ "x${conf_board}" = "xam335x_blank_bbbw" ] ; then

		file="/etc/udev/rules.d/70-persistent-net.rules"
		echo "" > ${TEMPDIR}/disk${file}
		echo "# Auto generated by RootStock-NG: setup_sdcard.sh" >> ${TEMPDIR}/disk${file}
		echo "# udevadm info -q all -p /sys/class/net/eth0 --attribute-walk" >> ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
		echo "# BeagleBone: net device ()" >> ${TEMPDIR}/disk${file}
		echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"cpsw\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"eth0\"" >> ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}

		if [ -f ${TEMPDIR}/disk/etc/init.d/cpufrequtils ] ; then
			sed -i 's/GOVERNOR="ondemand"/GOVERNOR="performance"/g' ${TEMPDIR}/disk/etc/init.d/cpufrequtils
		fi
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

	if [ "x${drm}" = "xomapdrm" ] ; then
		wfile="/etc/X11/xorg.conf"
		if [ -f ${TEMPDIR}/disk${wfile} ] ; then
			sudo sed -i -e 's:modesetting:omap:g' ${TEMPDIR}/disk${wfile}
			sudo sed -i -e 's:fbdev:omap:g' ${TEMPDIR}/disk${wfile}

			if [ "x${conf_board}" = "xomap3_beagle" ] ; then
				sudo sed -i -e 's:#HWcursor_false::g' ${TEMPDIR}/disk${wfile}
				sudo sed -i -e 's:#DefaultDepth::g' ${TEMPDIR}/disk${wfile}
			else
				sudo sed -i -e 's:#HWcursor_false::g' ${TEMPDIR}/disk${wfile}
			fi
		fi
	fi

	if [ "x${drm}" = "xetnaviv" ] ; then
		wfile="/etc/X11/xorg.conf"
		if [ -f ${TEMPDIR}/disk${wfile} ] ; then
			if [ -f ${TEMPDIR}/disk/usr/lib/xorg/modules/drivers/armada_drv.so ] ; then
				sudo sed -i -e 's:modesetting:armada:g' ${TEMPDIR}/disk${wfile}
				sudo sed -i -e 's:fbdev:armada:g' ${TEMPDIR}/disk${wfile}
			fi
		fi
	fi

	if [ "${usbnet_mem}" ] ; then
		echo "vm.min_free_kbytes = ${usbnet_mem}" >> ${TEMPDIR}/disk/etc/sysctl.conf
	fi

	if [ "${need_wandboard_firmware}" ] ; then
		http_brcm="https://raw.githubusercontent.com/Freescale/meta-fsl-arm-extra/master/recipes-bsp/broadcom-nvram-config/files/wandboard"
		${dl_quiet} --directory-prefix="${TEMPDIR}/disk/lib/firmware/brcm/" ${http_brcm}/brcmfmac4329-sdio.txt
		${dl_quiet} --directory-prefix="${TEMPDIR}/disk/lib/firmware/brcm/" ${http_brcm}/brcmfmac4330-sdio.txt
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
	if [ "x${build_img_file}" = "xenable" ] ; then
		echo "Image file: ${imagename}"
		echo "-----------------------------"

		if [ "x${usb_flasher}" = "x" ] && [ "x${emmc_flasher}" = "x" ] ; then
			wfile="${imagename}.xz.job.txt"
			echo "abi=aaa" > ${wfile}
			echo "conf_image=${imagename}.xz" >> ${wfile}
			bmapimage=$(echo ${imagename} | awk -F ".img" '{print $1}')
			echo "conf_bmap=${bmapimage}.bmap" >> ${wfile}
			echo "conf_resize=enable" >> ${wfile}
			echo "conf_partition1_startmb=${conf_boot_startmb}" >> ${wfile}

			case "${conf_boot_fstype}" in
			fat)
				echo "conf_partition1_fstype=0xE" >> ${wfile}
				;;
			ext2|ext3|ext4)
				echo "conf_partition1_fstype=0x83" >> ${wfile}
				;;
			esac

			if [ "x${media_rootfs_partition}" = "x2" ] ; then
				echo "conf_partition1_endmb=${conf_boot_endmb}" >> ${wfile}
				echo "conf_partition2_fstype=0x83" >> ${wfile}
			fi
			echo "conf_root_partition=${media_rootfs_partition}" >> ${wfile}
		fi
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
		;;
	--board)
		checkparm $2
		dtb_board="$2"
		dir_check="${DIR}/"
		check_dtb_board
		;;
	esac
	shift
done


find_issue
detect_software
dl_bootloader
create_partitions
populate_loaders





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
