#!/usr/bin/env bash
#
# Omarchy server post-install: remove desktop-only applications.
#
# Only packages that are actually installed are passed to pacman, so the
# script is safe to re-run. Packages still required by other installed
# packages are left alone (pacman refuses the transaction rather than
# forcing a broken system).
#
# Usage:
#   ./server-uninstall-packages.sh              # preview, confirm, then remove
#   ./server-uninstall-packages.sh --dry-run    # show what would happen, change nothing
#   ./server-uninstall-packages.sh --yes        # non-interactive / unattended confirmation
#
# Root is not required to start the script: only the pacman calls are
# elevated. pkexec is preferred so the password prompt appears as a polkit
# dialog; sudo is the fallback for systems without a polkit agent.

set -euo pipefail

# ---------------------------------------------------------------------------
# Packages to remove, exactly as requested. Alias resolution happens below.
# Add entries here (not in the removal logic) to change the target set.
# ---------------------------------------------------------------------------
readonly REQUESTED=(
  libreoffice-fresh
  libreoffice-still
  obsidian
  typora
  marktext
  zathura
  zathura-pdf-mupdf
  pinta
  gimp
  inkscape
  kdenlive
  obs-studio
  spotify
  vlc
  loupe
  discord
  telegram-desktop
  zoom
  basecamp
  'xournal++'
)

# Friendly / commonly used names that differ from the real Arch package name.
resolve_package() {
  case $1 in
    'xournal++') printf '%s\n' 'xournalpp' ;;
    *)           printf '%s\n' "$1" ;;
  esac
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: server-uninstall-packages.sh [OPTIONS]

Remove desktop-only applications from a server after an Omarchy install.
Elevation uses pkexec (polkit password dialog), falling back to sudo.

Options:
  -n, --dry-run   List installed targets and the command that would run;
                  make no changes.
  -y, --yes       Skip the confirmation prompt (for unattended runs).
  -h, --help      Show this help and exit.

Exit status:
  0  success, or nothing needed to be done
  1  preflight/removal error
  2  invalid command-line option
EOF
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
dry_run=false
assume_yes=false

while (($#)); do
  case $1 in
    -n|--dry-run) dry_run=true ;;
    -y|--yes)     assume_yes=true ;;
    -h|--help)    usage; exit 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
pacman_path=$(command -v pacman) \
  || die 'pacman not found; this script is for Arch-based Omarchy systems.'

# pkexec requires an absolute path to the program to run.
if (( EUID == 0 )); then
  pacman_cmd=("$pacman_path")
elif command -v pkexec >/dev/null 2>&1; then
  pacman_cmd=(pkexec "$pacman_path")
elif command -v sudo >/dev/null 2>&1; then
  pacman_cmd=(sudo "$pacman_path")
else
  die 'run as root, or install pkexec/sudo (only the pacman calls need elevation).'
fi

# ---------------------------------------------------------------------------
# Work out what is actually installed.
# ---------------------------------------------------------------------------
declare -a to_remove=()   # real package names, in requested order
declare -a absent=()      # requested names that are not installed
declare -A seen=()

add_package() {
  local pkg=$1
  [[ -z ${seen[$pkg]+x} ]] || return 0
  seen[$pkg]=1
  to_remove+=("$pkg")
}

for requested in "${REQUESTED[@]}"; do
  pkg=$(resolve_package "$requested")
  if pacman -Q -- "$pkg" >/dev/null 2>&1; then
    add_package "$pkg"
  else
    absent+=("$requested")
  fi
done

# LibreOffice language packs have a hard dependency on their base package.
# Leaving them installed makes `pacman -Rs libreoffice-fresh|still` fail, so
# include any that are present. They are unusable without the base anyway.
# (Expansion iterates over a snapshot; appending inside the loop is safe.)
for pkg in "${to_remove[@]}"; do
  case $pkg in
    libreoffice-fresh|libreoffice-still)
      prefix="$pkg-"
      while read -r candidate _rest; do
        [[ $candidate == "$prefix"* ]] && add_package "$candidate"
      done < <(pacman -Q)
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Report and confirm
# ---------------------------------------------------------------------------
printf 'Omarchy server post-install: desktop application cleanup\n'
printf 'Requested: %d package(s)\n' "${#REQUESTED[@]}"

if ((${#to_remove[@]})); then
  printf '\nInstalled - will be removed (%d):\n' "${#to_remove[@]}"
  printf '  %s\n' "${to_remove[@]}"
else
  printf '\nNo requested packages are installed. Nothing to remove.\n'
fi

if ((${#absent[@]})); then
  printf '\nNot installed - skipped (%d):\n' "${#absent[@]}"
  printf '  %s\n' "${absent[@]}"
fi

if ((${#to_remove[@]} == 0)); then
  printf '\nAlready clean; no changes made.\n'
  exit 0
fi

if $dry_run; then
  printf '\nDry run - no changes made.\n'
  printf 'Would run: %s -Rs --noconfirm %s\n' \
    "${pacman_cmd[*]}" "${to_remove[*]}"
  exit 0
fi

if ! $assume_yes; then
  [[ -t 0 ]] || die 'non-interactive shell: use --yes to confirm or --dry-run to preview.'
  printf '\nRemove these packages and their now-unused dependencies? [y/N] '
  IFS= read -r reply || die 'no answer received; aborting without changes.'
  case $reply in
    y|Y|yes|YES|Yes) ;;
    *) printf 'Aborted; no changes made.\n'; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Remove in a single pacman transaction.
#
# -R   remove only the named packages (no --dbonly tricks)
# -s   also remove dependencies no longer required by any installed package
#      (pacman will NOT break packages that still need them)
# No -n: modified config files are kept as .pacsave instead of being deleted.
# ---------------------------------------------------------------------------
printf '\nRemoving %d package(s)...\n' "${#to_remove[@]}"
if ! "${pacman_cmd[@]}" -Rs --noconfirm "${to_remove[@]}"; then
  die 'pacman reported an error; re-run to see what is left, or resolve the conflict above.'
fi

printf '\nDone. Removed: %s\n' "${to_remove[*]}"
printf 'Re-run with --dry-run at any time to verify the system is clean.\n'
