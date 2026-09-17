# Goodix 27c6:538d fingerprint reader on Arch / Omarchy

Working setup for the **Goodix 27c6:538d** ("Goodix TLS Fingerprint Sensor 53XD
(press)", a 64×80 press sensor) on Arch-based systems, including the Omarchy
desktop. It builds and installs the `libfprint` fork that actually drives this
sensor, then keeps that install from being clobbered by updates.

Stock `libfprint` does not handle this reader's TLS handshake/matcher well. This
uses [lbssousa/libfprint](https://github.com/lbssousa/libfprint) branch
`goodix-538d-sigfm-gtls` (OpenCV SIGFM matcher), pinned to a known-good commit.

## What you get

- `libfprint-goodix-538d` package, built from the fork above
- `IgnorePkg` for `libfprint*` so `pacman -Syu` does not replace it
- udev rule that keeps the reader out of USB autosuspend
- `fprintd` drop-in that only exposes reader dumps for debugging
- An Omarchy `post-update` hook that reinstalls the driver if an update drops it
- `enable-fingerprint-auth.sh` to switch on fingerprint for `sudo`, polkit, and
  the lock screen (and `--remove` to switch it back off)

After this, fingerprint works for lock screen, `sudo`, and polkit prompts, once
you enroll a finger and run `./enable-fingerprint-auth.sh`.

## Requirements

- Arch-based distro, `sudo`
- `base-devel`, `git`, `meson`, `cmake`, `pkgconf`, `opencv`
- The reader present: `lsusb` should show `ID 27c6:538d Shenzhen Goodix Technology`

## Install

```bash
git clone https://github.com/gj2908/Omarchy-Goodix-538d-fix.git
cd Omarchy-Goodix-538d-fix
./install.sh
```

The script builds the package (a few minutes) and installs everything. Re-running
it is safe; each step checks before it changes anything.

Options:

```bash
./install.sh --no-debug     # skip the fprintd dump drop-in
./install.sh --pkg path/to/libfprint-goodix-538d-*.pkg.tar.zst   # install a prebuilt package instead of building
./install.sh --dry-run      # print what would happen
```

## Enroll and test

```bash
fprintd-enroll              # press the sensor ~10 times, lifting between presses
fprintd-verify              # confirm a match
fprintd-list "$USER"        # show enrolled prints
```

## Enable fingerprint auth (sudo, lock, polkit)

Now hand the sensor to the auth stacks:

```bash
./enable-fingerprint-auth.sh           # sudo + polkit
./enable-fingerprint-auth.sh --lock    # also the Omarchy lock screen
```

The script inserts Omarchy's two lines at the top of `/etc/pam.d/sudo` and
`/etc/pam.d/polkit-1`:

```
auth  [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth  sufficient                  pam_fprintd.so
```

The `pam_exec` line is only added when Omarchy's lid check is installed. Because
`pam_fprintd` is `sufficient`, a failed read falls straight through to the
password, so this cannot lock you out. `--lock` additionally writes
`/etc/pam.d/omarchy-lock-fingerprint`, which the Omarchy shell lock uses.

Test it:

```bash
sudo -k && sudo true     # touch the sensor when prompted
```

Every file it edits is copied to `.pre-fingerprint` beside itself first, and
`./enable-fingerprint-auth.sh --remove` takes the lines back out.

On Omarchy, `omarchy-setup-security-fingerprint` does the same thing through the
wizard (and also wires the shell lock) — either path works.

## What the installer changes

| Path | Purpose |
| --- | --- |
| `/opt/goodix-538d/libfprint-goodix-538d-*.pkg.tar.zst` | keeps the built package for the update hook |
| `/etc/pacman.conf` | adds `IgnorePkg` for the `libfprint` family |
| `/etc/udev/rules.d/99-fingerprint-goodix.rules` | disables USB autosuspend for `27c6:538d` |
| `/etc/systemd/system/fprintd.service.d/debug.conf` | `GOODIX53XD_DUMP=/var/lib/fprint/fp` (optional) |
| `~/.config/omarchy/hooks/post-update.d/fingerprint-goodix-538d-hook` | reinstalls the driver after updates (Omarchy only) |

`install.sh` does not touch PAM. Fingerprint for `sudo`/polkit/lock is opt-in via
`./enable-fingerprint-auth.sh`, which edits `/etc/pam.d/sudo` and
`/etc/pam.d/polkit-1` (and, with `--lock`, `/etc/pam.d/omarchy-lock-fingerprint`).

## Troubleshooting

- Reader not found: `lsusb -d 27c6:538d`; check the udev rule loaded with
  `udevadm info -a -n /dev/bus/usb/...` and `journalctl -u fprintd`.
- Enroll succeeds but verify fails: re-enroll, pressing firmly and centered,
  lifting fully between presses. The SIGFM matcher is sensitive to partial
  presses.
- After an update the reader stops working: `pacman -Q libfprint-goodix-538d`
  should still be installed; if not, re-run `./install.sh` (or the hook).
- Debug dumps (if the drop-in is installed) land in `/var/lib/fprint/fp`.

## Uninstall

```bash
./uninstall.sh
```

Removes the hook, udev rule, fprintd drop-in, `IgnorePkg` entries, and the stored
package, then reinstalls the distro `libfprint`. Enrolled prints stay in
`/var/lib/fprint`; remove them with `fprintd-delete "$USER"`.

## License

The scripts and packaging here are MIT (see `LICENSE`). The library built by
`PKGBUILD` is LGPL, from the upstream fork.
