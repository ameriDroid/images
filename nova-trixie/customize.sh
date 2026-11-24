#! /bin/bash
# Debian 13 (trixie) on Indiedroid Nova with Debian's own mainline kernel.
# Kernel: Debian mainline from trixie-backports, required >= 6.17 (trixie's stock 6.12 has no HDMI/GPU nodes).
# Grub: ameriDroid's patched build (adds the grubdtb/devicetree handling), pinned from the ameriDroid repo.

chroot=$1
pkgs="indiedroid-nova grub-efi-arm64 initramfs-tools kmod systemd-timesyncd firmware-misc-nonfree firmware-realtek mesa-vulkan-drivers libgl1-mesa-dri"
run_in_chroot() {
    chroot $chroot /bin/bash -c "$1"
}

echo "Setting up the system"

# ameriDroid repo: only grub is taken from it. Its trixie suite also carries the vendor 6.1 kernel
# and mesa-panfork, which must not replace Debian's mainline kernel and Mesa (Panthor).
# Bootstrap the key from the bundled ameridroid-archive-keyring .deb; later key updates come from the repo.
keyring=/usr/share/keyrings/ameridroid-archive-keyring.gpg
cfgdir=$(dirname "$(readlink -f "$0")")
keydeb=$(ls "$cfgdir"/ameridroid-archive-keyring_*_all.deb | sort -V | tail -1)
cp "$keydeb" $chroot/tmp/ameridroid-archive-keyring.deb
run_in_chroot "dpkg -i /tmp/ameridroid-archive-keyring.deb && rm /tmp/ameridroid-archive-keyring.deb"
cat <<EOF2 > $chroot/etc/apt/sources.list.d/ameridroid.list
deb [signed-by=$keyring] https://ameridroid.github.io/apt-repo/stable trixie main
deb [signed-by=$keyring] https://ameridroid.github.io/apt-repo/testing trixie main
EOF2

cat <<EOF2 > $chroot/etc/apt/preferences.d/ameridroid
Package: *
Pin: origin ameridroid.github.io
Pin-Priority: -1

Package: grub-common grub2-common grub-efi grub-efi-arm64 grub-efi-arm64-bin grub-efi-arm64-unsigned ameridroid-archive-keyring indiedroid-nova
Pin: origin ameridroid.github.io
Pin-Priority: 1001
EOF2

echo "deb http://deb.debian.org/debian trixie-backports main contrib non-free-firmware" > $chroot/etc/apt/sources.list.d/backports.list

password=$(openssl passwd -6 debian) # Password is "debian" (without quotes)

# The rootfs/ overlay is copied in after this hook, so install what the hook itself needs now.
install -Dm755 "$cfgdir/rootfs/etc/kernel/postinst.d/zz-nova-dtb" $chroot/etc/kernel/postinst.d/zz-nova-dtb
for u in resizefs oemcleanup; do
    install -Dm644 "$cfgdir/rootfs/usr/lib/systemd/system/$u.service" $chroot/usr/lib/systemd/system/$u.service
done

run_in_chroot "apt update"
run_in_chroot "apt install -y $pkgs"
run_in_chroot "apt install -y -t trixie-backports linux-image-arm64"
kver=$(chroot $chroot dpkg-query -W -f='${Version}' linux-image-arm64)
if ! chroot $chroot dpkg --compare-versions "$kver" ge 6.17; then
    echo "Kernel $kver is older than 6.17; Nova HDMI/GPU need a newer one" >&2
    exit 1
fi
run_in_chroot "apt upgrade -y"
run_in_chroot "/etc/kernel/postinst.d/zz-nova-dtb"
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
