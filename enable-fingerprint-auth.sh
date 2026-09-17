#!/bin/bash
# Enable fingerprint authentication for sudo and polkit prompts.
#
# Run as your normal user:
#   ./enable-fingerprint-auth.sh            # sudo + polkit
#   ./enable-fingerprint-auth.sh --lock     # also create the Omarchy lock stack
#   ./enable-fingerprint-auth.sh --remove   # take the fingerprint lines back out
#   ./enable-fingerprint-auth.sh --dry-run  # show what would change
#
# Adds this to the top of each auth stack:
#   auth  [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
#   auth  sufficient                  pam_fprintd.so
# The pam_exec gate is only added when Omarchy's lid check is installed. Because
# pam_fprintd is `sufficient`, a failed or absent finger still falls through to
# the password, so this cannot lock you out.

set -euo pipefail

gate=/usr/bin/omarchy-hw-laptop-closed
lock_pam=/etc/pam.d/omarchy-lock-fingerprint
targets=(/etc/pam.d/sudo /etc/pam.d/polkit-1)

dry_run=false
do_remove=false
do_lock=false

for arg in "$@"; do
  case $arg in
    --dry-run) dry_run=true ;;
    --remove) do_remove=true ;;
    --lock) do_lock=true ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ $EUID -ne 0 ]] || { echo "run as your normal user, not root" >&2; exit 1; }

say() { printf '\n==> %s\n' "$*"; }
run() {
  if [[ $dry_run == true ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

if command -v fprintd-list >/dev/null 2>&1; then
  if ! fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#'; then
    printf 'note: no fingerprints enrolled yet; run fprintd-enroll before testing.\n' >&2
  fi
fi

has_fingerprint() { grep -q 'pam_fprintd\.so' "$1"; }

add_block() {
  local file=$1 tmp line first=1 block
  tmp=$(mktemp)
  block="auth       sufficient   pam_fprintd.so"
  if [[ -x $gate ]]; then
    block="auth      [success=1 default=ignore] pam_exec.so quiet $gate"$'\n'"$block"
  fi

  {
    while IFS= read -r line || [[ -n $line ]]; do
      if (( first == 1 )); then
        first=0
        if [[ $line == '#%PAM-1.0' ]]; then
          printf '%s\n%s\n' "$line" "$block"
        else
          printf '%s\n%s\n' "$block" "$line"
        fi
      else
        printf '%s\n' "$line"
      fi
    done < "$file"
  } > "$tmp"

  run sudo cp -a "$file" "$file.pre-fingerprint"
  run sudo install -m 644 -o root -g root "$tmp" "$file"
  rm -f "$tmp"
}

remove_block() {
  local file=$1 tmp
  tmp=$(mktemp)
  grep -vE 'pam_exec\.so quiet .*omarchy-hw-laptop-closed|pam_fprintd\.so' "$file" > "$tmp" || true
  run sudo cp -a "$file" "$file.pre-fingerprint"
  run sudo install -m 644 -o root -g root "$tmp" "$file"
  rm -f "$tmp"
}

create_lock_pam() {
  local tmp
  tmp=$(mktemp)
  printf '#%%PAM-1.0\nauth       required                    pam_fprintd.so\naccount    include                     system-local-login\n' > "$tmp"
  run sudo install -m 644 -o root -g root "$tmp" "$lock_pam"
  rm -f "$tmp"
}

if [[ $do_remove == true ]]; then
  for file in "${targets[@]}"; do
    [[ -f $file ]] || continue
    if has_fingerprint "$file"; then
      say "Removing fingerprint auth from $file"
      remove_block "$file"
    else
      say "$file has no fingerprint lines; leaving it"
    fi
  done
  if [[ -f $lock_pam ]]; then
    say "Removing $lock_pam"
    run sudo rm -f "$lock_pam"
  fi
else
  for file in "${targets[@]}"; do
    if [[ ! -f $file ]]; then
      printf 'skip: %s does not exist\n' "$file" >&2
      continue
    fi
    if has_fingerprint "$file"; then
      say "$file already enables fingerprint auth; leaving it"
    else
      say "Enabling fingerprint auth in $file"
      add_block "$file"
    fi
  done

  if [[ $do_lock == true ]]; then
    if [[ -f $lock_pam ]]; then
      say "$lock_pam already exists; leaving it"
    else
      say "Creating $lock_pam"
      create_lock_pam
    fi
  fi
fi

say "Done"
cat <<'NEXT'

Test sudo (touch the sensor when prompted):

  sudo -k && sudo true

Each file you changed has a .pre-fingerprint backup beside it, e.g.
  sudo cp /etc/pam.d/sudo.pre-fingerprint /etc/pam.d/sudo

Take it all back out with:
  ./enable-fingerprint-auth.sh --remove
NEXT
