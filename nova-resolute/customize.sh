#! /bin/bash
# Ubuntu 26.04 (resolute) on Indiedroid Nova with Ubuntu's generic arm64 kernel (7.0+).
# indiedroid-nova (ameriDroid repo) ships /etc/kernel/postinst.d/zz-nova-kernel: it swaps Ubuntu's stubble
# vmlinuz (crashes on edk2-rk3588) for the plain arm64 Image and installs /boot/dtb-<ver>, which stock grub loads;
# so the patched grub isn't needed. The ameriDroid repo is added for indiedroid-nova (bugfix channel);
# its resolute suite only carries ameriDroid's own packages, so no pinning is needed.

chroot=$1
run_in_chroot() {
    chroot $chroot /bin/bash -c "$1"
}
cfgdir=$(dirname "$(readlink -f "$0")")

echo "Setting up the system"

# The rootfs/ overlay is copied in after this hook, so install what the hook itself needs now.
for u in resizefs oemcleanup; do
    install -Dm644 "$cfgdir/rootfs/usr/lib/systemd/system/$u.service" $chroot/usr/lib/systemd/system/$u.service
done

# No snaps in the image: snapd can't seed inside a chroot, and the firefox/thunderbird debs are snap shims.
cat <<EOF2 > $chroot/etc/apt/preferences.d/no-snap
Package: snapd firefox thunderbird chromium-browser
Pin: release *
Pin-Priority: -1
EOF2

# mmdebstrap only adds the release pocket; add updates/security so the image gets current kernels and fixes.
cat <<EOF2 > $chroot/etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports resolute main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports resolute-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports resolute-security main restricted universe multiverse
EOF2

# ameriDroid repo, key bootstrapped from the bundled keyring .deb
cp "$(ls "$cfgdir"/ameridroid-archive-keyring_*_all.deb | sort -V | tail -1)" $chroot/tmp/ameridroid-archive-keyring.deb
run_in_chroot "dpkg -i /tmp/ameridroid-archive-keyring.deb && rm /tmp/ameridroid-archive-keyring.deb"
cat <<EOF2 > $chroot/etc/apt/sources.list.d/ameridroid.list
deb [signed-by=/usr/share/keyrings/ameridroid-archive-keyring.gpg] https://ameridroid.github.io/apt-repo/stable resolute main
deb [signed-by=/usr/share/keyrings/ameridroid-archive-keyring.gpg] https://ameridroid.github.io/apt-repo/testing resolute main
EOF2

password=$(openssl passwd -6 ubuntu) # Password is "ubuntu" (without quotes)

export DEBIAN_FRONTEND=noninteractive
run_in_chroot "apt-get update"
run_in_chroot "apt-get install -y indiedroid-nova grub-efi-arm64 initramfs-tools linux-image-generic linux-firmware systemd-timesyncd"
run_in_chroot "apt-get install -y --no-install-recommends ubuntu-desktop-minimal gdm3 gnome-terminal nautilus gnome-control-center gnome-tweaks \
    gnome-disk-utility pipewire-pulse wireplumber mesa-vulkan-drivers libgl1-mesa-dri fonts-ubuntu yaru-theme-gtk yaru-theme-icon \
    network-manager-gnome gnome-shell-extension-manager"
kver=$(chroot $chroot dpkg-query -W -f='${Version}' linux-image-generic)
if ! chroot $chroot dpkg --compare-versions "$kver" ge 6.17; then
    echo "Kernel $kver is older than 6.17; Nova HDMI/GPU need a newer one" >&2
    exit 1
fi
run_in_chroot "apt-get upgrade -y"
run_in_chroot "/etc/kernel/postinst.d/zz-nova-kernel"
run_in_chroot "groupadd -g 1001 ubuntu"
run_in_chroot "useradd -m -u 1001 -g 1001 -G sudo -s /bin/bash --password='$password' ubuntu"

run_in_chroot "locale-gen en_US.UTF-8"
run_in_chroot "update-locale LANG=en_US.UTF-8"

run_in_chroot "apt-get clean"
run_in_chroot "systemctl enable resizefs || true"

# Disable suspend/hibernate entirely (sleep targets masked, GNOME/GDM never idle-suspend).
# The rootfs/ overlay lands after this hook, so install the schema override here to compile it.
run_in_chroot "systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target"
install -Dm644 "$cfgdir/rootfs/usr/share/glib-2.0/schemas/90_nova-nosuspend.gschema.override" \
    $chroot/usr/share/glib-2.0/schemas/90_nova-nosuspend.gschema.override
run_in_chroot "glib-compile-schemas /usr/share/glib-2.0/schemas"
