*Version française : [README.md](README.md)*

# proxmox-claude-lxc

A script for **Proxmox VE** that creates, in one command, a Debian LXC
container ready for **[Claude Code](https://claude.com/claude-code)**: system
up to date, development tools, a user account with sudo, Claude Code
installed. Handy for one container per project, where Claude can work without
touching your other machines.

## Usage

On the Proxmox node, as **root** (node shell in the web UI, or SSH):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/f4ioz/proxmox-claude-lxc/main/proxmox-claude-lxc.sh)"
```

The script asks a few questions (Enter keeps the suggested value), shows a
summary, then creates and sets up the container. When it is done:

```bash
ssh dev@<container-ip>         # or: pct enter <ID>, then su - dev
claude                         # first launch: sign in through the link shown
```

You sign in to Claude on the first `claude` launch (Claude Pro/Max account, or
an Anthropic API key): the script never handles any Anthropic credential.

## What the script does

1. Checks that it runs as root on a Proxmox node (`pct`, `pveam`, `pvesm`).
2. Suggests the cluster's **next free ID** (VMs and containers alike).
3. Downloads the newest **Debian 13** template (Debian 12 as a fallback).
4. Creates an **unprivileged** container (`nesting=1,keyctl=1`, start at boot,
   `claude` tag).
5. Updates the system and installs: git, curl, sudo, openssh-server,
   build-essential, python3 (+ venv, pip), ripgrep, jq, tmux, htop, nano,
   unzip, avahi (`<name>.local` address).
6. Creates the user (`dev` by default): sudo group, **passwordless sudo** if
   you want it (convenient for Claude Code), SSH key, `~/projects` folder, git
   identity.
7. Installs **Claude Code** for that user with the official installer
   (`https://claude.ai/install.sh` → `~/.local/bin/claude`, auto-updating) and
   checks that it answers.

| Setting | Default |
|---|---|
| Name | `claude-dev` |
| Disk / vCPU / RAM / swap | 16 GB / 2 / 4096 MB / 1024 MB |
| Storage | `local-lvm` (otherwise the first active storage) |
| Network | `vmbr0`, DHCP (or a static CIDR IP + gateway) |
| User | `dev`, generated password (shown at the end) unless you type one |

The container's **root** account has no password: it is **locked** (nobody
can log in to it with a password), which is safer than a root password. Get
in with `pct enter <ID>` from the node, or SSH with the key you provided.

## No questions (several containers)

`--yes` takes the defaults, overridden by the `CLX_*` variables:

```bash
curl -fsSL -o proxmox-claude-lxc.sh \
  https://raw.githubusercontent.com/f4ioz/proxmox-claude-lxc/main/proxmox-claude-lxc.sh

CLX_HOSTNAME=claude-satwatch CLX_SSH_KEY=~/.ssh/id_ed25519.pub \
  bash proxmox-claude-lxc.sh --yes
```

| Variable | Purpose |
|---|---|
| `CLX_CTID` | container ID (next free one) |
| `CLX_HOSTNAME` | container name |
| `CLX_DISK`, `CLX_CORES`, `CLX_RAM`, `CLX_SWAP` | resources (GB, vCPU, MB, MB) |
| `CLX_STORAGE`, `CLX_BRIDGE` | storage, network bridge |
| `CLX_IP`, `CLX_GW` | `dhcp` or a CIDR IP, gateway |
| `CLX_USER`, `CLX_PASSWORD` | user, password (generated if empty) |
| `CLX_SSH_KEY` | public key, or path to a `.pub` file |
| `CLX_SUDO_NOPASSWD` | `1` (default) = passwordless sudo, `0` = with password |
| `CLX_GIT_NAME`, `CLX_GIT_EMAIL` | the user's git identity |
| `CLX_LANG` | `fr` or `en` (like `--lang`) |
| `CLX_APT_TIMEOUT` | time limit of each apt step, in seconds (1800) |

`bash proxmox-claude-lxc.sh --help` sums all of this up.

## Security

- **Unprivileged** container: root inside is not root on the host.
- Root: password locked (`passwd -l root`) and SSH by key only
  (`PermitRootLogin prohibit-password`), enforced by the script whatever the
  template does.
- **SSH key given → SSH by key only**: password logins over SSH are refused
  (`PasswordAuthentication no`), once the key is in place. The user's
  password is then for sudo and the console (`pct enter`). Without a key,
  password logins stay possible.
- The password goes through standard input (`chpasswd`), never on a command
  line.
- Passwordless sudo is a convenience for an isolated development container:
  answer "n" (or `CLX_SUDO_NOPASSWD=0`) if the container is shared or exposed.
- Claude Code runs commands in the container: keep your projects there, not
  your production secrets.

## Deleting a container

```bash
pct stop <ID> && pct destroy <ID>
```

## Development

The tests simulate a Proxmox node (fake `pct`, `pveam`, `pvesm`, `pvesh`,
`qm` commands): no container is created.

```bash
pip install pytest shellcheck-py
pytest
```

## Licence

MIT — see [LICENSE](LICENSE). Claude Code is an Anthropic product under its
own terms of use; this script is not an official Anthropic project.
