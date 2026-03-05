#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

# RK3308BS: arm64 only
ARCH=arm64

echo -e "\033[36m Building for $ARCH (RK3308BS) \033[0m"

if [ ! $VERSION ]; then
	VERSION="release"
fi

echo -e "\033[36m Building for $VERSION \033[0m"

LINARO_TARBALL="linaro-bookworm-${ARCH}.tar.gz"
if [ ! -e "$LINARO_TARBALL" ]; then
	echo -e "\033[31m Run mk-base-debian.sh (via build.sh rootfs) first \033[0m"
	exit 1
fi

echo -e "\033[36m Extract image \033[0m"
sudo tar -xpf "$LINARO_TARBALL"

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder (optional; skip if empty to avoid cp conflict with binary/lib etc.)
if compgen -G "overlay-firmware/*" > /dev/null; then
	sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/
fi

# overlay-debug folder
# adb, video, camera test files (optional, may not exist)
if [ "$VERSION" = "debug" ] && compgen -G "overlay-debug/*" > /dev/null; then
	sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/ 2>/dev/null || true
fi

echo -e "\033[36m Change root.....................\033[0m"

ID=$(stat --format %u $TARGET_ROOTFS_DIR)

# RK3308BS: minimal rootfs + lightweight GUI (X11)
echo -e "\033[36m Minimal rootfs: serial/SSH + WiFi/BT + X11 GUI \033[0m"
cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

# Fixup owners
if [ "$ID" -ne 0 ]; then
       find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/ 2>/dev/null); do
	chown -h -R \$u:\$u /home/\$u
done

# Remove default Linaro user if present
userdel -r linaro 2>/dev/null || true

# Ensure standard system groups exist (escape $grp so chroot sees it, not host)
for grp in audio video plugdev netdev dialout tty gpio; do
	getent group "\$grp" >/dev/null || groupadd "\$grp"
done

# Create default user 'unihiker' (password 'dfrobot') and add to root, sudo and device groups
useradd -m -s /bin/bash unihiker
echo 'unihiker:dfrobot' | chpasswd
usermod -aG root,sudo,audio,video,plugdev,netdev,dialout,tty,gpio unihiker

# Set hostname to 'unihiker'
echo 'unihiker' > /etc/hostname
sed -i 's/^\(127\.0\.1\.1\)\s\+.*/\1       unihiker/' /etc/hosts 2>/dev/null || true

echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "nameserver 114.114.114.114" >> /etc/resolv.conf

echo "deb http://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib" >> /etc/apt/sources.list
echo "deb-src http://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib" >> /etc/apt/sources.list

apt-get update
apt-get upgrade -y

# Serial console: root login without password
sed -i "s~\(^ExecStart=.*\)~# \1\nExecStart=-/bin/sh -c '/bin/bash -l </dev/%I >/dev/%I 2>\&1'~" /usr/lib/systemd/system/serial-getty@.service 2>/dev/null || true

# SSH + editor + sudo (unihiker needs sudo for ifconfig, etc.)
apt-get install -fy --allow-downgrades openssh-server openssh-client vim sudo
echo 'unihiker ALL=(ALL:ALL) ALL' > /etc/sudoers.d/99-unihiker
chmod 440 /etc/sudoers.d/99-unihiker

# WiFi/BT tools
apt-get install -fy --allow-downgrades wpasupplicant iw network-manager bluez

# Network tools (ifconfig, etc.)
apt-get install -fy --allow-downgrades net-tools

# Add /sbin and /usr/sbin to PATH for normal users to run ifconfig directly
echo 'export PATH="$PATH:/sbin:/usr/sbin"' > /etc/profile.d/unihiker-path.sh

# USB RNDIS/ECM gadget (br0 10.1.2.3 + DHCP)
apt-get install -fy --allow-downgrades bridge-utils isc-dhcp-server
chmod +x /usr/lib/rk3308bs/usb-rndis-ether.sh
# Ensure systemd sees the new gadget unit and enable it
systemctl daemon-reload
systemctl enable usb-rndis-ether.service
# Disable legacy usbdevice service to avoid long boot retries
systemctl disable usbdevice.service 2>/dev/null || true
systemctl mask usbdevice.service 2>/dev/null || true
rm -f /etc/systemd/system/sysinit.target.wants/usbdevice.service 2>/dev/null || true

# Lightweight GUI: X11 (Xorg fbdev + Openbox + xterm + libinput for touch + xsetroot)
apt-get install -fy --allow-downgrades xserver-xorg xserver-xorg-input-libinput xserver-xorg-video-fbdev xinit openbox xterm libinput-tools x11-xserver-utils

# Optional: evtest for touchscreen debugging
apt-get install -fy --allow-downgrades evtest || true

# X11 runs on tty1; free tty1 from getty and enable x11
systemctl mask getty@tty1.service 2>/dev/null || true
systemctl enable x11.service
chmod +x /etc/X11/xinit/xinitrc.minimal
chmod +x /usr/bin/start-x11

# WiFi/BT: create system/vendor layout and copy rtl8723ds firmware (ko installed by post-hook into /lib/modules/$(uname -r)/extra/)
mkdir -p /system/etc/firmware
if [ -d /usr/lib/rk3308bs/wifi-firmware ]; then
	cp -n /usr/lib/rk3308bs/wifi-firmware/* /system/etc/firmware/ 2>/dev/null || true
fi
mkdir -p /vendor/etc
ln -sf /system/etc/firmware /vendor/etc/firmware 2>/dev/null || true

apt list --installed 2>/dev/null | grep -v oldstable | cut -d/ -f1 | xargs -r apt-mark hold

systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
rm -f /lib/systemd/system/wpa_supplicant@.service


# Remove oem/userdata from fstab (simplified partition layout: boot+rootfs only)
sed -i '/by-partlabel\/oem/d; /by-partlabel\/userdata/d' /etc/fstab 2>/dev/null || true

# systemd-logind STATE_DIRECTORY: tmpfiles.d/logind-dirs.conf in overlay creates at boot
mkdir -p /var/lib/systemd/state
chmod 755 /var/lib/systemd/state

rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/

EOF
