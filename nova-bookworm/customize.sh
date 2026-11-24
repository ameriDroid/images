#! /bin/bash

chroot=$1
pkgs="indiedroid-nova grub-efi-arm64 initramfs-tools linux-rockchip mali-g610-firmware kmod systemd-timesyncd"
run_in_chroot() {
    chroot $chroot /bin/bash -c "$1"
}

echo "Setting up the system"

# Bootstrap the repo key from the bundled ameridroid-archive-keyring .deb (apt.ameridroid.com is gone).
cfgdir=$(dirname "$(readlink -f "$0")")
cp "$(ls "$cfgdir"/ameridroid-archive-keyring_*_all.deb | sort -V | tail -1)" $chroot/tmp/ameridroid-archive-keyring.deb
run_in_chroot "dpkg -i /tmp/ameridroid-archive-keyring.deb && rm /tmp/ameridroid-archive-keyring.deb"
cat <<EOF2 > $chroot/etc/apt/sources.list.d/ameridroid.list
deb [signed-by=/usr/share/keyrings/ameridroid-archive-keyring.gpg] https://ameridroid.github.io/apt-repo/stable bookworm main
deb [signed-by=/usr/share/keyrings/ameridroid-archive-keyring.gpg] https://ameridroid.github.io/apt-repo/testing bookworm main
EOF2

# Set up APT pinning for the repository
cat <<EOF > $chroot/etc/apt/preferences.d/ameridroid
Package: *
Pin: origin ameridroid.github.io
Pin-Priority: 1001
EOF

# The rootfs/ overlay is copied in after this hook; the unit must exist for systemctl enable.
install -Dm644 "$cfgdir/rootfs/usr/lib/systemd/system/resizefs.service" $chroot/usr/lib/systemd/system/resizefs.service

password=$(openssl passwd -6 debian) # Password is "debian" (without quotes) 

run_in_chroot "apt update"
run_in_chroot "apt install -y $pkgs"
run_in_chroot "apt upgrade -y"
run_in_chroot "groupadd -g 1001 debian"
run_in_chroot "useradd -m -u 1001 -g 1001 -G sudo -s /bin/bash --password='$password' debian"

run_in_chroot "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
run_in_chroot "locale-gen"
run_in_chroot "update-locale LANG=en_US.UTF-8"

run_in_chroot "apt clean"
run_in_chroot "apt autoclean"
run_in_chroot "systemctl enable resizefs || true"

# Disable suspend/hibernate entirely (sleep targets masked, GNOME/GDM never idle-suspend).
# The rootfs/ overlay lands after this hook, so install the schema override here to compile it.
run_in_chroot "systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target"
install -Dm644 "$cfgdir/rootfs/usr/share/glib-2.0/schemas/90_nova-nosuspend.gschema.override" \
    $chroot/usr/share/glib-2.0/schemas/90_nova-nosuspend.gschema.override
run_in_chroot "glib-compile-schemas /usr/share/glib-2.0/schemas"