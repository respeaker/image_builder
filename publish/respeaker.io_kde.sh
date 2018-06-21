#!/bin/bash -e

time=$(date +%Y%m%d)
DIR="$PWD"

ssh_user="pillar@192.168.4.48"
rev=$(git rev-parse HEAD)
branch=$(git describe --contains --all HEAD)
server_dir="/home/public/share"
cloud_dir="onedrive:respeaker"

export apt_proxy=192.168.4.48:3142/

keep_net_alive () {
	while : ; do
		sleep 15
		echo "log: [Running: ./publish/respeaker.io_stable.sh]"
	done
}

build_and_upload_image () {
	if [ -d ./deploy/${image_dir_name} ] ; then
		cd ./deploy/${image_dir_name}/
		echo "debug: [./setup_sdcard_v2.sh ${options}]"
		sudo ./setup_sdcard_v2.sh ${options}

		if [ -f ${image_name}-${size}.img ] ; then
			sudo chown v2.v2 ${image_name}-${size}.img
			#sudo chown v2.v2 ${image_name}-${size}.img.xz.job.txt

			bmaptool create -o ${image_name}-${size}.bmap ${image_name}-${size}.img

			xz -T0 -z -3 -v -v --verbose ${image_name}-${size}.img
			sha256sum ${image_name}-${size}.img.xz > ${image_name}-${size}.img.xz.sha256sum

			#upload:
			 ssh ${ssh_user} mkdir -p ${server_dir}/respeaker/${time}
			 rsync -e ssh -avh ./${image_name}-${size}.bmap ${ssh_user}:${server_dir}/respeaker/${time}
			 rsync -e ssh -avh ./${image_name}-${size}.img.xz ${ssh_user}:${server_dir}/respeaker/${time}
			 rsync -e ssh -avh ./${image_name}-${size}.img.xz.sha256sum ${ssh_user}:${server_dir}/respeaker/${time}

			cd ../../
			# sudo rm -rf ./deploy/ || true
		else
			echo "***ERROR***: Could not find ${image_name}-${size}.img"
		fi
	else
		echo "***ERROR***: Could not find ./deploy/${image_dir_name}"
	fi
}

keep_net_alive & KEEP_NET_ALIVE_PID=$!
echo "pid: [${KEEP_NET_ALIVE_PID}]"

# KDE ReSpeaker image
##Debian 9:
#image_name="${deb_distribution}-${release}-${image_type}-${deb_arch}-${time}"
config_name="respeaker-debian-stretch-kde-v4.4"
./RootStock-NG.sh -c ${config_name}


image_dir_name="debian-9.1-kde-armhf-${time}"
image_name="respeaker-debian-9-kde-sd-${time}"
size="4gb"
options="--img-4gb ${image_name} --dtb respeaker_v2 \
--boot_label SD_BOOT  --rootfs ext4 --force-device-tree rk3229-respeaker-v2.dtb"
build_and_upload_image


sudo rm -rf ./deploy/ || true

[ -e /proc/$KEEP_NET_ALIVE_PID ] && sudo kill $KEEP_NET_ALIVE_PID

