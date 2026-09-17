#!/bin/bash
# Install the Goodix 27c6:538d fingerprint driver and keep it installed.
#
# Run as your normal user (not root) from a clone of this repository:
#   ./install.sh
#
# Options:
#   --no-debug     skip the fprintd dump drop-in
#   --pkg FILE     install a prebuilt .pkg.tar.zst instead of building
#   --dry-run      show what would change, change nothing
#   -h, --help     this text

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

pkg_name=libfprint-goodix-538d
pkg_store=/opt/goodix-538d
udev_rule=/etc/udev/rules.d/99-fingerprint-goodix.rules
fprintd_dropin=/etc/systemd/system/fprintd.service.d/debug.conf
hook_name=fingerprint-goodix-538d-hook
ignore_names=(libfprint-goodix-538d libfprint-goodix-521d libfprint-git libfprint)

prebuilt=
dry_run=false
install_debug=true

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while (( $# > 0 )); do
  case $1 in
    --no-debug) install_debug=false ;;
    --pkg)
      shift
      prebuilt=${1:-}
      [[ -n $prebuilt ]] || { echo "--pkg needs a file" >&2; exit 2; }
      ;;
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n==> %s\n' "$*"; }

run() {
  if [[ $dry_run == true ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run this as your normal user, not root (makepkg refuses root)"
command -v pacman >/dev/null 2>&1 || die "this is for Arch-based systems (pacman not found)"

if ! lsusb -d 27c6:538d >/dev/null 2>&1; then
  echo "warning: no 27c6:538d reader on the USB bus right now." >&2
  echo "         continuing, but enroll/verify will fail until it is plugged in." >&2
fi

pkg_install() {
  if command -v omarchy-pkg-add >/dev/null 2>&1; then
    run omarchy-pkg-add "$@"
  else
    run sudo pacman -S --needed --noconfirm "$@"
  fi
}

add_missing_pkg() {
  local want=("$@") pkg
  local missing=()
  for pkg in "${want[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  (( ${#missing[@]} > 0 )) || return 0

  say "Installing build dependencies: ${missing[*]}"
  pkg_install "${missing[@]}"
}

build_package() {
  say "Building $pkg_name from source (this takes a few minutes)"
  local build_dir
  build_dir=$(mktemp -d)
  cp "$repo_dir/PKGBUILD" "$repo_dir/fix-tests-foreach.patch" "$build_dir/"

  if [[ $dry_run == true ]]; then
    printf '  [dry-run] makepkg -f --noconfirm in %s\n' "$build_dir"
    built_pkg="$build_dir/${pkg_name}-1.94.10-1-x86_64.pkg.tar.zst"
    return 0
  fi

  ( cd "$build_dir" && makepkg -f --noconfirm )
  built_pkg=$(find "$build_dir" -maxdepth 1 -name "${pkg_name}-*.pkg.tar.zst" ! -name '*-debug-*' | head -1)
  [[ -n $built_pkg && -f $built_pkg ]] || die "build finished but no package was produced"
}

install_package() {
  local pkg=$1
  say "Installing $(basename "$pkg")"
  run sudo mkdir -p "$pkg_store"
  run sudo cp "$pkg" "$pkg_store/"
  run sudo pacman -U --noconfirm --ask 4 "$pkg"
}

ignore_pacman_pkg() {
  local joined="${ignore_names[*]}"
  if grep -qE '^[[:space:]]*IgnorePkg[[:space:]]*=' /etc/pacman.conf; then
    if ! grep -E '^[[:space:]]*IgnorePkg[[:space:]]*=' /etc/pacman.conf | grep -qw "${ignore_names[0]}"; then
      say "Adding ${ignore_names[*]} to IgnorePkg"
      run sudo cp -a /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%s)"
      if [[ $dry_run != true ]]; then
        awk -v add=" $joined" '
          /^[[:space:]]*IgnorePkg[[:space:]]*=/ && !done { $0 = $0 add; done = 1 }
          { print }
        ' /etc/pacman.conf > /tmp/pacman.conf.new
        sudo install -m 644 /tmp/pacman.conf.new /etc/pacman.conf
        rm -f /tmp/pacman.conf.new
        pacman-conf >/dev/null || die "pacman.conf failed to parse; restore the .bak copy"
      fi
    fi
  else
    say "Setting IgnorePkg = $joined"
    run sudo cp -a /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%s)"
    if [[ $dry_run != true ]]; then
      awk -v line="IgnorePkg = $joined" '
        { print }
        /^\[options\]/ && !done { print line; done = 1 }
      ' /etc/pacman.conf > /tmp/pacman.conf.new
      sudo install -m 644 /tmp/pacman.conf.new /etc/pacman.conf
      rm -f /tmp/pacman.conf.new
      pacman-conf >/dev/null || die "pacman.conf failed to parse; restore the .bak copy"
    fi
  fi
}

install_udev_rule() {
  say "Installing udev autosuspend rule"
  run sudo install -m 644 -o root -g root "$repo_dir/files/99-fingerprint-goodix.rules" "$udev_rule"
  run sudo udevadm control --reload
  run sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=27c6
}

install_fprintd_dropin() {
  [[ $install_debug == true ]] || return 0
  say "Installing fprintd dump drop-in"
  run sudo install -m 644 -o root -g root "$repo_dir/files/fprintd-debug.conf" "$fprintd_dropin"
  run sudo systemctl daemon-reload
}

install_omarchy_hook() {
  [[ -d $HOME/.config/omarchy/hooks ]] || return 0
  say "Installing Omarchy post-update hook"
  if [[ $dry_run == true ]]; then
    printf '  [dry-run] install %s into ~/.config/omarchy/hooks/post-update.d\n' "$hook_name"
    return 0
  fi
  mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
  install -m 755 "$repo_dir/files/$hook_name" "$HOME/.config/omarchy/hooks/post-update.d/$hook_name"
}

say "Checking for $pkg_name"
if [[ -n $prebuilt ]]; then
  [[ -f $prebuilt ]] || die "--pkg file not found: $prebuilt"
  built_pkg=$prebuilt
else
  say "Ensuring base-devel is present"
  pkg_install base-devel
  add_missing_pkg git meson cmake pkgconf opencv
  build_package
fi

install_package "$built_pkg"
ignore_pacman_pkg
install_udev_rule
install_fprintd_dropin
install_omarchy_hook

say "Restarting fprintd"
run sudo systemctl restart fprintd

cat <<'NEXT'

Done. Next steps:

  fprintd-enroll          # press the sensor ~10 times, lifting between presses
  fprintd-verify          # confirm a match

To use it for sudo/polkit, and the lock screen:

  ./enable-fingerprint-auth.sh          # sudo + polkit
  ./enable-fingerprint-auth.sh --lock   # also the Omarchy lock screen

On Omarchy, omarchy-setup-security-fingerprint does the same through the wizard.

NEXT
