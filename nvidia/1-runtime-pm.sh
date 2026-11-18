#!/usr/bin/env bash
# NVIDIA runtime power management (RTD3 + S0ix) + PRIME test tools.
# Run as:  sudo bash nvidia/1-runtime-pm.sh
# Needs a reboot afterwards for the GPU part.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }


say "Installing mesa-utils, vulkan-tools (glxinfo/eglinfo/vulkaninfo for prime-run tests)"
pacman -S --needed --noconfirm mesa-utils vulkan-tools

# --------------------------------------------------------- NVIDIA power
say "NVIDIA: fine-grained runtime D3 + S0ix for s2idle"
cat > /etc/modprobe.d/nvidia-pm.conf <<'EOF'
# Let the RTX power off when idle (RTD3, fine-grained) and use S0ix during
# s2idle suspend (this laptop only offers s2idle by default).
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_EnableS0ixPowerManagement=1
EOF

# Arch wiki (PRIME / NVIDIA runtime D3): power/control=auto on driver bind.
cat > /etc/udev/rules.d/80-nvidia-pm.rules <<'EOF'
# Enable runtime PM for NVIDIA VGA/3D controllers and their audio function on bind
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="auto"
# Back to always-on when the driver unbinds
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="on"
EOF

# Video memory preservation is on by default (param = 2); its systemd
# helpers were disabled. NVIDIA's suspend path (incl. S0ix) expects them.
say "Enabling nvidia-suspend/resume/hibernate helpers"
systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service

# nvidia is loaded from the initramfs (early KMS), so the new modprobe
# options must be inside it.
say "Rebuilding initramfs"
mkinitcpio -P


say "Verification"
ok=1
chk() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; ok=0; fi; }
chk "glxinfo + vulkaninfo"        "command -v glxinfo >/dev/null && command -v vulkaninfo >/dev/null"
chk "modprobe options file"       "grep -q 'NVreg_DynamicPowerManagement=0x02' /etc/modprobe.d/nvidia-pm.conf"
chk "options inside initramfs"    "lsinitcpio /boot/initramfs-linux.img | grep -q 'modprobe.d/nvidia-pm.conf'"
chk "udev rule syntax"            "udevadm verify /etc/udev/rules.d/80-nvidia-pm.rules >/dev/null 2>&1"
chk "nvidia-suspend enabled"      "systemctl is-enabled -q nvidia-suspend"
echo
[ "$ok" = 1 ] && echo "All good. Now run nvidia/2-initramfs-udev-rule.sh, then reboot." \
              || echo "Something FAILED - fix it before rebooting."
