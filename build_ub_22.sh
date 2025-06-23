#!/bin/bash

if [ "$(id -u)" -ne 0 ];
then
    echo "Got root?"
    exit 1
fi

ROOTFS_BASE_NAME="ubuntu-base-22.04.5-base-arm64.tar.gz"
ROOTFS_BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/jammy/release/"
ROOTFS_DOWNLOAD="$ROOTFS_BASE_URL$ROOTFS_BASE_NAME"

echo "Building Ubuntu 22 (Jammy) base image from scratch..."
echo "Going to take a moment to complete..."

mkdir -p BaseOS

cd BaseOS

DEBUG_BUILD=1
ENABLE_DOCKER=0
ENABLE_SNAPD=0

function umountBindMounts(){
        echo "Unmounting bind mounts..."
        umount $ROOTFS_BINDMOUNTS/dev
        umount $ROOTFS_BINDMOUNTS/proc
        umount $ROOTFS_BINDMOUNTS/sys
}

function addFilesForChroot(){
        echo "mychroot" > etc/hostname
        echo "nameserver 8.8.8.8" > etc/resolv.conf
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy main restricted" > etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy universe" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates universe" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy multiverse" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates multiverse" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-backports main restricted universe multiverse" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-security universe" >> etc/apt/sources.list
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ jammy-security multiverse" >> etc/apt/sources.list

        if [ $ENABLE_DOCKER -eq 1 ];
        then
                echo "ENABLE_DOCKER pragma is enabled."
                echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable" >> etc/apt/sources.list
        fi

        mkdir -p tmp/
        echo "#!/bin/bash" > tmp/inside_chroot.sh
        echo "echo 'Updating apt repository cache...' " >> tmp/inside_chroot.sh
        echo "apt update" >> tmp/inside_chroot.sh
        echo "echo 'tzdata tzdata/Areas select Africa' | debconf-set-selections" >> tmp/inside_chroot.sh
        echo "echo 'tzdata tzdata/Zones/Afica select Johannesburg' | debconf-set-selections" >> tmp/inside_chroot.sh
        echo "echo 'Installing system packages...' " >> tmp/inside_chroot.sh
        echo "DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates bridge-utils curl gnupg tzdata net-tools network-manager modemmanager iputils-ping apt-utils openssh-server kmod systemd-sysv nano vim dialog sudo rauc rauc-service libubootenv-tool mmc-utils wireless-regdb iw fdisk iproute2" >> tmp/inside_chroot.sh
        if [ $DEBUG_BUILD -eq 1 ];
        then
                echo "DEBUG_BUILD pragma is enabled."
                echo "DEBIAN_FRONTEND=noninteractive apt install -y initramfs-tools device-tree-compiler u-boot-tools" >> tmp/inside_chroot.sh
        fi

        if [ $ENABLE_DOCKER -eq 1 ];
        then
                echo "echo Installing keys for use on Docker repos..." >> tmp/inside_chroot.sh
                echo "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg" >> tmp/inside_chroot.sh
                echo "apt update" >> tmp/inside_chroot.sh
                echo "DEBIAN_FRONTEND=noninteractive apt install -y docker-ce docker-ce-cli containerd.io" >> tmp/inside_chroot.sh
        fi

        if [ $ENABLE_SNAPD -eq 1 ];
        then
                echo "Installing snapd..."
                echo "DEBIAN_FRONTEND=noninteractive apt install -y snapd" >> tmp/inside_chroot.sh
        fi

        echo "echo 'Fixing NetworkManager...'" >> tmp/inside_chroot.sh
        echo "touch /etc/NetworkManager/conf.d/10-globally-managed-devices.conf" >> tmp/inside_chroot.sh
        echo "echo 'Adding admin user for login...' " >> tmp/inside_chroot.sh
        echo "useradd -m -s /bin/bash admin" >> tmp/inside_chroot.sh
        echo "echo admin:admin | chpasswd" >> tmp/inside_chroot.sh
        echo "usermod -aG sudo admin" >> tmp/inside_chroot.sh
        echo "usermod -aG adm admin" >> tmp/inside_chroot.sh
        echo "echo 'Purging unused system packages...'" >> tmp/inside_chroot.sh
        echo "apt-get purge -y man-db manpages info doc-base" >> tmp/inside_chroot.sh
        echo "echo Deleting SSHd generated keys!" >> tmp/inside_chroot.sh
        echo "rm -r /etc/machine-id" >> tmp/inside_chroot.sh
        echo "rm -r /etc/ssh/ssh_host_*" >> tmp/inside_chroot.sh
        echo "echo Deleting all cached system-packages..." >> tmp/inside_chroot.sh
        echo "apt-get clean" >> tmp/inside_chroot.sh
        echo "echo Deleting all syslogs..." >> tmp/inside_chroot.sh
        echo "rm -r /var/log/*" >> tmp/inside_chroot.sh
        echo "echo Deleting all apt-lists..." >> tmp/inside_chroot.sh
        echo "rm -r /var/lib/apt/lists/*" >> tmp/inside_chroot.sh
        echo "echo Deleting all apt cached packages..." >> tmp/inside_chroot.sh
        echo "rm -r /var/cache/apt/archives/* " >> tmp/inside_chroot.sh
        echo "exit" >> tmp/inside_chroot.sh
        chmod +x tmp/inside_chroot.sh
}

function mountBindMounts(){
        echo "Making bind mounts into the system"
        mount --bind /dev $ROOTFS_BINDMOUNTS/dev
        mount --bind /proc $ROOTFS_BINDMOUNTS/proc
        mount --bind /sys $ROOTFS_BINDMOUNTS/sys
}


rm -r rootfs_22

echo "Making rootfs_22 folder..."
mkdir -p rootfs_22

if [ -f "$ROOTFS_BASE_NAME" ]
then
        echo "$ROOTFS_BASE_NAME found, not downloading..."
else
        echo "$ROOTFS_BASE_NAME missing, downloading..."
        wget "$ROOTFS_DOWNLOAD"
fi

echo "Extracting rootfs..."
cd rootfs_22
tar -xf ../$ROOTFS_BASE_NAME

ROOTFS_BINDMOUNTS=$(pwd)

echo "Going to add some files before jumping into chroot jail..."
addFilesForChroot
cd ../

echo "Doing bind mounts before chrooting into the system..."
mountBindMounts

echo "Jumping into chroot jail..."
chroot rootfs_22 /tmp/inside_chroot.sh

echo "Chroot jail setup is done"
umountBindMounts

echo "Removing chroot setup script..."
cd rootfs_22/
rm -r tmp/inside_chroot.sh

echo "Creating rootfs tar file..."
if [ -f ../rootfs_22.tar ];
then
        echo "Deleting current rootfs_22.tar file..."
        rm -r ../rootfs_22.tar
fi

tar -cf ../rootfs_22.tar .

echo "Done."
