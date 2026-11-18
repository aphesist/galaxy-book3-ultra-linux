#!/usr/bin/env bash
# Webcam (OV02C10): upright image + brighter default + browser camera portal.
#  - Adds a `rotation` parameter to the ov02c10 DKMS driver (overrides the
#    firmware's 0°). With rotation=180, libcamera turns on the sensor's own
#    H+V flip for every app, which is the orientation the fork's init
#    registers (0x3820=0xb0) already intended.
#  - Default digital gain 6x (dgain=6144). Change it in
#    /etc/modprobe.d/ov02c10.conf: 1024=1x (darkest, least grain), 4096=4x.
#  - xdg-desktop-portal-gtk: the camera portal's "Access" backend (Firefox).
# Needs the ov02c10 DKMS driver from Andycodeman/samsung-galaxy-book-linux-fixes first.
# Run as:  sudo bash camera/install.sh     then reboot.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
SRC=/usr/src/ov02c10-1.0/ov02c10.c
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
[ -f "$SRC" ] || { echo "$SRC missing: install the ov02c10 DKMS driver first (see README)"; exit 1; }

say "xdg-desktop-portal-gtk (camera access for browsers)"
pacman -S --needed --noconfirm xdg-desktop-portal-gtk

say "Patching $SRC (rotation parameter)"
if grep -q "rotation_override" "$SRC"; then
    echo "already patched"
else
    cp -a "$SRC" "$SRC.orig"
    python3 -I - "$SRC" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
a1 = "/* Apply the max_exp cap to a computed exposure ceiling. */\n"
a2 = ("\tret = v4l2_fwnode_device_parse(ov02c10->dev, &props);\n"
      "\tif (ret)\n\t\treturn ret;\n")
assert s.count(a1) == 1 and s.count(a2) == 1, "anchors not found - driver changed"
param = (
    "/* Local: firmware reports 0 deg on the Galaxy Book3 Ultra, but the sensor\n"
    " * is mounted upside down. -1 = use firmware value. */\n"
    "static int rotation_override = -1;\n"
    "module_param_named(rotation, rotation_override, int, 0444);\n"
    "MODULE_PARM_DESC(rotation, \"Override mounting rotation in degrees (0 or 180). -1 = firmware (default).\");\n\n")
over = ("\tif (rotation_override == 0 || rotation_override == 180)\n"
        "\t\tprops.rotation = rotation_override;\n")
s = s.replace(a1, param + a1, 1).replace(a2, a2 + over, 1)
open(p, "w").write(s)
EOF
    echo "patched (original kept as $SRC.orig)"
fi

say "/etc/modprobe.d/ov02c10.conf"
cat > /etc/modprobe.d/ov02c10.conf <<'EOF'
# Webcam (OV02C10). rotation=180: sensor is mounted upside down.
# dgain: default digital gain, 1024=1x 2048=2x 3072=3x 4096=4x (more = brighter + grainier)
options ov02c10 rotation=180 dgain=6144
EOF

say "Rebuilding ov02c10 for $(uname -r)"
dkms build ov02c10/1.0 -k "$(uname -r)" --force
dkms install ov02c10/1.0 -k "$(uname -r)" --force

say "Verification"
modinfo -p ov02c10 2>/dev/null | grep -q "^rotation" && echo "  ok   rotation parameter in installed module" || echo "  FAIL rotation parameter missing"
echo
echo "Done. Reboot. Then copy 50-hide-ipu6-raw-v4l2.conf and 50-egl-mesa.conf (see README)."
