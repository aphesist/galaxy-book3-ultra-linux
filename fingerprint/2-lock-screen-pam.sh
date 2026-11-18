#!/usr/bin/env bash
# Fingerprint on Panacea's lock: a finger-only PAM service used by the
#    patched lock.qml (panacea-config: hypr/custom/bin/lock-patch.py).
# Run as:  sudo bash fingerprint/2-lock-screen-pam.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

echo "==> /etc/pam.d/panacea-fprint"
cat > /etc/pam.d/panacea-fprint <<'EOF'
#%PAM-1.0
# Fingerprint-only unlock for Panacea's lock screen (patched lock.qml).
# Password unlock keeps using /etc/pam.d/swaylock (and unlocks the keyring).
# One 30 s attempt per run; the lock screen restarts it after a miss.
auth     required  pam_fprintd.so max-tries=1 timeout=30
account  required  pam_unix.so
EOF
chmod 644 /etc/pam.d/panacea-fprint

echo
[ -f /etc/pam.d/panacea-fprint ] && echo "ok   PAM service installed"
echo "Done."
