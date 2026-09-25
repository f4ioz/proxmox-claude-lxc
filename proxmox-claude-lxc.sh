#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# proxmox-claude-lxc — a Debian LXC container on Proxmox VE, ready for
# Claude Code (https://claude.com/claude-code)
#
# Creates an unprivileged Debian 13 container (Debian 12 as a fallback),
# updates it, installs the usual development tools, creates a user account
# (sudo) and installs Claude Code for that user. Log in afterwards and run
# `claude`: the first launch asks you to sign in.
#
# Usage: on the Proxmox node, as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/f4ioz/proxmox-claude-lxc/main/proxmox-claude-lxc.sh)"
#
# Options: --yes (no questions: defaults + CLX_* variables), --lang fr|en,
# --help. Variables: see usage() below.
# ------------------------------------------------------------------------------

# BRIDGE, CORES, DISK… are assigned by ask() through printf -v.
# shellcheck disable=SC2153
set -euo pipefail

VERSION="1.0.1"
REPO_URL="https://github.com/f4ioz/proxmox-claude-lxc"
CLAUDE_INSTALL_URL="${CLX_CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"

# ─── Language (English source, French translation) ────────────────────────────
# Messages are written in English; MSG holds their French translation.
# Choice: --lang / CLX_LANG, otherwise the first question. Values: {1}, {2}…
UI_LANG="${CLX_LANG:-}"
declare -A MSG=()

t() {  # t "English text" [value of {1}, of {2}…]
  # Leading alignment spaces are not part of the key.
  local raw="$1" lead m i=1 a
  shift
  lead="${raw%%[! ]*}"
  m="${raw#"$lead"}"
  m="${MSG[$m]:-$m}"
  for a in "$@"; do m="${m//\{$i\}/$a}"; i=$((i + 1)); done
  printf '%s' "$lead$m"
}

load_fr() {
  MSG["(Enter = suggested value)"]="(Entrée = valeur proposée)"
  MSG["Cancelled: nothing has been created."]="Annulé : rien n'a été créé."
  MSG["Claude Code installed: {1}"]="Claude Code installé : {1}"
  MSG["Claude Code install failed (container {1} is kept)."]="L'installation de Claude Code a échoué (la CT {1} est conservée)."
  MSG["Confirm"]="Confirmer"
  MSG["Container"]="Conteneur"
  MSG["Container ID"]="ID de la CT"
  MSG["Container name"]="Nom de la CT"
  MSG["Container storage"]="Stockage de la CT"
  MSG["Container {1} created."]="CT {1} créée."
  MSG["Container started."]="CT démarrée."
  MSG["Continue?"]="Continuer ?"
  MSG["Creating container {1}…"]="Création de la CT {1}…"
  MSG["Creating user {1}…"]="Création de l'utilisateur {1}…"
  MSG["Disk (GB)"]="Disque (Go)"
  MSG["Downloading template {1}…"]="Téléchargement du template {1}…"
  MSG["Gateway (e.g. 192.168.1.1)"]="Passerelle (ex. 192.168.1.1)"
  MSG["Git email (optional)"]="E-mail Git (facultatif)"
  MSG["Git name (optional)"]="Nom Git (facultatif)"
  MSG["Installing Claude Code for {1}…"]="Installation de Claude Code pour {1}…"
  MSG["Invalid ID, or already used (VM or container)."]="ID invalide ou déjà utilisé (VM ou CT)."
  MSG["Invalid address."]="Adresse invalide."
  MSG["Invalid name: letters, digits and hyphens."]="Nom invalide : lettres, chiffres et tirets."
  MSG["Invalid user name: lowercase letters, digits, - and _ (not root)."]="Nom d'utilisateur invalide : minuscules, chiffres, - et _ (pas root)."
  MSG["IP (dhcp or CIDR, e.g. 192.168.1.50/24)"]="IP (dhcp ou CIDR, ex. 192.168.1.50/24)"
  MSG["Looking for a Debian template…"]="Recherche d'un template Debian…"
  MSG["Network OK."]="Réseau OK."
  MSG["Network bridge"]="Bridge réseau"
  MSG["No Internet access (DNS) in the container: check bridge, IP and gateway."]="Pas d'accès à Internet (DNS) dans la CT : vérifier bridge, IP et passerelle."
  MSG["No active storage accepts templates (vztmpl)."]="Aucun stockage actif n'accepte les templates (vztmpl)."
  MSG["No debian-13/12-standard template in pveam."]="Aucun template debian-13/12-standard dans pveam."
  MSG["Packages installed."]="Paquets installés."
  MSG["Packages: {1}…"]="Paquets : {1}…"
  MSG["Password of {1} (empty = generated)"]="Mot de passe de {1} (vide = généré)"
  MSG["Passwords differ."]="Mots de passe différents."
  MSG["Public SSH key (line ssh-ed25519/ssh-rsa… or file path), Enter to skip"]="Clé SSH publique (ligne ssh-ed25519/ssh-rsa… ou chemin d'un fichier), Entrée pour ignorer"
  MSG["RAM (MB)"]="RAM (Mo)"
  MSG["Root: password locked, SSH by key only."]="Root : mot de passe verrouillé, SSH par clé uniquement."
  MSG["Run this as root on the Proxmox node."]="À lancer en root sur le nœud Proxmox."
  MSG["SSH key file not found: {1}"]="Fichier de clé SSH introuvable : {1}"
  MSG["Starting…"]="Démarrage…"
  MSG["Summary"]="Récapitulatif"
  MSG["Swap (MB)"]="Swap (Mo)"
  MSG["System up to date."]="Système à jour."
  MSG["Template: {1}"]="Template : {1}"
  MSG["Updating the system (apt)…"]="Mise à jour du système (apt)…"
  MSG["User"]="Utilisateur"
  MSG["User name"]="Nom d'utilisateur"
  MSG["User {1} ready."]="Utilisateur {1} prêt."
  MSG["Waiting for the network in the container…"]="Attente du réseau dans la CT…"
  MSG["passwordless sudo"]="sudo sans mot de passe"
  MSG["sudo with password"]="sudo avec mot de passe"
  MSG["Passwordless sudo for {1}? (convenient for Claude Code)"]="sudo sans mot de passe pour {1} ? (pratique pour Claude Code)"
  MSG["vCPU"]="vCPU"
  MSG["{1} must be a number: {2}"]="{1} doit être un nombre : {2}"
  MSG["{1} not found: not on a Proxmox VE node?"]="{1} introuvable : pas sur un nœud Proxmox VE ?"
  MSG["CT {1} '{2}': disk {3} GB, {4} vCPU, RAM {5} MB, swap {6} MB"]="CT {1} '{2}' : disque {3} Go, {4} vCPU, RAM {5} Mo, swap {6} Mo"
  MSG["storage {1}, bridge {2}, IP {3}{4}"]="stockage {1}, bridge {2}, IP {3}{4}"
  MSG["user {1} ({2}), SSH key: {3}"]="utilisateur {1} ({2}), clé SSH : {3}"
  MSG["gateway"]="passerelle"
  MSG["yes"]="oui"
  MSG["no"]="non"
  MSG["Claude Code is ready in container {1}"]="Claude Code est prêt dans la CT {1}"
  MSG["Container   : {1} ({2})  IP {3}"]="CT          : {1} ({2})  IP {3}"
  MSG["User        : {1}"]="Utilisateur : {1}"
  MSG["Password    : {1}   (generated: write it down)"]="Mot de passe : {1}   (généré : notez-le)"
  MSG["Connect     : ssh {1}@{2}"]="Connexion   : ssh {1}@{2}"
  MSG["Console     : pct enter {1}, then su - {2}"]="Console     : pct enter {1}, puis su - {2}"
  MSG["Then run    : claude   (first launch: sign in through the link shown)"]="Puis lancer : claude   (1er lancement : connexion par le lien affiché)"
  MSG["Projects    : ~/projects"]="Projets     : ~/projects"
  MSG["Delete      : pct stop {1} && pct destroy {1}"]="Supprimer   : pct stop {1} && pct destroy {1}"
  MSG["Retry       : pct exec {1} -- runuser -l {2} -c 'curl -fsSL {3} | bash'"]="Relancer    : pct exec {1} -- runuser -l {2} -c 'curl -fsSL {3} | bash'"
}

ask_lang() {
  local choice
  case "$UI_LANG" in fr) load_fr; return 0 ;; en) return 0 ;; esac
  if [[ $ASSUME_YES == 1 ]]; then UI_LANG="en"; return 0; fi
  echo
  echo "    1) Français"
  echo "    2) English"
  read -r -p "  Langue / Language [1] : " choice || true
  case "${choice,,}" in 2|en|english|e) UI_LANG="en" ;; *) UI_LANG="fr"; load_fr ;; esac
}

# ─── Colors and output ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

msg_info() { echo -e "${CYAN}${BOLD}[..]${NC} $(t "$@")"; }
msg_ok()   { echo -e "${GREEN}${BOLD}[OK]${NC} $(t "$@")"; }
msg_warn() { echo -e "${YELLOW}${BOLD}[!!]${NC} $(t "$@")"; }
msg_err()  { echo -e "${RED}${BOLD}[KO]${NC} $(t "$@")" >&2; }
say()      { t "$@"; echo; }

header() {
  clear 2>/dev/null || true
  cat <<'EOF'
   ____ _                 _        _     __  ______
  / ___| | __ _ _   _  __| | ___  | |    \ \/ / ___|
 | |   | |/ _` | | | |/ _` |/ _ \ | |     \  / |
 | |___| | (_| | |_| | (_| |  __/ | |___  /  \ |___
  \____|_|\__,_|\__,_|\__,_|\___| |_____|/_/\_\____|

 proxmox-claude-lxc — Debian LXC + Claude Code for Proxmox VE
EOF
  echo
}

usage() {
  cat <<EOF
proxmox-claude-lxc $VERSION — $REPO_URL

Usage (on the Proxmox node, as root):
  bash proxmox-claude-lxc.sh [--yes] [--lang fr|en]

  --yes, -y     no questions: defaults, overridden by the CLX_* variables
  --lang fr|en  language of the messages (otherwise asked)
  --help, -h    this help

Variables (all optional):
  CLX_CTID      container ID              (next free ID)
  CLX_HOSTNAME  container name            ($D_HOSTNAME)
  CLX_DISK      disk, GB                  ($D_DISK)
  CLX_CORES     vCPU                      ($D_CORES)
  CLX_RAM       RAM, MB                   ($D_RAM)
  CLX_SWAP      swap, MB                  ($D_SWAP)
  CLX_STORAGE   container storage         (local-lvm, or the first one available)
  CLX_BRIDGE    network bridge            ($D_BRIDGE)
  CLX_IP        dhcp or CIDR              ($D_IP)
  CLX_GW        gateway (static IP)
  CLX_USER      user account              ($D_USER)
  CLX_PASSWORD  its password              (generated and shown at the end)
  CLX_SSH_KEY   public SSH key, or path to a .pub file
  CLX_SUDO_NOPASSWD  1 = passwordless sudo ($D_SUDO_NOPASSWD)
  CLX_GIT_NAME, CLX_GIT_EMAIL   git identity of the user

Example — a second container, no questions:
  CLX_HOSTNAME=claude-satwatch CLX_SSH_KEY=~/.ssh/id_ed25519.pub \\
    bash proxmox-claude-lxc.sh --yes --lang fr
EOF
}

# ─── Pre-checks ───────────────────────────────────────────────────────────────
check_root() {
  [[ $EUID -eq 0 ]] || { msg_err "Run this as root on the Proxmox node."; exit 1; }
}
check_proxmox() {
  local cmd
  for cmd in pct pveam pvesm; do
    command -v "$cmd" >/dev/null || { msg_err "{1} not found: not on a Proxmox VE node?" "$cmd"; exit 1; }
  done
}

# ─── Defaults ─────────────────────────────────────────────────────────────────
D_HOSTNAME="claude-dev"
D_DISK="16"          # GB: Debian + toolchains + projects
D_CORES="2"
D_RAM="4096"         # MB: Claude Code plus a build or test run
D_SWAP="1024"        # MB
D_BRIDGE="vmbr0"
D_IP="dhcp"
D_USER="dev"
D_SUDO_NOPASSWD="1"  # the container is a sandbox: Claude Code can run sudo

PACKAGES="sudo curl ca-certificates git openssh-server avahi-daemon locales tmux \
ripgrep jq unzip less nano htop build-essential python3 python3-venv python3-pip"

# IDs are shared by VMs and containers across the whole cluster: pvesh knows
# this, pct status only sees the containers of this node.
id_free() {
  if command -v pvesh >/dev/null; then
    pvesh get /cluster/nextid --vmid "$1" >/dev/null 2>&1
  else
    ! pct status "$1" &>/dev/null && ! qm status "$1" &>/dev/null
  fi
}

find_next_ctid() {
  local id
  id=$(pvesh get /cluster/nextid 2>/dev/null | tr -d '"[:space:]') || true
  if [[ $id =~ ^[0-9]+$ ]]; then echo "$id"; return; fi
  id=100
  while ! id_free "$id"; do ((id++)); done
  echo "$id"
}

first_storage() {  # first_storage CONTENT PREFERRED → an active storage accepting CONTENT
  local found
  found=$(pvesm status -content "$1" 2>/dev/null | awk 'NR > 1 && $3 == "active" {print $1}')
  if grep -qx "$2" <<<"$found"; then echo "$2"; else echo "${found%%$'\n'*}"; fi
}

ask() {  # ask VAR "Question" [default] — with --yes, takes the default silently
  local answer=""
  if [[ $ASSUME_YES != 1 ]]; then read -rp "$(t "$2")${3:+ [$3]} : " answer || true; fi
  printf -v "$1" '%s' "${answer:-${3:-}}"
}

valid_hostname() { [[ $1 =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
valid_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ && $1 != root ]]; }
valid_ip() { [[ $1 == dhcp || $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; }

gen_password() {  # 16 characters, no ambiguous ones
  local pw=""
  while (( ${#pw} < 16 )); do
    pw+=$(head -c 64 /dev/urandom | tr -dc 'A-HJ-NP-Za-km-z2-9' || true)
  done
  printf '%s' "${pw:0:16}"
}

read_ssh_key() {  # read_ssh_key VALUE → key line (VALUE may be a file path)
  local v="$1"
  if [[ -z $v ]]; then return 0; fi
  if [[ $v == ssh-* || $v == ecdsa-* || $v == sk-* ]]; then printf '%s' "$v"; return 0; fi
  v="${v/#\~/$HOME}"
  [[ -f $v ]] || { msg_err "SSH key file not found: {1}" "$v"; exit 1; }
  head -n1 "$v"
}

# ─── Questions ────────────────────────────────────────────────────────────────
prompt_config() {
  local d_ctid d_storage c pw2 key_in
  d_ctid="${CLX_CTID:-$(find_next_ctid)}"
  d_storage="${CLX_STORAGE:-$(first_storage rootdir local-lvm)}"
  TMPL_STORAGE=$(first_storage vztmpl local)
  [[ -n $TMPL_STORAGE ]] || { msg_err "No active storage accepts templates (vztmpl)."; exit 1; }

  echo -e "${BOLD}$(t "Container")${NC} $(t "(Enter = suggested value)")"
  while :; do
    ask CTID "Container ID" "$d_ctid"
    if [[ $CTID =~ ^[0-9]+$ ]] && (( CTID >= 100 )) && id_free "$CTID"; then break; fi
    msg_warn "Invalid ID, or already used (VM or container)."
    if [[ $ASSUME_YES == 1 ]]; then exit 1; fi
  done
  while :; do
    ask CT_HOST "Container name" "${CLX_HOSTNAME:-$D_HOSTNAME}"
    CT_HOST="${CT_HOST,,}"
    if valid_hostname "$CT_HOST"; then break; fi
    msg_warn "Invalid name: letters, digits and hyphens."
    if [[ $ASSUME_YES == 1 ]]; then exit 1; fi
  done
  ask DISK "Disk (GB)" "${CLX_DISK:-$D_DISK}"
  ask CORES "vCPU" "${CLX_CORES:-$D_CORES}"
  ask RAM "RAM (MB)" "${CLX_RAM:-$D_RAM}"
  ask SWAP "Swap (MB)" "${CLX_SWAP:-$D_SWAP}"
  for c in DISK CORES RAM SWAP; do
    [[ ${!c} =~ ^[0-9]+$ ]] || { msg_err "{1} must be a number: {2}" "$c" "${!c}"; exit 1; }
  done
  ask STORAGE "Container storage" "$d_storage"
  ask BRIDGE "Network bridge" "${CLX_BRIDGE:-$D_BRIDGE}"
  while :; do
    ask IP "IP (dhcp or CIDR, e.g. 192.168.1.50/24)" "${CLX_IP:-$D_IP}"
    if valid_ip "$IP"; then break; fi
    msg_warn "Invalid address."
    if [[ $ASSUME_YES == 1 ]]; then exit 1; fi
  done
  GATEWAY=""
  if [[ $IP != dhcp ]]; then ask GATEWAY "Gateway (e.g. 192.168.1.1)" "${CLX_GW:-}"; fi

  echo
  echo -e "${BOLD}$(t "User")${NC}"
  while :; do
    ask CT_USER "User name" "${CLX_USER:-$D_USER}"
    if valid_user "$CT_USER"; then break; fi
    msg_warn "Invalid user name: lowercase letters, digits, - and _ (not root)."
    if [[ $ASSUME_YES == 1 ]]; then exit 1; fi
  done
  USER_PW="${CLX_PASSWORD:-}"
  if [[ -z $USER_PW && $ASSUME_YES != 1 ]]; then
    while :; do
      read -rsp "$(t "Password of {1} (empty = generated)" "$CT_USER") : " USER_PW || true; echo
      if [[ -z $USER_PW ]]; then break; fi
      read -rsp "$(t "Confirm") : " pw2 || true; echo
      if [[ $USER_PW == "$pw2" ]]; then break; fi
      msg_warn "Passwords differ."
    done
  fi
  PW_GENERATED=0
  if [[ -z $USER_PW ]]; then USER_PW=$(gen_password); PW_GENERATED=1; fi

  ask c "$(t "Passwordless sudo for {1}? (convenient for Claude Code)" "$CT_USER")" \
    "$([[ ${CLX_SUDO_NOPASSWD:-$D_SUDO_NOPASSWD} == 1 ]] && echo y || echo n)"
  if [[ ${c,,} =~ ^[yo] || $c == 1 ]]; then SUDO_NOPASSWD=1; else SUDO_NOPASSWD=0; fi

  key_in="${CLX_SSH_KEY:-}"
  if [[ -z $key_in && $ASSUME_YES != 1 ]]; then
    say "Public SSH key (line ssh-ed25519/ssh-rsa… or file path), Enter to skip"
    read -r key_in || true
  fi
  SSH_PUBKEY=$(read_ssh_key "$key_in")
  ask GIT_NAME "Git name (optional)" "${CLX_GIT_NAME:-}"
  ask GIT_EMAIL "Git email (optional)" "${CLX_GIT_EMAIL:-}"

  echo
  echo -e "${BOLD}$(t "Summary")${NC}"
  say "  CT {1} '{2}': disk {3} GB, {4} vCPU, RAM {5} MB, swap {6} MB" "$CTID" "$CT_HOST" "$DISK" "$CORES" "$RAM" "$SWAP"
  say "  storage {1}, bridge {2}, IP {3}{4}" "$STORAGE" "$BRIDGE" "$IP" "${GATEWAY:+ ($(t "gateway") $GATEWAY)}"
  say "  user {1} ({2}), SSH key: {3}" "$CT_USER" \
    "$(if [[ $SUDO_NOPASSWD == 1 ]]; then t "passwordless sudo"; else t "sudo with password"; fi)" \
    "$(if [[ -n $SSH_PUBKEY ]]; then t "yes"; else t "no"; fi)"
  if [[ $ASSUME_YES != 1 ]]; then
    read -rp "$(t "Continue?") [$([[ $UI_LANG == fr ]] && echo "O/n" || echo "Y/n")] : " c || true
    [[ "${c:-Y}" =~ ^[OoYy]$ ]] || { msg_warn "Cancelled: nothing has been created."; exit 0; }
  fi
}

# ─── Template ─────────────────────────────────────────────────────────────────
ensure_template() {
  local tmpl="" version
  msg_info "Looking for a Debian template…"
  pveam update >/dev/null 2>&1 || true
  for version in 13 12; do
    tmpl=$(pveam available --section system 2>/dev/null \
           | awk -v v="debian-$version-standard" '$2 ~ "^"v".*amd64" {print $2}' | sort -V | tail -n1)
    if [[ -n $tmpl ]]; then break; fi
  done
  [[ -n $tmpl ]] || { msg_err "No debian-13/12-standard template in pveam."; exit 1; }
  if ! pveam list "$TMPL_STORAGE" 2>/dev/null | grep -q "$tmpl"; then
    msg_info "Downloading template {1}…" "$tmpl"
    pveam download "$TMPL_STORAGE" "$tmpl" >/dev/null
  fi
  TEMPLATE="${TMPL_STORAGE}:vztmpl/${tmpl}"
  msg_ok "Template: {1}" "$tmpl"
}

# ─── Container creation ───────────────────────────────────────────────────────
create_lxc() {
  local net="name=eth0,bridge=${BRIDGE}" keyfile="" extra=()
  if [[ $IP == dhcp ]]; then net="${net},ip=dhcp"; else net="${net},ip=${IP}${GATEWAY:+,gw=${GATEWAY}}"; fi
  if [[ -n $SSH_PUBKEY ]]; then
    keyfile=$(mktemp)
    echo "$SSH_PUBKEY" > "$keyfile"
    extra+=(--ssh-public-keys "$keyfile")
  fi

  msg_info "Creating container {1}…" "$CTID"
  # nesting=1: systemd services of Debian 13 need namespaces in an
  # unprivileged container; keyctl=1 lets tools that use the kernel keyring
  # (e.g. Docker, podman) work. Root gets no password: harden_root() locks it.
  pct create "$CTID" "$TEMPLATE" \
    --hostname "$CT_HOST" \
    --cores "$CORES" \
    --memory "$RAM" \
    --swap "$SWAP" \
    --rootfs "${STORAGE}:${DISK}" \
    --net0 "$net" \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 \
    --onboot 1 \
    --timezone host \
    --ostype debian \
    --tags claude \
    --description "Claude Code dev container — $REPO_URL" \
    "${extra[@]}" >/dev/null
  if [[ -n $keyfile ]]; then rm -f "$keyfile"; fi
  msg_ok "Container {1} created." "$CTID"

  msg_info "Starting…"
  pct start "$CTID"
  msg_ok "Container started."
}

# ─── Container setup ──────────────────────────────────────────────────────────
ct() { pct exec "$CTID" -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

wait_network() {
  local n=30
  msg_info "Waiting for the network in the container…"
  while (( n-- > 0 )); do
    if ct getent hosts claude.ai &>/dev/null; then msg_ok "Network OK."; return; fi
    sleep 2
  done
  msg_err "No Internet access (DNS) in the container: check bridge, IP and gateway."
  exit 1
}

prepare_ct() {
  msg_info "Updating the system (apt)…"
  ct bash -c 'apt-get update -qq && apt-get upgrade -y -qq' >/dev/null
  msg_ok "System up to date."
  msg_info "Packages: {1}…" "$PACKAGES"
  ct bash -c "apt-get install -y -qq --no-install-recommends $PACKAGES" >/dev/null
  # <name>.local address: in an unprivileged container avahi's rlimit-nproc
  # limit is shared with the other containers (same UID range) → disabled.
  ct bash -c 'sed -i "s/^rlimit-nproc=/#rlimit-nproc=/" /etc/avahi/avahi-daemon.conf
              systemctl restart avahi-daemon' >/dev/null 2>&1 || true
  msg_ok "Packages installed."
}

harden_root() {
  # Root never logs in with a password: its password is locked (whatever the
  # template ships with) and SSH only accepts a key for it. Root access stays
  # possible through `pct enter` on the node, or SSH with the provided key.
  ct passwd -l root >/dev/null
  ct bash -c 'install -d /etc/ssh/sshd_config.d
              echo "PermitRootLogin prohibit-password" > /etc/ssh/sshd_config.d/10-root-key-only.conf
              systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true'
  msg_ok "Root: password locked, SSH by key only."
}

create_user() {
  local home="/home/$CT_USER"
  msg_info "Creating user {1}…" "$CT_USER"
  ct useradd -m -s /bin/bash -G sudo "$CT_USER"
  # Password through stdin: never on a command line (ps, logs).
  printf '%s:%s\n' "$CT_USER" "$USER_PW" | pct exec "$CTID" -- chpasswd
  if [[ $SUDO_NOPASSWD == 1 ]]; then
    ct bash -c "echo '$CT_USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-$CT_USER
                chmod 440 /etc/sudoers.d/90-$CT_USER"
  fi
  if [[ -n $SSH_PUBKEY ]]; then
    printf '%s\n' "$SSH_PUBKEY" | pct exec "$CTID" -- bash -c \
      "install -d -m 700 -o '$CT_USER' -g '$CT_USER' '$home/.ssh'
       cat >> '$home/.ssh/authorized_keys'
       chown '$CT_USER:$CT_USER' '$home/.ssh/authorized_keys'; chmod 600 '$home/.ssh/authorized_keys'"
  fi
  as_user "mkdir -p ~/projects"
  # ~/.local/bin (where Claude Code lives) also in non-login shells.
  as_user "grep -q 'HOME/.local/bin' ~/.bashrc || echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
  if [[ -n $GIT_NAME ]]; then as_user "git config --global user.name $(printf '%q' "$GIT_NAME")"; fi
  if [[ -n $GIT_EMAIL ]]; then as_user "git config --global user.email $(printf '%q' "$GIT_EMAIL")"; fi
  as_user "git config --global init.defaultBranch main"
  msg_ok "User {1} ready." "$CT_USER"
}

as_user() { ct runuser -l "$CT_USER" -c "$1"; }

# ─── Claude Code ──────────────────────────────────────────────────────────────
install_claude() {
  local version
  msg_info "Installing Claude Code for {1}…" "$CT_USER"
  # Official native installer: ~/.local/bin/claude, kept up to date by itself.
  as_user "curl -fsSL $CLAUDE_INSTALL_URL | bash" || return 1
  # shellcheck disable=SC2016  # $HOME is expanded inside the container
  version=$(as_user '$HOME/.local/bin/claude --version' 2>/dev/null | head -n1) || return 1
  [[ -n $version ]] || return 1
  msg_ok "Claude Code installed: {1}" "$version"
}

claude_failed() {
  msg_err "Claude Code install failed (container {1} is kept)." "$CTID"
  say "  Retry       : pct exec {1} -- runuser -l {2} -c 'curl -fsSL {3} | bash'" "$CTID" "$CT_USER" "$CLAUDE_INSTALL_URL"
  say "  Console     : pct enter {1}, then su - {2}" "$CTID" "$CT_USER"
  say "  Delete      : pct stop {1} && pct destroy {1}" "$CTID"
  exit 1
}

# ─── Final summary ────────────────────────────────────────────────────────────
ct_ip() {
  ct bash -c "ip -4 -o addr show eth0 | awk '{print \$4}' | cut -d/ -f1 | head -n1" 2>/dev/null || true
}

show_summary() {
  local ip
  ip=$(ct_ip)
  echo
  echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  $(t "Claude Code is ready in container {1}" "$CTID")${NC}"
  echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  say "  Container   : {1} ({2})  IP {3}" "$CTID" "$CT_HOST" "${ip:-?}"
  say "  User        : {1}" "$CT_USER"
  if [[ $PW_GENERATED == 1 ]]; then say "  Password    : {1}   (generated: write it down)" "$USER_PW"; fi
  say "  Connect     : ssh {1}@{2}" "$CT_USER" "${ip:-$CT_HOST.local}"
  say "  Console     : pct enter {1}, then su - {2}" "$CTID" "$CT_USER"
  say "  Then run    : claude   (first launch: sign in through the link shown)"
  say "  Projects    : ~/projects"
  say "  Delete      : pct stop {1} && pct destroy {1}" "$CTID"
  echo
}

# ─── Main ─────────────────────────────────────────────────────────────────────
ASSUME_YES="${CLX_YES:-0}"

parse_args() {
  while (( $# )); do
    case "$1" in
      -y|--yes) ASSUME_YES=1 ;;
      --lang) UI_LANG="${2:-}"; shift ;;
      --lang=*) UI_LANG="${1#--lang=}" ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  header
  ask_lang
  check_root
  check_proxmox
  prompt_config
  ensure_template
  create_lxc
  wait_network
  prepare_ct
  harden_root
  create_user
  install_claude || claude_failed
  show_summary
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
