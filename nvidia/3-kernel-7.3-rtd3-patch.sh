#!/usr/bin/env bash
# 1) xdg-desktop-portal so Firefox can use the PipeWire/libcamera webcam.
# 2) CachyOS fix for NVIDIA runtime D3 on kernel 7.3 ("Runtime D3: Not
#    supported"): since 615 the driver probes in a kthread, and on 7.3
#    kthreads have an empty root, so its /sys/.../config lookup fails.
#    Patch: CachyOS/kernel-patches PR #191 (14 lines, kernel-open/nvidia/nv-pci.c).
# Run as:  sudo bash nvidia/3-kernel-7.3-rtd3-patch.sh     then reboot.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH_SRC="$HERE/0004-Open-sysfs-config-from-the-userspace-root-on-7.3.patch"
SHA=a6bbae1da91bead7030ed78a161dedd2dc8d38d495ef87af24673642ef1d7ca9
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

echo "$SHA  $PATCH_SRC" | sha256sum -c --quiet || { echo "patch file changed since review - aborting"; exit 1; }

say "Installing xdg-desktop-portal (+ Hyprland backend)"
pacman -S --needed --noconfirm xdg-desktop-portal xdg-desktop-portal-hyprland

say "Installing the patch + re-apply helper"
install -Dm644 "$PATCH_SRC" /etc/nvidia-rtd3/0004-rtd3-kthread-root.patch
cat > /usr/local/bin/nvidia-rtd3-patch <<'EOF'
#!/bin/sh
# Apply the 7.3 runtime-D3 fix to every installed nvidia-open DKMS source.
# Idempotent; skips (with a message) if already fixed or no longer applicable.
P=/etc/nvidia-rtd3/0004-rtd3-kthread-root.patch
rc=0
for d in /usr/src/nvidia-*/; do
    f="$d/kernel-open/nvidia/nv-pci.c"
    [ -f "$f" ] || continue
    if grep -q scoped_with_init_fs "$f"; then
        echo "nvidia-rtd3: $d already has the fix"
        continue
    fi
    if patch -d "$d" -p1 --dry-run -s < "$P" >/dev/null 2>&1; then
        patch -d "$d" -p1 -s < "$P" && echo "nvidia-rtd3: patched $d"
    else
        echo "nvidia-rtd3: WARNING patch does not apply to $d (driver changed?) - skipped"
        rc=1
    fi
done
exit $rc
EOF
chmod 755 /usr/local/bin/nvidia-rtd3-patch

# 69- sorts before 70-dkms-install/-upgrade, so the source is patched
# before DKMS builds the new driver version.
cat > /etc/pacman.d/hooks/69-nvidia-rtd3-patch.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = nvidia-open-dkms

[Action]
Description = Applying NVIDIA runtime-D3 fix for kernel 7.3 to the DKMS source...
When = PostTransaction
Exec = /usr/local/bin/nvidia-rtd3-patch
EOF

say "Patching the current driver source"
/usr/local/bin/nvidia-rtd3-patch

V=$(basename /usr/src/nvidia-*/ | sed 's/^nvidia-//')
K=$(uname -r)
say "Rebuilding nvidia/$V for $K (old module stays if the build fails)"
dkms build "nvidia/$V" -k "$K" --force
dkms install "nvidia/$V" -k "$K" --force

say "Rebuilding initramfs (nvidia loads early)"
mkinitcpio -P

say "Verification"
ok=1
chk() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; ok=0; fi; }
chk "portal installed"        "command -v /usr/lib/xdg-desktop-portal >/dev/null || [ -x /usr/lib/xdg-desktop-portal ]"
chk "source patched"          "grep -q scoped_with_init_fs /usr/src/nvidia-$V/kernel-open/nvidia/nv-pci.c"
chk "dkms installed for $K"   "dkms status nvidia/$V -k $K | grep -q installed"
chk "pacman hook present"     "[ -f /etc/pacman.d/hooks/69-nvidia-rtd3-patch.hook ]"
chk "module in initramfs"     "lsinitcpio /boot/initramfs-linux.img | grep -q 'nvidia.ko'"
echo
[ "$ok" = 1 ] && echo "All good. Reboot, then check: grep 'Runtime D3' /proc/driver/nvidia/gpus/*/power" || echo "Something FAILED - fix it before rebooting."
