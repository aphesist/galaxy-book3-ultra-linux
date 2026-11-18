#!/usr/bin/env bash
# The NVIDIA driver binds inside the initramfs (early KMS), before
# /etc/udev/rules.d exists, so 80-nvidia-pm.rules never fired and the RTX
# stayed at power/control=on. Ship the rule in the initramfs too.
# Run as:  sudo bash nvidia/2-initramfs-udev-rule.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
GPU=$(dirname "$(grep -l 0x10de /sys/bus/pci/devices/*/vendor | head -1)")

echo "==> mkinitcpio drop-in: include the NVIDIA runtime-PM udev rule"
cat > /etc/mkinitcpio.conf.d/20-nvidia-pm.conf <<'EOF'
# nvidia binds in the initramfs; its runtime-PM udev rule must be there too.
FILES+=(/etc/udev/rules.d/80-nvidia-pm.rules)
EOF
mkinitcpio -P

echo "==> Live test: power/control=auto now (no reboot needed for this test)"
echo auto > "$GPU/power/control"
for i in $(seq 1 15); do
    s=$(cat "$GPU/power/runtime_status")
    printf '  %2ss: %s\n' "$i" "$s"
    [ "$s" = suspended ] && break
    sleep 1
done
grep -E "Runtime D3|Video Memory:" /proc/driver/nvidia/gpus/*/power || true

echo
lsinitcpio /boot/initramfs-linux.img | grep -q 80-nvidia-pm.rules \
  && echo "ok   rule is inside the initramfs" || echo "FAIL rule missing from initramfs"
[ "$(cat "$GPU/power/runtime_status")" = suspended ] \
  && echo "ok   RTX suspended (it will wake automatically when something uses it)" \
  || echo "note RTX still active - expected while something holds it open; check again after a reboot (see README)"
