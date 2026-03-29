# CLAUDE.md — Contexte projet ha-picoclaw

## Qu'est-ce que ce projet ?

**ha-picoclaw** est un **wrapper Home Assistant Add-on** autour du projet upstream [sipeed/picoclaw](https://github.com/sipeed/picoclaw).
Ce n'est **pas** un custom component HA (pas de `custom_components/`, pas de sensors/switches/entites).
PicoClaw est un runtime d'agent IA (chat, gateway, skills, tools). Le wrapper fournit le packaging Docker, le stockage persistant, l'ingress HA, et la normalisation de config.

**Philosophie** : wrapper mince, pas un fork. HA gere le cycle de vie, PicoClaw gere la logique agent.

---

## Arborescence des fichiers

```
.
├── CLAUDE.md                          # Ce fichier de contexte
├── README.md                          # Documentation generale du repo
├── repository.yaml                    # Metadonnees du depot HA add-on
├── scripts/
│   └── set-version.sh                 # Met a jour les versions (upstream + wrapper) dans build.yaml, config.yaml, Dockerfile
├── .github/workflows/
│   ├── ci.yml                         # Validation YAML/JSON, lint shell, build smoke amd64, smoke test
│   ├── publish.yml                    # Build multi-arch (amd64, aarch64, armv7) + push GHCR
│   └── sync-upstream-release.yml      # Cron hebdo : detecte nouvelle release upstream, cree PR auto
└── picoclaw/                          # Le add-on lui-meme
    ├── config.yaml                    # Manifeste HA add-on (version, arch, ingress, options)
    ├── build.yaml                     # Versions : PICOCLAW_VERSION (upstream) + PICOCLAW_WRAPPER_VERSION
    ├── Dockerfile                     # Build multi-stage : Go builder -> runtime Alpine
    ├── run.sh                         # Point d'entree : setup dirs, normalise config, lance le launcher
    ├── DOCS.md                        # Documentation operationnelle complete
    ├── README.md                      # Guide demarrage rapide
    ├── translations/en.yaml           # Labels des options HA
    ├── examples/
    │   └── raw_json_config.example.json  # Template de configuration JSON
    ├── patches/
    │   └── 0001-launcher-ha-english-defaults.patch  # Patch ingress + UI anglais (598 lignes)
    ├── icon.png
    ├── logo.png
    └── assets/
        └── launcher-webui.jpg
```

---

## Versioning

Deux versions coexistent dans `picoclaw/build.yaml` :

| Cle                        | Exemple      | Role                                    |
|----------------------------|--------------|-----------------------------------------|
| `PICOCLAW_VERSION`         | `v0.2.4`     | Tag upstream sipeed/picoclaw a cloner   |
| `PICOCLAW_WRAPPER_VERSION` | `v0.2.4-ha.9`| Version du wrapper HA (affichee dans HA)|

Ces versions sont aussi dupliquees dans :
- `picoclaw/config.yaml` → champ `version`
- `picoclaw/Dockerfile` → ARG `PICOCLAW_VERSION` et `PICOCLAW_WRAPPER_VERSION`

**Pour mettre a jour** : `sh scripts/set-version.sh v0.3.0` (ou `sh scripts/set-version.sh v0.3.0 ha.2` pour specifier la revision wrapper).

---

## Flux de demarrage (run.sh)

Sequence executee au lancement du container :

1. **`ensure_directories`** — Cree `/share/picoclaw/`, `/share/picoclaw/workspace/`, `/data/picoclaw/`
2. **`ensure_workspace_symlink`** — `/data/picoclaw/workspace` → symlink vers `/share/picoclaw/workspace` (avec migration legacy si ancien format)
3. **`bootstrap_workspace_templates`** — **Premier demarrage uniquement** (marker `.workspace-templates-bootstrapped`) : copie les fichiers templates depuis `/usr/local/share/picoclaw/workspace` (bundlés dans l'image) vers `/share/picoclaw/workspace`, sans ecraser les fichiers existants
4. **`log_workspace_diagnostics`** — Log les chemins et verifie la coherence du symlink
5. **`copy_optional_security_file`** — Copie `.security.yml` de `/share` vers `/data` si present. Ignore `config.override.json` (prevention split-brain)
6. **`write_launcher_config`** — Ecrit `launcher-config.json` (`{"port": 18800, "public": true}`)
7. **`write_runtime_config`** — Lit `raw_json_config` des options HA, valide le JSON, normalise via `jq` :
   - Force `agents.defaults.workspace` = `/share/picoclaw/workspace`
   - Defaults `gateway.host` = `127.0.0.1`, `gateway.port` = `18790`
   - Force `tools.web.prefer_native` = `false` si absent
   - Auto-active les tools fichier + skills si absents
   - Force `version = 1`, trie les cles
8. **`start_launcher`** — Configure les env vars, detecte `gateway.log_level = "debug"`, lance `picoclaw-launcher` via `su-exec` (uid 1000)

---

## Pipeline Docker (Dockerfile)

### Stage 1 : Builder (`golang:1.25-alpine`)
- Clone upstream au tag `PICOCLAW_VERSION`
- Applique les patches depuis `/patches/*.patch` (tri alphabetique)
- `go generate ./...`
- Build frontend : `pnpm install --frozen-lockfile && pnpm build:backend`
- Compile 3 binaires Go (cross-compile via GOARCH) :
  - `picoclaw` (agent principal)
  - `picoclaw-launcher` (backend web UI)
  - `picoclaw-launcher-tui` (TUI)
- Copie le workspace entier depuis `src/workspace` (templates USER.md, skills, etc.)

### Stage 2 : Runtime (image base HA `3.22`)
- Installe : `bash`, `jq`, `su-exec`, `tzdata`, `ca-certificates`
- Cree user `picoclaw` (uid/gid 1000)
- Copie binaires + workspace templates (`/usr/local/share/picoclaw/workspace`) + `run.sh`
- Healthcheck : `wget http://127.0.0.1:18800/api/gateway/status` (interval 30s)

---

## Contrat de stockage

```
/share/picoclaw/                  ← Editable par l'utilisateur (File Editor, Samba, SSH)
├── workspace/                    ← Workspace de l'agent (USER.md, memory/, skills/, sessions/, etc.)
└── .security.yml                 ← Optionnel, copie vers /data au demarrage

/data/picoclaw/                   ← Gere par le add-on (pas d'acces direct utilisateur)
├── config.json                   ← Config normalisee (chmod 600)
├── launcher-config.json          ← {"port": 18800, "public": true}
├── .security.yml                 ← Copie depuis /share si present
├── .workspace-templates-bootstrapped  ← Marker : templates deja copies (1er demarrage)
├── workspace → /share/picoclaw/workspace  ← Symlink
└── logs/                         ← Logs gateway
```

---

## Le patch ingress (0001-launcher-ha-english-defaults.patch)

Unique patch applique sur le code upstream. 598 lignes. Modifie 21 fichiers.

### Backend (Go)
| Fichier | Modification |
|---------|-------------|
| `web/backend/api/gateway.go` | Ajoute flags `-d --no-truncate` si `log_level=debug` ; echo stdout des logs gateway |
| `web/backend/api/gateway_host.go` | Detecte header `X-Ingress-Path` et passe le base path au frontend |
| `web/backend/embed.go` | Injecte `window.__PICOCLAW_BASE_PATH__` dans le HTML servi |

### Frontend (TypeScript/React)
| Fichier | Modification |
|---------|-------------|
| `src/lib/runtime.ts` | **Nouveau fichier** : helper `withBasePath()` qui prefixe toutes les URLs API |
| `src/api/*.ts` (9 fichiers) | Toutes les URLs fetch wrappees avec `withBasePath()` |
| `src/main.tsx` | Router utilise `getRouterBasePath()` |
| `src/components/app-header.tsx` | WebSocket URL passe par le base path ingress |
| `src/components/config/*.tsx` | URLs config passent par base path |
| `src/components/models/provider-label.ts` | Labels chinois traduits en anglais (Qwen, Moonshot, etc.) |
| `src/i18n/index.ts` | Supprime le detecteur de langue i18next, force anglais par defaut |
| `vite.config.ts` | Ajustements build |

### Effet
Le launcher fonctionne dans l'iframe ingress HA a l'URL `/api/hassio/proxy/picoclaw/`.

---

## CI/CD

### ci.yml (chaque push/PR)
1. Valide syntaxe YAML (repository.yaml, build.yaml, config.yaml, translations/en.yaml)
2. Valide JSON de l'exemple
3. Lint shell (`bash -n`)
4. Build image Docker amd64 smoke
5. Smoke test : demarre le container, attend healthcheck, verifie config.json, launcher-config.json, workspace, enforcement du path

### publish.yml (push sur main ou dispatch manuel)
- Build 3 images via matrice : `amd64`, `aarch64`, `armv7`
- Cross-compile avec Docker Buildx + QEMU
- Push vers GHCR : `ghcr.io/justtrying-arduino/{arch}-picoclaw-ha:{version}` + tag `latest`

### sync-upstream-release.yml (cron lundi 05:17 UTC ou dispatch manuel)
- Interroge `sipeed/picoclaw/releases/latest` via `gh api`
- Compare avec la version courante dans `build.yaml`
- Si nouvelle version : execute `set-version.sh`, cree une PR automatique sur branche `codex/sync-picoclaw-{tag}`

---

## Configuration utilisateur

L'add-on expose une seule option HA : `raw_json_config` (string JSON brut).

Exemple minimal (voir `picoclaw/examples/raw_json_config.example.json`) :

```json
{
  "agents": {
    "defaults": {
      "model_name": "gpt-5.4",
      "restrict_to_workspace": true,
      "max_tokens": 8192,
      "context_window": 131072
    }
  },
  "model_list": [{ "model_name": "gpt-5.4", "model": "openai/gpt-5.4", "api_key": "sk-...", "api_base": "https://api.openai.com/v1" }],
  "tools": { "exec": {"enabled": true}, "web": {"enabled": true}, "mcp": {"enabled": false, "servers": {"home-assistant": {"enabled": false, "type": "http", "url": "http://homeassistant:8123/api/mcp", "headers": {"Authorization": "Bearer TOKEN"}}}} },
  "gateway": { "log_level": "debug" }
}
```

**Normalisations automatiques par run.sh** (le user n'a pas besoin de les specifier) :
- `version = 1` (force)
- `agents.defaults.workspace` = `/share/picoclaw/workspace` (force, non overridable)
- `gateway.host` = `127.0.0.1` (default si absent)
- `gateway.port` = `18790` (default si absent/0)
- `tools.web.prefer_native` = `false` (default si absent — desactive le mode natif du tool web)
- Tools fichier (`list_dir`, `read_file`, `write_file`, `append_file`, `edit_file`) et skills (`skills`, `find_skills`, `install_skill`) : auto-actives si absents

---

## Points d'attention pour les mises a jour upstream

1. **Le patch 0001 est le point de fragilite principal.** Toute modification upstream dans les fichiers patches (notamment `web/backend/api/gateway.go`, `web/backend/embed.go`, `web/frontend/src/api/*.ts`, `web/frontend/src/main.tsx`) peut casser l'application du patch. Apres chaque bump, verifier que `git apply` passe proprement.

2. **Nouvelles options de config upstream** : Si PicoClaw ajoute de nouvelles cles de config, verifier si `run.sh` doit les normaliser (section `write_runtime_config`).

3. **Nouveaux tools upstream** : Si de nouveaux tools apparaissent, decider s'ils doivent etre auto-actives dans la normalisation `jq` de `run.sh`.

4. **Build frontend** : La commande `pnpm build:backend` peut changer. Verifier le `package.json` upstream.

5. **Version Go** : Le Dockerfile utilise `golang:1.25-alpine`. Verifier la compatibilite avec les nouvelles versions upstream.

6. **Base images HA** : `ghcr.io/home-assistant/*-base:3.22` dans `build.yaml`. HA peut publier de nouvelles versions de base.

7. **Endpoints API modifies upstream** : Le patch prefixe toutes les URLs fetch. Si upstream ajoute/renomme des endpoints, le patch doit etre mis a jour.

8. **Workflow sync-upstream-release.yml** : Il met a jour les versions automatiquement mais ne regenere pas le patch. Un humain doit verifier que le patch s'applique toujours sur le nouveau tag et ajuster si necessaire.

---

## Ports internes

| Port  | Composant          | Binding       | Role                          |
|-------|--------------------|---------------|-------------------------------|
| 18800 | picoclaw-launcher  | 0.0.0.0       | Web UI (ingress HA)           |
| 18790 | picoclaw gateway   | 127.0.0.1     | API gateway interne           |

---

## Variables d'environnement definies au lancement

```bash
HOME=/data/picoclaw
PICOCLAW_HOME=/data/picoclaw
PICOCLAW_CONFIG=/data/picoclaw/config.json
PICOCLAW_BINARY=/usr/local/bin/picoclaw
PICOCLAW_GATEWAY_HOST=0.0.0.0
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
```

> **Note** : `PICOCLAW_BUILTIN_SKILLS` a ete supprime depuis `ha.9`. Les skills sont desormais bundlés dans le workspace template (`/usr/local/share/picoclaw/workspace`) et copies dans `/share/picoclaw/workspace` au premier demarrage.
