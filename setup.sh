#!/bin/sh

usage(){
	echo -e "Usage: $0 <device (dev/sdX) > [uki_filename]"
	exit 1
}

cleanup(){
	#check if /mnt is in /proc/mounts
	if grep -qs '/mnt' /proc/mounts ; then
		umount /mnt ||  { echo "ERR: Unable to umount /mnt" ; exit 1; }
	fi	

	#UKI_TEMP_FILE created by get_uki_file() function
	if [ -n "$UKI_TEMP_FILE" ] && [ -f "$UKI_TEMP_FILE" ] ; then
		rm -f "$UKI_TEMP_FILE"
	fi
}

get_uki_file(){
	#find the current overlay partition
	overlay_dev=$(awk '$2 == "/overlay" { print $1 }' /proc/mounts )
	
	#boot partition
	boot_part=$(echo "$overlay_dev" | sed 's/[0-9]/1/g')

	UKI_TEMP_FILE=$(mktemp)

	mount "${boot_part}" /mnt
	cp /mnt/efi/boot/bootx64.efi "$UKI_TEMP_FILE"
	echo "$UKI_TEMP_FILE"
}

partition(){
	DEVICE="$1"
	[ -n "$DEVICE" ] || usage
	[ -b "$DEVICE" ] || { echo "ERR partition : Device $DEVICE not found" ; exit 1 ; }
	
	# Passing inputs to fdisk
	#https://askubuntu.com/questions/741679/automated-shell-script-to-run-fdisk-command-with-user-input
	(
	echo g  	#GPT partition
	echo n  	#New partition
	echo 1  	#Parition Number
	echo    	#Default - first available sector
	echo +512M	#Size of the 1st partition
	echo t		#Change the partition type (default Linux Filesystem)
	echo 1		#Set type EFI system
	echo n		
	echo 2
	echo 		#Default - first available sector
	echo 		#Default - last sector
	echo w		#Write the changes
	)  | fdisk "$DEVICE"  1> /dev/null || { echo "ERR partition : Unable to partition $DEVICE" ; exit 1 ; }
}

format(){
	DEVICE="$1"
	
	[ -n "$DEVICE" ] || usage

	#partitions
	PART1="${DEVICE}1"
	PART2="${DEVICE}2"

	[ -b "${PART1}" ] || { echo "ERR format : Device ${PART1} not found " ; exit 1 ; }
	[ -b "${PART2}" ] || { echo "ERR format : Device ${PART2} not found" ; exit 1  ; }

		
	mkfs.vfat -F 32 "${PART1}"	
	mkfs.ext4 -L extroot "${PART2}"

}

mount_and_copy(){
	DEVICE="$1"
	UKI_FILE="$2"
	
	[ -n "$DEVICE" ] || usage
	[ -n "$UKI_FILE" ] || UKI_FILE=$(get_uki_file)
	
	PART1="${DEVICE}1"
	[ -b "${PART1}" ] || { echo "ERR mount_and_copy : Device ${PART1} not found" ; exit 1 ; }

	#mount the 1st partition
	mount "${PART1}" /mnt || { echo "ERR mount_and_copy : Unable to mount ${PART1} " ; exit 1 ; } 
	
	#create BOOT directory
	mkdir -p /mnt/efi/boot
	
	#copy the UKI image file
	cp "${UKI_FILE}" /mnt/efi/boot/bootx64.efi ||  { echo "ERR mount_and_copy : Unable to copy UKI file" ; exit 1  ; }


	umount /mnt || { echo "ERR mount_and_copy : Unable to umount /mnt" ; exit 1 ; }
}

#--------Start of script--------
if [ "$#" -lt 1 ] ; then
	usage
fi

#trap the EXIT, SIGINT and SIGTERM signals
trap cleanup EXIT SIGINT SIGTERM

DEVICE="$1"
UKI_FILE="$2"
partition "$DEVICE"
format "$DEVICE"
mount_and_copy "$DEVICE" "$UKI_FILE"
