"""proxmox-claude-lxc.sh, run against a simulated Proxmox node.

pct, pveam, pvesm, pvesh and qm are fake commands that log their calls;
whatever pct exec receives on stdin (password, SSH key) goes to a separate
log, so the tests can check that secrets never appear on a command line.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "proxmox-claude-lxc.sh"
KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@pc"

FAKE_PCT = r"""#!/usr/bin/env bash
echo "pct $*" >> "$CALLS"
case "$1" in
  status) [[ $2 == 100 ]] && exit 0; exit 1 ;;          # container 100 already exists
  exec)
    if [[ "$*" == *chpasswd* || "$*" == *authorized_keys* ]]; then
      echo "stdin[$*]: $(cat)" >> "$STDIN_LOG"
    fi
    if [[ "$*" == *"ip -4"* ]]; then echo 192.168.1.50; fi
    if [[ "$*" == *"claude --version"* ]]; then
      [[ -n ${FAIL:-} ]] && exit 1
      echo "2.1.282 (Claude Code)"
    fi ;;
esac
exit 0
"""
FAKE_QM = r"""#!/usr/bin/env bash
[[ $1 == status && $2 == 101 ]]                        # VM 101 already exists
"""
FAKE_PVESH = r"""#!/usr/bin/env bash
# /cluster/nextid: next free ID (VMs and containers); --vmid N fails if N is taken.
if [[ "$*" == *--vmid* ]]; then
  v="${@: -1}"
  if [[ $v == 100 || $v == 101 ]]; then echo "VM $v already exists" >&2; exit 2; fi
  echo "$v"; exit 0
fi
echo 102
"""
FAKE_PVEAM = r"""#!/usr/bin/env bash
echo "pveam $*" >> "$CALLS"
if [[ $1 == available ]]; then
  echo "system          debian-12-standard_12.7-1_amd64.tar.zst"
  echo "system          debian-13-standard_13.1-2_amd64.tar.zst"
fi
exit 0
"""
FAKE_PVESM = r"""#!/usr/bin/env bash
echo "Name Type Status Total Used Available %"
case "$*" in
  *rootdir*) echo "local-zfs zfspool active 1 1 1 1%" ;;
  *vztmpl*) echo "local dir active 1 1 1 1%" ;;
esac
"""


@pytest.fixture
def proxmox(tmp_path, request):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fakes = {"pct": FAKE_PCT, "qm": FAKE_QM, "pvesh": FAKE_PVESH, "pveam": FAKE_PVEAM, "pvesm": FAKE_PVESM}
    if getattr(request, "param", "") == "no-pvesh":
        del fakes["pvesh"]
    for name, body in fakes.items():
        (bin_dir / name).write_text(body)
        (bin_dir / name).chmod(0o755)
    return {"PATH": f"{bin_dir}:{os.environ['PATH']}", "CALLS": str(tmp_path / "calls"),
            "STDIN_LOG": str(tmp_path / "stdin"), "TERM": "dumb", "CLX_LANG": "en"}


def run(env: dict[str, str], answers: list[str] | None = None, *args: str, **extra: str):
    # Sourced (main() does not start by itself): check_root disabled, we are not root.
    script = f'source "{SCRIPT}"\ncheck_root() {{ :; }}\nmain "$@"'
    clean = {k: v for k, v in os.environ.items() if not k.startswith("CLX_")}
    return subprocess.run(["bash", "-c", script, "bash", *args],
                          input="\n".join(answers or []) + "\n", capture_output=True, text=True,
                          timeout=60, env={**clean, **env, **extra})


def log(tmp_path: Path, name: str = "calls") -> str:
    f = tmp_path / name
    return f.read_text() if f.exists() else ""


def create_line(tmp_path: Path) -> str:
    return next(line for line in log(tmp_path).splitlines() if line.startswith("pct create"))


# Container questions: ID 100 (container) and 101 (VM) taken → asked again,
# then name, disk, vCPU, RAM, swap, storage, bridge, IP with their defaults.
CT_ANSWERS = ["100", "101", "", "", "", "", "", "", "", "", ""]


def test_interactive_install_with_defaults(tmp_path, proxmox) -> None:
    answers = [*CT_ANSWERS, "", "", "", KEY, "Olivier F4IOZ", "", ""]   # user, password, sudo, key, git…
    r = run(proxmox, answers)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Invalid ID, or already used" in r.stdout
    calls = log(tmp_path)
    assert "pveam download local debian-13-standard_13.1-2_amd64.tar.zst" in calls   # the newest Debian
    create = create_line(tmp_path)
    assert create.startswith("pct create 102 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst")
    for opt in ("--hostname claude-dev", "--rootfs local-zfs:16", "--memory 4096", "--cores 2",
                "--swap 1024", "--features nesting=1,keyctl=1", "--unprivileged 1",
                "--net0 name=eth0,bridge=vmbr0,ip=dhcp", "--ssh-public-keys", "--tags claude"):
        assert opt in create, opt
    assert "--password" not in create                        # root: pct enter or SSH key only
    assert "passwd -l root" in calls                          # locked whatever the template does
    assert "PermitRootLogin prohibit-password" in calls
    assert calls.index("passwd -l root") < calls.index("useradd")
    # Key given: SSH refuses passwords, set only once the key is in place.
    assert "PasswordAuthentication no" in calls and "KbdInteractiveAuthentication no" in calls
    assert calls.index("authorized_keys") < calls.index("PasswordAuthentication no")
    assert "SSH: key only, password login refused" in r.stdout
    assert "ripgrep" in calls and "build-essential" in calls and "openssh-server" in calls
    assert "useradd -m -s /bin/bash -G sudo dev" in calls
    assert "NOPASSWD:ALL" in calls
    assert "runuser -l dev -c curl -fsSL https://claude.ai/install.sh | bash" in calls
    assert "git config --global user.name Olivier\\ F4IOZ" in calls
    assert "user.email" not in calls
    # Generated password: shown once at the end, sent through stdin only.
    pw = next(line.split(":", 1)[1].split()[0] for line in r.stdout.splitlines() if "Password    :" in line)
    assert len(pw) == 16
    assert pw not in calls
    stdin = log(tmp_path, "stdin")
    assert f"dev:{pw}" in stdin and KEY in stdin
    for expected in ("Claude Code installed: 2.1.282", "ssh dev@192.168.1.50", "pct enter 102, then su - dev",
                     "pct stop 102 && pct destroy 102"):
        assert expected in r.stdout, expected


@pytest.mark.parametrize("proxmox", ["with-pvesh", "no-pvesh"], indirect=True)
def test_default_id_skips_existing_vm_and_container(tmp_path, proxmox) -> None:
    r = run(proxmox, [""] * 20)
    assert r.returncode == 0, r.stdout + r.stderr
    assert create_line(tmp_path).startswith("pct create 102 ")


def test_yes_mode_uses_variables_and_asks_nothing(tmp_path, proxmox) -> None:
    keyfile = tmp_path / "id.pub"
    keyfile.write_text(KEY + "\n")
    r = run(proxmox, None, "--yes", CLX_HOSTNAME="Claude-Sat", CLX_PASSWORD="S3cret-pw",
            CLX_SSH_KEY=str(keyfile), CLX_SUDO_NOPASSWD="0", CLX_IP="192.168.1.60/24",
            CLX_GW="192.168.1.1", CLX_RAM="8192", CLX_USER="olivier", CLX_GIT_EMAIL="me@example.org")
    assert r.returncode == 0, r.stdout + r.stderr
    create = create_line(tmp_path)
    assert "--hostname claude-sat" in create and "--memory 8192" in create
    assert "ip=192.168.1.60/24,gw=192.168.1.1" in create
    calls = log(tmp_path)
    assert "useradd -m -s /bin/bash -G sudo olivier" in calls
    assert "NOPASSWD" not in calls                            # sudo keeps asking for the password
    assert "git config --global user.email me@example.org" in calls
    assert "S3cret-pw" not in calls and "S3cret-pw" not in r.stdout
    assert "olivier:S3cret-pw" in log(tmp_path, "stdin") and KEY in log(tmp_path, "stdin")


def test_yes_mode_rejects_invalid_values(tmp_path, proxmox) -> None:
    for bad in ({"CLX_USER": "root"}, {"CLX_HOSTNAME": "bad_name"}, {"CLX_IP": "10.0.0.5"},
                {"CLX_CTID": "100"}, {"CLX_RAM": "lots"}):
        r = run(proxmox, None, "--yes", **bad)
        assert r.returncode != 0, bad
    assert "pct create" not in log(tmp_path)


def test_missing_ssh_key_file_stops_before_anything(tmp_path, proxmox) -> None:
    r = run(proxmox, None, "--yes", CLX_SSH_KEY=str(tmp_path / "nope.pub"))
    assert r.returncode != 0 and "SSH key file not found" in r.stderr
    assert "pct create" not in log(tmp_path)


def test_without_key_ssh_keeps_passwords(tmp_path, proxmox) -> None:
    r = run(proxmox, None, "--yes")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "PasswordAuthentication" not in log(tmp_path)     # otherwise no way in over SSH
    assert "SSH: password login (no key given)" in r.stdout


def test_cancel_creates_nothing(tmp_path, proxmox) -> None:
    r = run(proxmox, [*CT_ANSWERS, "", "", "", "", "", "", "n"])
    assert r.returncode == 0 and "nothing has been created" in r.stdout
    assert "pct create" not in log(tmp_path)


def test_typed_password_must_be_confirmed(tmp_path, proxmox) -> None:
    answers = [*CT_ANSWERS, "", "pw-one", "pw-two", "pw-one", "pw-one", "", "", "", "", ""]
    r = run(proxmox, answers)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Passwords differ." in r.stdout
    assert "dev:pw-one" in log(tmp_path, "stdin")
    assert "Password    :" not in r.stdout                   # typed, so not shown


def test_claude_install_failure_keeps_container_and_explains(tmp_path, proxmox) -> None:
    r = run(proxmox, None, "--yes", FAIL="1")
    assert r.returncode == 1
    assert "container 102 is kept" in r.stderr
    assert "runuser -l dev -c 'curl -fsSL https://claude.ai/install.sh | bash'" in r.stdout
    assert "destroy" not in log(tmp_path)


def test_french_messages(tmp_path, proxmox) -> None:
    env = {k: v for k, v in proxmox.items() if k != "CLX_LANG"}
    r = run(env, ["1", *CT_ANSWERS, "", "", "", "", "", "", ""])
    assert r.returncode == 0, r.stdout + r.stderr
    assert "1) Français" in r.stdout and "2) English" in r.stdout
    for expected in ("Récapitulatif", "CT 102 créée.", "Utilisateur dev prêt.", "Claude Code est prêt dans la CT 102",
                     "Mot de passe :", "Supprimer   : pct stop 102"):
        assert expected in r.stdout, expected
    assert "Summary" not in r.stdout


def test_yes_mode_without_language_speaks_english(tmp_path, proxmox) -> None:
    env = {k: v for k, v in proxmox.items() if k != "CLX_LANG"}
    r = run(env, None, "--yes")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Langue / Language" not in r.stdout and "Summary" in r.stdout


def test_help_and_unknown_option(proxmox) -> None:
    r = run(proxmox, None, "--help")
    assert r.returncode == 0 and "CLX_HOSTNAME" in r.stdout and "--yes" in r.stdout
    r = run(proxmox, None, "--bogus")
    assert r.returncode == 2 and "Unknown option" in r.stderr


def test_script_is_valid_bash() -> None:
    r = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


@pytest.mark.skipif(not shutil.which("shellcheck"), reason="shellcheck not installed")
def test_shellcheck() -> None:
    r = subprocess.run(["shellcheck", str(SCRIPT)], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout
