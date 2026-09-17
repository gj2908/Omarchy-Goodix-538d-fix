#!/bin/bash
# Undo install.sh: remove the hook, udev rule, drop-in, IgnorePkg entries, and
# the stored package, then put the distro libfprint back.
#
#   ./uninstall.sh [--dry-run]

set -euo pipefail

pkg_store=/opt/goodix-538d
udev_rule=/etc/udev/rules.d/99-fingerprint-goodix.rules
fprintd_dropin=/etc/systemd/system/fprintd.service.d/debug.conf
hook_name=fingerprint-goodix-538d-hook
hook_path="$HOME/.config/omarchy/hooks/post-update.d/$hook_name"
ignore_names=(libfprint-goodix-538d libfprint-goodix-521d libfprint-git libfprint)

dry_run=false
[[ ${1:-} == "--dry-run" && $# -eq 1 ]] && dry_run=true

say() { printf '\n==> %s\n' "$*"; }
run() {
  if [[ $dry_run == true ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

[[ $EUID -ne 0 ]] || { echo "run as your normal user, not root" >&2; exit 1; }

say "Removing Omarchy hook"
run rm -f "$hook_path"

say "Removing udev rule"
run sudo rm -f "$udev_rule"
run sudo udevadm control --reload

say "Removing fprintd drop-in"
run sudo rm -f "$fprintd_dropin"
run sudo systemctl daemon-reload

say "Removing ${ignore_names[*]} from IgnorePkg"
if grep -qE '^[[:space:]]*IgnorePkg[[:space:]]*=' /etc/pacman.conf; then
  if [[ $dry_run == true ]]; then
    printf '  [dry-run] drop our names from the IgnorePkg line in /etc/pacman.conf\n'
  else
    sudo cp -a /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%s)"
    name_list=${ignore_names[*]}
    awk -v names="$name_list" '
      BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) drop[a[i]] = 1 }
      /^[[:space:]]*IgnorePkg[[:space:]]*=/ && !done {
        done = 1
        split($0, parts, "=")
        m = split(parts[2], toks, " ")
        kept = ""
        for (j = 1; j <= m; j++) {
          if (!(toks[j] in drop)) kept = kept (kept == "" ? "" : " ") toks[j]
        }
        if (kept == "") next
        print "IgnorePkg = " kept
        next
      }
      { print }
    ' /etc/pacman.conf > /tmp/pacman.conf.new
    sudo install -m 644 /tmp/pacman.conf.new /etc/pacman.conf
    rm -f /tmp/pacman.conf.new
    pacman-conf >/dev/null || { echo "pacman.conf failed to parse; restore a .bak copy" >&2; exit 1; }
  fi
fi

say "Removing stored package"
run sudo rm -rf "$pkg_store"

say "Reinstalling the distro libfprint"
run sudo pacman -S --noconfirm libfprint

say "Restarting fprintd"
run sudo systemctl restart fprintd

printf '\nDone. Enrolled prints remain in /var/lib/fprint; remove with: fprintd-delete %s\n' "$USER"
