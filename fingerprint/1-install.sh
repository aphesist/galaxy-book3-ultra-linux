#!/usr/bin/env bash
# Build + install libfprint-egismoc-sdcp (replaces Arch's libfprint) and reset
# fprintd so it starts clean. Run as YOUR USER (makepkg refuses root):
#     bash fingerprint/1-install.sh
# pacman asks to remove the conflicting 'libfprint': answer y.
# Undo:  sudo pacman -S libfprint
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "run as your user, not root"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "Build deps"
sudo pacman -S --needed base-devel git meson ninja glib2-devel libgusb libgudev pixman openssl

say "Building the package (pinned commit, see PKGBUILD)"
B="$(mktemp -d)"; cp "$HERE/PKGBUILD" "$B/"; cd "$B"
makepkg -f

say "Installing (answer y to remove libfprint)"
sudo systemctl stop fprintd || true
sudo pacman -U ./libfprint-egismoc-sdcp-[0-9]*.pkg.tar.zst

say "Resetting fprintd's records (prints made with the old library can't verify)"
sudo rm -rf "/var/lib/fprint/$USER"
sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=1c7a || true

say "Verification"
pacman -Q libfprint-egismoc-sdcp && echo "  ok   package installed"
strings /usr/lib/libfprint-2.so.2 | grep -q "SDCP AuthorizedIdentity" && echo "  ok   libfprint has SDCP" || echo "  FAIL SDCP code missing"
echo; echo "Done. Enroll:  fprintd-enroll    then test:  fprintd-verify"
