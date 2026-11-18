#!/usr/bin/env bash
# sudo: finger first (1 try, 10 s), then the normal password prompt.
# Run as:  sudo bash fingerprint/3-sudo-fingerprint.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
cp -a /etc/pam.d/sudo "/etc/pam.d/sudo.bak-$(date +%Y%m%d-%H%M%S)"
if ! grep -q pam_fprintd /etc/pam.d/sudo; then
    sed -i '0,/^auth/s//auth\t\tsufficient\tpam_fprintd.so max-tries=1 timeout=10\nauth/' /etc/pam.d/sudo
fi
awk '/^auth/{print; exit}' /etc/pam.d/sudo | grep -q pam_fprintd && echo "ok   fprintd before password" || echo "FAIL"
grep -q 'auth.*include.*system-auth' /etc/pam.d/sudo && echo "ok   password fallback intact" || echo "FAIL system-auth missing"
