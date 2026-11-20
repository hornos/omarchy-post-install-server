#!/usr/bin/env bash
#
# Omarchy server post-install: install and configure the server toolset.
#
# Mirrors server-uninstall-packages.sh: checks current state first, uses
# pkexec for privileged work (sudo fallback), supports --dry-run/--yes, and
# is safe to re-run. Each task reports "already OK" and changes nothing when
# its target is already in place.
#
# Usage:
#   ./server-install.sh              # show current state, confirm, then apply
#   ./server-install.sh --dry-run    # show what would be done, change nothing
#   ./server-install.sh --yes        # unattended confirmation
#
# Install from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main/install.sh | bash
#
# Tasks: Flea (+ default file manager), disktree-bin (+ software OpenGL
# wrapper for older GPUs), Omarchy Control (+ menu integration), Tailscale,
# Rufust, OpenShell and TMOG.

set -euo pipefail

version='1.0.0'
repo_url='https://github.com/hornos/omarchy-post-install-server'

dry_run=false
assume_yes=false

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '  %s\n' "$*"; }

usage() {
  cat <<EOF
Usage: server-install.sh [OPTIONS]

Install and configure the Omarchy server toolset.

Options:
  -n, --dry-run   Show current state and the commands that would run;
                  make no changes.
  -y, --yes       Skip the confirmation prompt (for unattended runs).
  -v, --version   Print the version and exit.
  -h, --help      Show this help and exit.

Privilege escalation uses pkexec (polkit dialog) when available, falling
back to sudo, or no elevation at all when run as root. AUR packages are
installed with yay as the invoking desktop user.

Source: $repo_url
EOF
}

while (($#)); do
  case $1 in
    -n|--dry-run) dry_run=true ;;
    -y|--yes)     assume_yes=true ;;
    -v|--version) printf 'server-install.sh %s\n' "$version"; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v pacman >/dev/null 2>&1 \
  || die 'pacman not found; this script is for Arch-based Omarchy systems.'
pacman_path=$(command -v pacman)
bash_path=$(command -v bash)
systemctl_path=$(command -v systemctl || true)
omarchy_bin=$(command -v omarchy || true)
[[ -n $omarchy_bin ]] || die 'omarchy command not found; this needs an Omarchy install.'

target_user="${SUDO_USER:-${USER:-$(id -un)}}"
if (( EUID == 0 )) && [[ $target_user == root ]]; then
  target_user=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
fi

if (( EUID == 0 )); then
  priv=()
elif command -v pkexec >/dev/null 2>&1; then
  priv=(pkexec)
elif command -v sudo >/dev/null 2>&1; then
  priv=(sudo)
else
  die 'run as root, or install pkexec/sudo.'
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
run() {
  if $dry_run; then
    printf '  [dry-run]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

priv_run() { run "${priv[@]}" "$@"; }

aur_run() {
  # yay must never run as root. When the script itself is root, hand the AUR
  # install to the invoking desktop user instead.
  if (( EUID == 0 )) && [[ -n $target_user && $target_user != root ]]; then
    run runuser -u "$target_user" -- "$@"
  else
    run "$@"
  fi
}

write_file() {
  local path=$1 content=$2 mode=$3
  if $dry_run; then
    printf '  [dry-run] write %s (mode %s)\n' "$path" "$mode"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  chmod "$mode" "$path"
}

have_pkg() { pacman -Q -- "$1" >/dev/null 2>&1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_yay() {
  have_cmd yay || die 'yay is required (openshell-bin and tmog-bin come from the AUR).'
}

pkg_status() {
  if have_pkg "$1"; then pacman -Q "$1" | awk '{print $2}'; else printf 'missing\n'; fi
}

# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------
task_flea() {
  step 'Flea file manager'
  if have_pkg flea; then
    ok "flea already installed ($(pkg_status flea))"
  else
    priv_run "$omarchy_bin" pkg add flea
  fi

  local svc="$HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"
  if [[ -f $svc ]] && grep -qi 'flea' "$svc"; then
    ok 'Flea is already the default file manager'
  else
    # NOTE: if you use the Flea software-Vulkan shims, re-point the Exec line
    # at ~/.local/libexec/flea/flea-filemanager1 after this command.
    run flea --default
  fi
}

task_disktree() {
  step 'Disktree with software OpenGL (older GPUs)'
  if have_pkg disktree-bin; then
    ok "disktree-bin already installed ($(pkg_status disktree-bin))"
  else
    need_yay
    # disktree-bin is in the Omarchy repo, not the AUR; yay installs it happily.
    aur_run yay -S --needed --noconfirm disktree-bin
  fi

  if ! have_pkg mesa; then
    priv_run "$omarchy_bin" pkg add mesa
  fi

  # disktree's wgpu renderer fails on old Radeon/GL drivers. The per-user
  # wrapper forces Mesa's software GL for disktree only, leaving every other
  # application hardware-accelerated. Its .desktop file launches "disktree",
  # so this wrapper is picked up from PATH automatically. ~/.local/bin comes
  # before /usr/local/bin on Omarchy, so put it there and never clobber an
  # unrelated local executable.
  local wrapper="$HOME/.local/bin/disktree"
  if [[ -f $wrapper ]] \
     && grep -aq 'LIBGL_ALWAYS_SOFTWARE=1' "$wrapper" \
     && grep -aq '/usr/bin/disktree' "$wrapper"; then
    ok 'software OpenGL wrapper already configured'
  else
    if [[ -e $wrapper ]] && ! cmp -s "$wrapper" /usr/bin/disktree; then
      printf '  warning: %s exists and is not the packaged binary; leaving it untouched.\n' "$wrapper"
      printf '  Move it aside, then re-run to install the software-GL wrapper.\n'
      return 0
    fi
    if [[ -e $wrapper ]]; then
      ok 'replacing the local copy of /usr/bin/disktree with a software-GL wrapper'
    fi
    local body
    IFS= read -r -d '' body <<'EOF' || true
#!/bin/sh
# Force Mesa software OpenGL for disktree on older GPUs; other apps are
# unaffected. Installed by server-install.sh (safe to re-run).
export LIBGL_ALWAYS_SOFTWARE=1
exec /usr/bin/disktree "$@"
EOF
    write_file "$wrapper" "$body" 755
  fi

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) printf '  warning: %s is not in PATH; the wrapper will not be used.\n' "$HOME/.local/bin" ;;
  esac
}

task_omarchy_control() {
  step 'Omarchy Control'
  local need_install=false help_text
  if ! have_cmd omarchy-control; then
    need_install=true
  else
    # Capture first: with pipefail, `cmd --help | grep -q` can fail via SIGPIPE
    # when grep exits early on a match.
    help_text=$(omarchy-control --help 2>/dev/null || true)
    if ! grep -q 'integrate menu' <<<"$help_text"; then
      need_install=true
    fi
  fi

  if ! $need_install; then
    ok "omarchy-control $(omarchy-control --version 2>/dev/null | awk '{print $2}') already installed"
  else
    local url='https://raw.githubusercontent.com/last-refuge/omarchy-control/main/install.sh'
    local installer="$tmpdir/omarchy-control-install.sh"
    if $dry_run; then
      printf '  [dry-run] download %s and run with --yes\n' "$url"
    else
      command -v curl >/dev/null 2>&1 || die 'curl is required to install Omarchy Control.'
      curl -fsSL --proto '=https' --proto-redir '=https' \
        -o "$installer" "$url" || die 'could not download the Omarchy Control installer.'
      priv_run "$bash_path" "$installer" --yes
    fi
  fi

  local menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  if [[ -f $menu ]] && grep -q '"omarchy-control"' "$menu"; then
    ok 'already integrated in the Omarchy menu'
  else
    run omarchy-control integrate menu
  fi
}

task_tailscale() {
  step 'Tailscale'
  if have_pkg tailscale; then
    ok "tailscale already installed ($(pkg_status tailscale))"
  else
    priv_run "$omarchy_bin" pkg add tailscale
  fi

  if [[ -n $systemctl_path ]]; then
    if [[ $("$systemctl_path" is-enabled tailscaled.service 2>/dev/null || true) == enabled ]]; then
      ok 'tailscaled.service already enabled'
    else
      priv_run "$systemctl_path" enable tailscaled.service
    fi
    if "$systemctl_path" is-active --quiet tailscaled.service; then
      ok 'tailscaled.service is running'
    else
      priv_run "$systemctl_path" start tailscaled.service
    fi
  fi
  ok 'authenticate this node with: tailscale up'
}

task_rufust() {
  step 'Rufust (GitHub release)'
  have_cmd curl || die 'curl is required for the Rufust release check.'
  have_cmd jq   || die 'jq is required for the Rufust release check.'
  have_cmd vercmp || die 'vercmp is required for the Rufust version check.'

  local api='https://api.github.com/repos/NitroDiesel/rufust/releases/latest'
  local json="$tmpdir/rufust-release.json"
  if ! curl -fsSL --connect-timeout 15 --max-time 60 -o "$json" "$api"; then
    printf '  warning: could not query GitHub releases; skipping Rufust.\n'
    return 0
  fi

  local tag asset asset_ver installed_ver cmp base
  tag=$(jq -r '.tag_name // empty' "$json")
  asset=$(jq -r --arg arch "$(uname -m)" \
    '.assets[].name | select(test("^rufust-[0-9][0-9.]*-[0-9]+-" + $arch + "\\.pkg\\.tar\\.zst$"))' \
    "$json" | head -n 1)
  if [[ -z $tag || -z $asset ]]; then
    ok "no Arch Linux release asset for $(uname -m); skipped"
    return 0
  fi

  asset_ver=${asset#rufust-}
  asset_ver=${asset_ver%-*}
  if have_pkg rufust; then
    installed_ver=$(pacman -Q rufust | awk '{print $2}')
    cmp=$(vercmp "$installed_ver" "$asset_ver")
    if (( cmp >= 0 )); then
      ok "rufust $installed_ver is current (release $asset_ver)"
      return 0
    fi
  fi

  base="https://github.com/NitroDiesel/rufust/releases/download/$tag"
  if $dry_run; then
    printf '  [dry-run] would download, verify and install %s\n' "$asset"
    return 0
  fi

  curl -fsSL -o "$tmpdir/$asset" "$base/$asset" || die "could not download $asset."
  curl -fsSL -o "$tmpdir/SHA256SUMS" "$base/SHA256SUMS" \
    || die 'could not download SHA256SUMS.'
  (cd "$tmpdir" && grep -F " $asset" SHA256SUMS | sha256sum -c --status -) \
    || die 'Rufust checksum did not match; nothing was installed.'
  priv_run "$pacman_path" -U --needed --noconfirm "$tmpdir/$asset"
}

task_openshell() {
  step 'OpenShell'
  if have_cmd openshell; then
    ok "openshell already available at $(command -v openshell)"
    return 0
  fi
  need_yay
  # NVIDIA's install.sh only handles deb/rpm/snap; the AUR package tracks the
  # same releases and is the correct Arch equivalent.
  aur_run yay -S --needed --noconfirm openshell-bin
  if ! $dry_run; then
    have_cmd openshell || die 'openshell CLI not found after installation.'
  fi
}

task_tmog() {
  step 'TMOG task manager'
  need_yay
  # Precompiled upstream AppImage packaged for Arch; upgrades the older
  # omarchy-repo version if present. Optional no-root sensor grants are NOT
  # applied (see README.md).
  aur_run yay -S --needed --noconfirm tmog-bin
}

# ---------------------------------------------------------------------------
# Status summary, confirmation and execution
# ---------------------------------------------------------------------------
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu_file ]] && grep -q '"omarchy-control"' "$menu_file"; then menu_state=yes; else menu_state=no; fi
effective_disktree=$(command -v disktree || true)
if [[ -n $effective_disktree ]] \
   && grep -aq 'LIBGL_ALWAYS_SOFTWARE=1' "$effective_disktree"; then gl_state=configured; else gl_state=missing; fi
if [[ -n $systemctl_path ]] && "$systemctl_path" is-enabled --quiet tailscaled.service 2>/dev/null; then ts_state=enabled; else ts_state=disabled; fi

printf 'Omarchy server post-install %s: install/configure toolset\n' "$version"
printf 'Privilege helper: %s\n' "${priv[0]:-root (no elevation needed)}"
printf '\nCurrent status:\n'
printf '  flea:              %s\n' "$(pkg_status flea)"
printf '  disktree-bin:      %s\n' "$(pkg_status disktree-bin)"
printf '  disktree GL:       %s\n' "$gl_state"
printf '  omarchy-control:   %s (menu: %s)\n' "$(pkg_status omarchy-control)" "$menu_state"
printf '  tailscale:         %s (tailscaled: %s)\n' "$(pkg_status tailscale)" "$ts_state"
printf '  rufust:            %s\n' "$(pkg_status rufust)"
printf '  openshell:         %s\n' "$(command -v openshell || printf 'missing')"
printf '  tmog-bin:          %s\n' "$(pkg_status tmog-bin)"

tasks=(flea disktree omarchy_control tailscale rufust openshell tmog)

if $dry_run; then
  printf '\nDry run - showing actions, no changes made.\n'
  for t in "${tasks[@]}"; do "task_$t" || true; done
  exit 0
fi

if ! $assume_yes; then
  [[ -t 0 ]] || die 'non-interactive shell: use --yes to confirm or --dry-run to preview.'
  printf '\nInstall/configure the missing items? [y/N] '
  IFS= read -r reply || die 'no answer received; aborting without changes.'
  case $reply in
    y|Y|yes|YES|Yes) ;;
    *) printf 'Aborted; no changes made.\n'; exit 0 ;;
  esac
fi

failed=()
for t in "${tasks[@]}"; do
  if ! "task_$t"; then failed+=("$t"); fi
done

if ((${#failed[@]})); then
  printf '\nFinished with failures: %s\n' "${failed[*]}"
  printf 'Re-run after resolving the errors above.\n'
  exit 1
fi

printf '\nDone. Re-run with --dry-run at any time to verify.\n'
