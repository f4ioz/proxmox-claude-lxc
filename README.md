*English version: [README.en.md](README.en.md)*

# proxmox-claude-lxc

Un script pour **Proxmox VE** qui crée, en une commande, un conteneur LXC
Debian prêt pour **[Claude Code](https://claude.com/claude-code)** : système à
jour, outils de développement, compte utilisateur avec sudo, Claude Code
installé. Pratique pour ouvrir un conteneur par projet et y laisser travailler
Claude sans toucher à vos autres machines.

## Utilisation

Sur le nœud Proxmox, en **root** (shell du nœud dans l'interface web, ou SSH) :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/f4ioz/proxmox-claude-lxc/main/proxmox-claude-lxc.sh)"
```

Le script pose quelques questions (Entrée garde la valeur proposée), affiche un
récapitulatif, puis crée et prépare le conteneur. À la fin :

```bash
ssh dev@<ip-du-conteneur>      # ou : pct enter <ID>, puis su - dev
claude                         # 1er lancement : connexion par le lien affiché
```

La connexion à Claude se fait au premier lancement de `claude` (compte
Claude Pro/Max, ou clé API Anthropic) : le script ne manipule aucun
identifiant Anthropic.

## Ce que fait le script

1. Vérifie qu'il tourne en root sur un nœud Proxmox (`pct`, `pveam`, `pvesm`).
2. Propose le **prochain ID libre** du cluster (VM et conteneurs confondus).
3. Télécharge le template **Debian 13** le plus récent (Debian 12 en repli).
4. Crée un conteneur **non privilégié** (`nesting=1,keyctl=1`, démarrage
   automatique, étiquette `claude`).
5. Met le système à jour et installe : git, curl, sudo, openssh-server,
   build-essential, python3 (+ venv, pip), ripgrep, jq, tmux, htop, nano,
   unzip, avahi (adresse `<nom>.local`).
6. Crée l'utilisateur (`dev` par défaut) : groupe sudo, **sudo sans mot de
   passe** si vous le voulez (pratique pour Claude Code), clé SSH, dossier
   `~/projects`, identité git.
7. Installe **Claude Code** pour cet utilisateur avec l'installeur officiel
   (`https://claude.ai/install.sh` → `~/.local/bin/claude`, mis à jour
   automatiquement) et vérifie qu'il répond.

| Réglage | Par défaut |
|---|---|
| Nom | `claude-dev` |
| Disque / vCPU / RAM / swap | 16 Go / 2 / 4096 Mo / 1024 Mo |
| Stockage | `local-lvm` (sinon le premier stockage actif) |
| Réseau | `vmbr0`, DHCP (ou IP fixe en CIDR + passerelle) |
| Utilisateur | `dev`, mot de passe généré (affiché à la fin) si vous n'en tapez pas |

Le compte **root** du conteneur n'a pas de mot de passe : il est
**verrouillé** (personne ne peut s'y connecter par mot de passe), ce qui est
plus sûr qu'un mot de passe root. On y accède par `pct enter <ID>` depuis le
nœud, ou en SSH avec la clé fournie.

## Sans question (plusieurs conteneurs)

`--yes` prend les valeurs par défaut, remplacées par les variables `CLX_*` :

```bash
curl -fsSL -o proxmox-claude-lxc.sh \
  https://raw.githubusercontent.com/f4ioz/proxmox-claude-lxc/main/proxmox-claude-lxc.sh

CLX_HOSTNAME=claude-satwatch CLX_SSH_KEY=~/.ssh/id_ed25519.pub \
  bash proxmox-claude-lxc.sh --yes --lang fr
```

| Variable | Rôle |
|---|---|
| `CLX_CTID` | ID du conteneur (prochain libre) |
| `CLX_HOSTNAME` | nom du conteneur |
| `CLX_DISK`, `CLX_CORES`, `CLX_RAM`, `CLX_SWAP` | ressources (Go, vCPU, Mo, Mo) |
| `CLX_STORAGE`, `CLX_BRIDGE` | stockage, bridge réseau |
| `CLX_IP`, `CLX_GW` | `dhcp` ou IP en CIDR, passerelle |
| `CLX_USER`, `CLX_PASSWORD` | utilisateur, mot de passe (généré si vide) |
| `CLX_SSH_KEY` | clé publique, ou chemin d'un fichier `.pub` |
| `CLX_SUDO_NOPASSWD` | `1` (défaut) = sudo sans mot de passe, `0` = avec |
| `CLX_GIT_NAME`, `CLX_GIT_EMAIL` | identité git de l'utilisateur |
| `CLX_LANG` | `fr` ou `en` (comme `--lang`) |
| `CLX_APT_TIMEOUT` | délai maximum de chaque étape apt, en secondes (1800) |

`bash proxmox-claude-lxc.sh --help` résume tout cela.

## Sécurité

- Conteneur **non privilégié** : root dans le conteneur n'est pas root sur
  l'hôte.
- Root : mot de passe verrouillé (`passwd -l root`) et SSH par clé uniquement
  (`PermitRootLogin prohibit-password`), imposés par le script quel que soit
  le template.
- **Clé SSH fournie → SSH par clé uniquement** : la connexion SSH par mot de
  passe est refusée (`PasswordAuthentication no`), une fois la clé installée.
  Le mot de passe de l'utilisateur sert alors à sudo et à la console
  (`pct enter`). Sans clé, la connexion par mot de passe reste possible.
- Le mot de passe passe par l'entrée standard (`chpasswd`), jamais sur une
  ligne de commande.
- Sudo sans mot de passe est un choix de confort pour un conteneur de
  développement isolé : répondez « n » (ou `CLX_SUDO_NOPASSWD=0`) si le
  conteneur doit être partagé ou exposé.
- Claude Code exécute des commandes dans le conteneur : gardez-y vos projets,
  pas vos secrets de production.

## Supprimer un conteneur

```bash
pct stop <ID> && pct destroy <ID>
```

## Développement

Les tests simulent un nœud Proxmox (fausses commandes `pct`, `pveam`,
`pvesm`, `pvesh`, `qm`) : aucun conteneur n'est créé.

```bash
pip install pytest shellcheck-py
pytest
```

## Licence

MIT — voir [LICENSE](LICENSE). Claude Code est un produit d'Anthropic, soumis
à ses propres conditions d'utilisation ; ce script n'est pas un projet
officiel d'Anthropic.
