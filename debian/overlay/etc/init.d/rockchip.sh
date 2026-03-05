#!/bin/bash -e
### BEGIN INIT INFO
# Provides:          rockchip
# Required-Start:
# Required-Stop:
# Default-Start:
# Default-Stop:
# Short-Description:
# Description:       Setup RK3308BS platform environment
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

compatible=$(cat /proc/device-tree/compatible)
if ! echo "$compatible" | grep -q rk3308; then
    echo "This script is for RK3308BS only."
    exit 1
fi

# RK3308BS: no GPU, use software rendering
[ -e /etc/X11/xorg.conf.d/20-modesetting.conf ] && \
    sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf

# first boot configure
if [ ! -e "/usr/local/first_boot_flag" ]; then
    echo "It's the first time booting. The rootfs will be configured."

    mount -o remount,sync /

    if [ -e "/dev/rfkill" ]; then
        rm /dev/rfkill
    fi

    rm -rf /*.deb /*.tar

    touch /usr/local/first_boot_flag

    sync
    shutdown -r now
fi

# sync system time
hwclock --systohc
