<div align="center">

# Galaxy Book3 Ultra on Linux

**The hardware fixes, one folder each**

![Arch](https://img.shields.io/badge/Arch_Linux-kernel_7.3-18181b)
![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-ffffff)
![Laptop](https://img.shields.io/badge/Galaxy_Book3_Ultra-NP960XFH-888888)
![License](https://img.shields.io/badge/license-MIT-d71920)

[NVIDIA](#nvidia--the-rtx-sleeps-when-idle) · [Webcam](#webcam--upright-bright-one-camera) · [Fingerprint](#fingerprint--egis-match-on-chip-with-sdcp)

</div>

The Galaxy Book3 Ultra (Intel Raptor Lake iGPU + RTX 4070, 2880×1800 OLED,
OV02C10 webcam, Egis fingerprint reader) runs Arch almost perfectly. These are
the three things that didn't work out of the box, with the fix for each, and
why the fix works.

Every script is **idempotent** (safe to run twice), checks its own result at
the end, and prints how to undo it. Root scripts say so in their header. Run
them yourself after reading them. Nothing here asks you for a password.

Tested on: `linux 7.3.4`, `nvidia-open-dkms 620.70.06`, `fprintd 1.94.5`.

## NVIDIA: the RTX sleeps when idle

| Symptom | Cause | Fix |
|---|---|---|
| RTX stays powered (≈ 5–8 W) even with nothing on it | runtime power management off by default | `nvidia/1-runtime-pm.sh` |
| …still on after that | the driver binds inside the initramfs, before the udev rule exists | `nvidia/2-initramfs-udev-rule.sh` |
| `/proc/driver/nvidia/gpus/*/power` says *Runtime D3: Disabled by default* | on kernel 7.3, kthreads have an empty root, so the driver's `/sys/.../config` lookup fails | `nvidia/3-kernel-7.3-rtd3-patch.sh` |

```sh
sudo bash nvidia/1-runtime-pm.sh
sudo bash nvidia/2-initramfs-udev-rule.sh
sudo bash nvidia/3-kernel-7.3-rtd3-patch.sh     # kernel 7.3+ only
reboot
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status   # → suspended
```

- **Step 1:** fine-grained RTD3 (`NVreg_DynamicPowerManagement=0x02`), S0ix for s2idle, the Arch-wiki udev rule, and `nvidia-suspend/resume/hibernate`.
- **Step 3:** a 14-line patch to `kernel-open/nvidia/nv-pci.c` that uses `scoped_with_init_fs()`. It comes from [CachyOS/kernel-patches#191](https://github.com/CachyOS/kernel-patches/pull/191) by *treshaun*, and the script pins its SHA-256. A pacman hook (`69-`, before DKMS's `70-`) re-applies it on every `nvidia-open-dkms` upgrade, and skips it with a warning once upstream ships the fix.

The RTX only sleeps if nothing holds it open. `camera/50-egl-mesa.conf` makes
EGL default to Mesa, so idle Wayland clients don't wake the RTX. Use
`prime-run <app>` to run something on it.

## Webcam: upright, bright, one camera

The OV02C10 needs an out-of-tree driver first, because the board feeds it
26 MHz and mainline only accepts 19.2 MHz. Install it from
[Andycodeman/samsung-galaxy-book-linux-fixes](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes)
(`webcam-fix-libcamera`). This repo builds on top of it:

| Symptom | Fix |
|---|---|
| Image upside down | adds a `rotation` module parameter to the DKMS source (the firmware reports 0°; the sensor is mounted at 180°). libcamera then enables the sensor's own H+V flip for every app |
| Image very dark | default digital gain 6× (`dgain=6144`) in `/etc/modprobe.d/ov02c10.conf` |
| Firefox lists 30+ "ipu6" cameras that all fail | `50-hide-ipu6-raw-v4l2.conf` hides the raw ISYS nodes from WirePlumber; only *Built-in Front Camera* stays |
| Firefox can't open the camera at all | `xdg-desktop-portal-gtk` provides the portal's *Access* backend |
| Webcam fails with GPU debayer errors | `50-egl-mesa.conf`: glvnd would try NVIDIA's EGL first |

```sh
sudo bash camera/install.sh     # rotation patch + gain + portal, rebuilds DKMS
mkdir -p ~/.config/wireplumber/wireplumber.conf.d ~/.config/environment.d
cp camera/50-hide-ipu6-raw-v4l2.conf ~/.config/wireplumber/wireplumber.conf.d/
cp camera/50-egl-mesa.conf ~/.config/environment.d/
reboot
```

Brighter or darker: edit `dgain` in `/etc/modprobe.d/ov02c10.conf` (1024 = 1×)
and reboot. Don't probe the camera with `cam` while an app is streaming: libcamera
resets the flips when it initialises the sensor.

Want a cleaner picture? The setup above uses libcamera's software ISP, which
is grainy and flat. [galaxy-book3-ultra-ipu6-camera](https://github.com/aphesist/galaxy-book3-ultra-ipu6-camera)
runs the webcam through Intel's own IPU6 pipeline (AIQ, like Windows) on top
of this driver: real contrast, much less grain, full frame rate.

## Fingerprint: Egis match-on-chip with SDCP

The reader is an **Egis `1c7a:05a1`** (firmware 9050.1.2.33). It needs
**SDCP**, the secure handshake Windows Hello uses. With Arch's libfprint the
sensor seems to work: it enrolls, then instantly answers *no-match* for every
finger, because the chip never stored the print. fprintd then deletes its own
record as well.

[TenSeventy7/libfprint-egismoc-sdcp](https://github.com/TenSeventy7/libfprint-egismoc-sdcp)
implements SDCP for this driver. `fingerprint/PKGBUILD` builds that fork
(pinned to the reviewed commit `4d128d4`) as `libfprint-egismoc-sdcp`, which
`provides`/`conflicts` with `libfprint`, so fprintd just uses it.

```sh
bash fingerprint/1-install.sh             # as your user: builds + installs, resets fprintd
fprintd-enroll && fprintd-verify
sudo bash fingerprint/2-lock-screen-pam.sh   # finger-only PAM for Panacea's lock screen
sudo bash fingerprint/3-sudo-fingerprint.sh  # optional: finger first for sudo
```

| File | What it does |
|---|---|
| `/etc/pam.d/panacea-fprint` | `pam_fprintd max-tries=1 timeout=30`: the lock screen restarts it after each miss, so the finger works at any time with no password first. The password path still uses `swaylock` and unlocks the keyring |
| `/etc/pam.d/sudo` | `pam_fprintd` *sufficient* before `system-auth`; the password stays as the fallback |

The lock-screen side (the indicator and auto-retry) lives in
[panacea-config](https://github.com/aphesist/panacea-config).

Undo: `sudo pacman -S libfprint`.

## See also

- [galaxy-book3-ultra-ipu6-camera](https://github.com/aphesist/galaxy-book3-ultra-ipu6-camera): the webcam through Intel's IPU6 AIQ pipeline
- [panacea-config](https://github.com/aphesist/panacea-config): the desktop on top
- [arch-setup](https://github.com/aphesist/arch-setup): silent boot, autologin into a locked Hyprland, apps and dev tools

## Credits

CachyOS / *treshaun* (NVIDIA 7.3 patch) · *Andycodeman* (OV02C10 driver) ·
*TenSeventy7* (SDCP libfprint) · the Arch wiki. Their code keeps its own
licences (GPL-2.0, LGPL-2.1); the scripts in this repo are MIT.
