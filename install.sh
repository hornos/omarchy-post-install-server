#!/usr/bin/env bash
#
# Bootstrap installer for the Omarchy post-install toolkit.
#
# Intended to be run straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main/install.sh | bash
#
# It installs server-install.sh and server-uninstall-packages.sh into a local
# bin directory (default: ~/.local/bin). Pass --run to execute the installer
# immediately; any remaining arguments are forwarded to server-install.sh.

set -euo pipefail

repo='https://github.com/hornos/omarchy-post-install-server'
raw='https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main'
scripts=(server-install.sh server-uninstall-packages.sh)

install_dir="${OMARCHY_POST_INSTALL_DIR:-$HOME/.local/bin}"
run_after=false
forward=()

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS] [-- [SERVER-INSTALL ARGS]]

Download and install the Omarchy post-install scripts locally.

Options:
  -d, --dir DIR      Install into DIR (default: \$HOME/.local/bin).
  -r, --run          Run server-install.sh after installing.
  -h, --help         Show this help and exit.

Environment:
  OMARCHY_POST_INSTALL_DIR   Same as --dir.

Examples:
  install.sh
  install.sh --run --dry-run
  install.sh --run --yes
EOF
}

while (($#)); do
  case $1 in
    -d|--dir)
      [[ $# -ge 2 ]] || die '--dir requires a path.'
      install_dir=$2
      shift 2
      ;;
    --dir=*)
      install_dir=${1#*=}
      shift
      ;;
    -r|--run)
      run_after=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      forward+=("$@")
      break
      ;;
    *)
      forward+=("$1")
      shift
      ;;
  esac
done

command -v curl >/dev/null 2>&1 || die 'curl is required to install from GitHub.'

# When run from a local checkout, use the files beside this script. When piped
# from curl, BASH_SOURCE is empty/not a file, so download from the raw URL.
self=${BASH_SOURCE[0]:-}
source_dir=''
if [[ -n $self && -f $self ]]; then
  candidate=$(cd -- "$(dirname -- "$self")" && pwd)
  if [[ -f $candidate/server-install.sh && -f $candidate/server-uninstall-packages.sh ]]; then
    source_dir=$candidate
  fi
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if [[ -z $source_dir ]]; then
  printf 'Downloading the toolkit from %s\n' "$repo"
  for script in "${scripts[@]}"; do
    curl -fsSL --proto '=https' --proto-redir '=https' \
      -o "$tmpdir/$script" "$raw/$script" \
      || die "could not download $script."
    [[ -s $tmpdir/$script ]] || die "downloaded $script is empty."
  done
  source_dir=$tmpdir
else
  printf 'Using local checkout: %s\n' "$source_dir"
fi

for script in "${scripts[@]}"; do
  bash -n "$source_dir/$script" || die "$script failed its syntax check; nothing was installed."
done

mkdir -p -- "$install_dir"
for script in "${scripts[@]}"; do
  install -m 755 "$source_dir/$script" "$install_dir/$script"
done

printf 'Installed into %s:\n' "$install_dir"
for script in "${scripts[@]}"; do
  printf '  %s\n' "$install_dir/$script"
done

if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  printf 'Note: %s is not on your PATH in this shell.\n' "$install_dir" >&2
fi

if $run_after; then
  printf '\nRunning the server installer...\n'
  exec "$install_dir/server-install.sh" "${forward[@]}"
fi

if ((${#forward[@]})); then
  printf '\nNote: arguments were ignored because --run was not given.\n' >&2
fi

printf '\nNext: preview with\n  %s/server-install.sh --dry-run\n' "$install_dir"
