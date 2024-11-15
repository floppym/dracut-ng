#!/bin/sh

trap 'poweroff -f' EXIT
set -ex
mdadm --create /dev/md0 --run --auto=yes --level=5 --raid-devices=3 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid[123]
# wait for the array to finish initializing, otherwise this sometimes fails
# randomly.
mdadm -W /dev/md0 || :
printf test > keyfile
cryptsetup -q luksFormat /dev/md0 /keyfile
echo "The passphrase is test"
cryptsetup luksOpen /dev/md0 dracut_crypt_test < /keyfile
lvm pvcreate -ff -y /dev/mapper/dracut_crypt_test
lvm vgcreate dracut /dev/mapper/dracut_crypt_test
lvm lvcreate --yes -l 100%FREE -n root dracut
lvm vgchange -ay
mkfs.ext4 -q -L root /dev/dracut/root
mkdir -p /sysroot
mount -t ext4 /dev/dracut/root /sysroot
cp -a -t /sysroot /source/*
mkdir -p /sysroot/run
umount /sysroot
lvm lvchange -a n /dev/dracut/root
udevadm settle
cryptsetup luksClose /dev/mapper/dracut_crypt_test
udevadm settle
mdadm -W /dev/md0 || :
udevadm settle
mdadm --detail --export /dev/md0 | grep -F MD_UUID > /tmp/mduuid
. /tmp/mduuid
udevadm settle
eval "$(udevadm info --query=property --name=/dev/md0 | while read -r line || [ -n "$line" ]; do [ "$line" != "${line#*ID_FS_UUID*}" ] && echo "$line"; done)"
{
    echo "dracut-root-block-created"
    echo MD_UUID="$MD_UUID"
    echo "ID_FS_UUID=$ID_FS_UUID"
} | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
sync
poweroff -f
