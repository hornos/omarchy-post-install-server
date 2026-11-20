# Omarchy post-install toolkit

A small toolkit of idempotent shell scripts for preparing an Arch-based
**Omarchy** install for server use. The main scripts check current state before
acting, support `--dry-run` and `--yes`, and are safe to re-run.

| Script | Purpose |
|--------|---------|
| [`install.sh`](install.sh) | Bootstrap that installs the toolkit from GitHub with a one-liner. |
| [`server-install.sh`](server-install.sh) | Install and configure the server toolset: Flea, Disktree, Omarchy Control, Tailscale, Rufust, OpenShell and TMOG. |
| [`server-uninstall-packages.sh`](server-uninstall-packages.sh) | Remove desktop applications such as LibreOffice, GIMP, VLC and Discord. |

## Install from GitHub

Install both scripts into `~/.local/bin` with a single command:

```sh
curl -fsSL https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main/install.sh | bash
```

The bootstrap downloads the scripts over HTTPS, checks their bash syntax, and
installs them executable. It does **not** run the server installer by default.
Preview first, then apply:

```sh
~/.local/bin/server-install.sh --dry-run
~/.local/bin/server-install.sh
```

To install and immediately run the installer in one step, pass `--run`. Extra
arguments are forwarded to `server-install.sh`:

```sh
curl -fsSL https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main/install.sh | bash -s -- --run --dry-run
curl -fsSL https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main/install.sh | bash -s -- --run --yes
```

Change the destination with `OMARCHY_POST_INSTALL_DIR` (or `--dir` when running
a local copy of `install.sh`):

```sh
curl -fsSL https://raw.githubusercontent.com/hornos/omarchy-post-install-server/main/install.sh | OMARCHY_POST_INSTALL_DIR=~/bin bash
```

## Requirements

- An Arch-based Omarchy installation with `bash`, `pacman` and the `omarchy` CLI.
- `pkexec` or `sudo` for privileged operations, or run the script as root.
- `yay` for the AUR packages (`openshell-bin`, `tmog-bin`).
- `curl` for the one-line installer and the Rufust release check; `jq` for the
  Rufust release check. `vercmp` comes with pacman.
- Network access for GitHub releases, the AUR and the Omarchy Control installer.

## Usage

```sh
chmod +x server-install.sh server-uninstall-packages.sh

# Install / configure the server toolset
./server-install.sh                       # show status, confirm, then apply
./server-install.sh --dry-run             # preview actions; changes nothing
./server-install.sh --yes                 # unattended run (no prompt)

# Remove desktop-only packages
./server-uninstall-packages.sh            # list targets, confirm, then remove
./server-uninstall-packages.sh --dry-run  # preview only; changes nothing
./server-uninstall-packages.sh --yes      # unattended run (no prompt)
```

Privileged calls use `pkexec` so the password prompt appears as a polkit
dialog. `sudo` is used as a fallback, and no elevation happens at all when a
script is run as root. `-h` / `--help` prints all options. AUR installs are
always run as the invoking desktop user, never as root.

### Options

| Option | Effect |
|--------|--------|
| `-n`, `--dry-run` | Print the current state and the commands that would run. No changes are made. |
| `-y`, `--yes` | Skip the confirmation prompt for unattended runs. |
| `-v`, `--version` | Print the script version and exit. |
| `-h`, `--help` | Show help and exit. |

## What the installer sets up

| Project | Short description | Reference |
|---------|-------------------|-----------|
| **Flea** | Fast, keyboard-first GUI file manager for Omarchy with tabs, two-pane view, Quick Look, tags, search and network shares. Installed with `omarchy pkg add flea`; `flea --default` is applied only when needed. | [thisisgm/flea](https://github.com/thisisgm/flea) |
| **Disktree** | Visual disk-space treemap for finding and safely removing what fills a drive. Installed from `disktree-bin`, with a wrapper that forces software OpenGL on older Radeon/GL drivers. | [tobi/disktree](https://github.com/tobi/disktree) · [AUR package](https://aur.archlinux.org/packages/disktree-bin) |
| **Omarchy Control** | Control center for Omarchy settings such as audio, Bluetooth, services, appearance, displays, input and power. The official installer is downloaded to a temp file, then `omarchy-control integrate menu` adds the launcher entry. | [last-refuge/omarchy-control](https://github.com/last-refuge/omarchy-control) |
| **Tailscale** | WireGuard-based mesh VPN. The package is installed and `tailscaled.service` is enabled and started; authentication is left to you via `tailscale up`. | [tailscale.com](https://tailscale.com) · [github.com/tailscale/tailscale](https://github.com/tailscale/tailscale) |
| **Rufust** | Independent Linux and Windows port of Rufus for creating bootable USB drives with a native UI and a safety-first privileged helper. The latest release package is checksum-verified before installation. | [NitroDiesel/rufust](https://github.com/NitroDiesel/rufust) |
| **OpenShell** | NVIDIA's safe, private runtime for autonomous AI agents. Installed from the AUR package `openshell-bin` because NVIDIA's own installer ships only deb/rpm packages. | [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) · [docs](https://docs.nvidia.com/openshell/latest/) |
| **TMOG** | Native system monitor for macOS, Windows and Linux. Installed from the AUR package `tmog-bin`, upgrading an older Omarchy-repo version if present. | [tmog.org](https://www.tmog.org) |

### Install notes

- **Flea software rendering:** an existing D-Bus file-manager service pointing
  at `~/.local/libexec/flea/flea-filemanager1` is left alone so custom
  software-Vulkan shims are not overwritten.
- **Disktree wrapper:** `~/.local/bin` precedes `/usr/local/bin` on Omarchy's
  PATH. A local `disktree` that is an exact copy of `/usr/bin/disktree` is
  replaced with the software-GL wrapper. An unrelated local executable is
  never overwritten; the script warns and skips it.
- **OpenShell runtime:** the CLI does not install Docker, Podman or a VM
  runtime, which is needed before a sandbox can actually run.
- **TMOG power readings:** optional no-root `powercap` grants from
  [tmog.org/linux.html](https://www.tmog.org/linux.html) are not applied. The
  app runs unprivileged, so the Energy row may read "Power access restricted".
- **Rufust offline:** if the GitHub release query fails, Rufust is skipped
  with a warning instead of aborting the whole run.

## What the cleanup removes

`libreoffice-fresh`, `libreoffice-still`, `obsidian`, `typora`, `marktext`,
`zathura`, `zathura-pdf-mupdf`, `pinta`, `gimp`, `inkscape`, `kdenlive`,
`obs-studio`, `spotify`, `vlc`, `loupe`, `discord`, `telegram-desktop`,
`zoom`, `basecamp`, `xournal++`.

To change the set, edit the `REQUESTED` array near the top of
`server-uninstall-packages.sh`; nothing else needs updating.

### Cleanup edge cases

- `xournal++` is resolved to the real Arch package name `xournalpp`.
- `basecamp` is a web-app launcher on Omarchy, not an installed package, so it
  is reported as "not installed" and its launcher is left alone.
- Installed LibreOffice language packs are added automatically because they
  hard-depend on the base package.
- Web-app `.desktop` launchers in `~/.local/share/applications` are not
  removed; only packages are.

## Safety model

### Installer

- Checks first: anything already installed or configured is reported as
  "already OK" and left untouched.
- Confirms by default and refuses to guess on non-interactive input.
- Avoids blind `curl | bash`: the Omarchy Control installer is downloaded over
  HTTPS to a temporary file before execution.
- Verifies the Rufust release package against upstream `SHA256SUMS` before
  `pacman -U`; a mismatch installs nothing.
- Collects per-task failures so one problem does not cancel unrelated tasks.

### Uninstaller

- Only installed packages are passed to pacman; missing ones are skipped.
- Uses `pacman -Rs` without forced flags, so a package still required by
  another one aborts the transaction instead of breaking the system.
- Keeps modified config files as `.pacsave` by omitting `-n`.
- Finds AUR packages through pacman's local database; no AUR helper is needed.
- Performs all removals in one pacman transaction.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, or nothing needed to be done |
| 1 | Preflight failure, package-manager error, or one or more install tasks failed |
| 2 | Invalid option |

## Repository layout

```text
.
├── .gitignore
├── LICENSE
├── README.md
├── install.sh                     # GitHub one-line bootstrap
├── server-install.sh              # installs/configures the toolset
└── server-uninstall-packages.sh   # removes desktop packages
```

## Development

```sh
git clone git@github.com:hornos/omarchy-post-install-server.git
cd omarchy-post-install-server
./install.sh --dir "$HOME/.local/bin"

# Or run a checkout directly
./server-install.sh --dry-run
```

## License

[MIT](LICENSE) © 2026 Omarchy post-install contributors.
