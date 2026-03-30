# PicoClaw for Home Assistant

Run [PicoClaw](https://github.com/sipeed/picoclaw) — an open-source AI agent runtime — directly inside Home Assistant as a native add-on.

**One click to install, one JSON to configure, everything accessible from the HA sidebar.**

![PicoClaw launcher UI inside Home Assistant](picoclaw/assets/launcher-webui.jpg)

---

## Table of Contents

- [Why This Add-on](#why-this-add-on)
- [Quick Start](#quick-start)
  - [Install](#install)
  - [Configure](#configure)
  - [Use](#use)
- [Configuration Examples](#configuration-examples)
  - [Minimal (OpenAI)](#minimal-openai)
  - [With MCP and Home Assistant](#with-mcp-and-home-assistant)
  - [Full Example](#full-example)
- [What the Wrapper Does for You](#what-the-wrapper-does-for-you)
  - [Accessible UI via Ingress](#accessible-ui-via-ingress)
  - [Smart Config Defaults](#smart-config-defaults)
- [Debugging](#debugging)
- [Architecture](#architecture)
  - [Design Philosophy](#design-philosophy)
  - [Storage Layout](#storage-layout)
  - [Repository Structure](#repository-structure)
- [Learn More](#learn-more)

---

## Why This Add-on

PicoClaw is a powerful AI agent runtime: chat interface, gateway, skills, tools, MCP support. But installing it standalone means managing Docker, ports, config files, and persistence manually.

This add-on gives you all of that with Home Assistant ergonomics:

| Feature | |
|---|---|
| Install | One-click from the HA add-on store |
| UI access | HA sidebar via Ingress |
| Persistence | Automatic across restarts and updates |
| **Agent workspace** | **Fully editable from HA — see below** |

### 🗂️ Edit everything directly from Home Assistant

The entire agent workspace lives at `/share/picoclaw/workspace`, accessible from **File Editor**, **Samba**, or **SSH** — without leaving Home Assistant.

This means you can tune every aspect of the agent's behaviour from within HA:

| File / Folder | What you can change |
|---|---|
| `USER.md` | Who the agent thinks it's talking to — your preferences, context, habits |
| `AGENT.md` · `SOUL.md` | The agent's main persona, behavior, and values |
| `TOOLS.md` | Workspace-specific rules and preferences for tool usage |
| `HEARTBEAT.md` | Periodic self-reflection prompts |
| `config.full.json` | The full editable shared PicoClaw config used by the add-on |
| `skills/` | Add, edit, or disable agent skills (remove a folder to disable) |
| `memory/` | Browse and edit the agent's long-term memory |
| `sessions/` | Inspect past conversations |

No terminal, no Docker, no manual file mounting — everything stays inside Home Assistant.

---

## Quick Start

### Install

1. Go to **Settings > Add-ons > Add-on Store**
2. Click **...** (top right) > **Repositories** and add:
   ```
   https://github.com/JustTrying-Arduino/ha-picoclaw
   ```
3. Refresh, find **PicoClaw**, click **Install**

### Configure

1. Open the add-on **Configuration** tab
2. Paste your JSON config into `raw_json_config` (see [examples below](#configuration-examples))
3. Click **Save**

### Use

1. **Start** the add-on
2. Click **Open Web UI** (or use the sidebar entry)
3. Configure your model/credentials in the launcher UI
4. Click **Start Gateway** and start chatting

---

## Configuration Examples

The add-on exposes a single option: `raw_json_config`. On first boot, the wrapper uses it to seed `/share/picoclaw/workspace/config.full.json`, then that shared file becomes the editable source of truth used by the launcher and gateway.
Sensitive values are kept out of `config.full.json`; use the launcher UI or `/share/picoclaw/.security.yml` for secrets.

> You don't need to specify workspace paths, file tools, or skill tools — the wrapper injects them automatically if missing.

### Minimal (OpenAI)

The smallest config to get started:

```json
{
  "agents": {
    "defaults": {
      "model_name": "gpt-4o",
      "restrict_to_workspace": true
    }
  },
  "model_list": [
    {
      "model_name": "gpt-4o",
      "model": "openai/gpt-4o",
      "api_key": "sk-your-openai-key",
      "api_base": "https://api.openai.com/v1"
    }
  ]
}
```

That's it. The wrapper auto-enables file tools, skill tools, and sets sane gateway defaults.

### With MCP and Home Assistant

Connect PicoClaw to Home Assistant's own MCP server so the agent can control your smart home:

```json
{
  "agents": {
    "defaults": {
      "model_name": "gpt-4o",
      "restrict_to_workspace": true,
      "max_tokens": 8192
    }
  },
  "model_list": [
    {
      "model_name": "gpt-4o",
      "model": "openai/gpt-4o",
      "api_key": "sk-your-openai-key",
      "api_base": "https://api.openai.com/v1"
    }
  ],
  "tools": {
    "exec": { "enabled": true, "enable_deny_patterns": true },
    "web": { "enabled": true },
    "mcp": {
      "enabled": true,
      "servers": {
        "home-assistant": {
          "enabled": true,
          "type": "http",
          "url": "http://homeassistant:8123/api/mcp",
          "headers": {
            "Authorization": "Bearer YOUR_LONG_LIVED_ACCESS_TOKEN"
          }
        }
      }
    }
  }
}
```

> Replace `YOUR_LONG_LIVED_ACCESS_TOKEN` with a token from **Profile > Long-Lived Access Tokens** in HA.

### Full Example

See [`picoclaw/examples/raw_json_config.example.json`](picoclaw/examples/raw_json_config.example.json) for a complete configuration with all tools explicitly enabled, MCP pre-configured, and debug logging.

---

## What the Wrapper Does for You

### Accessible UI via Ingress

The full PicoClaw launcher UI runs inside Home Assistant through Ingress — no port forwarding needed:

- Model and credentials configuration
- Channel setup (Telegram, etc.)
- Gateway control (start/stop/status)
- Built-in chat interface
- Raw config editor, logs, tools, and skills management

Open it from the add-on page (**Open Web UI**) or pin it to the HA sidebar for one-click access.

### Smart Config Defaults

Every time the add-on starts, the wrapper normalizes the effective shared config:

| Setting | Behavior |
|---|---|
| `agents.defaults.workspace` | Forced to `/share/picoclaw/workspace` |
| `gateway.host` | Defaults to `127.0.0.1` if absent |
| `gateway.port` | Defaults to `18790` if absent |
| `tools.web.prefer_native` | Defaults to `false` if absent |
| File tools (`list_dir`, `read_file`, `write_file`, `append_file`, `edit_file`) | Auto-enabled if absent |
| Skill tools (`skills`, `find_skills`, `install_skill`) | Auto-enabled if absent |
| `version` | Forced to `1` |

Invalid JSON is rejected at startup with a clear error — the add-on fails fast instead of launching broken.

---

## Debugging

Add this to `raw_json_config` before first boot, or to `/share/picoclaw/workspace/config.full.json` afterwards, then restart:

```json
{
  "gateway": {
    "log_level": "debug"
  }
}
```

This enables verbose logging in the HA add-on logs: gateway traffic, prompts, tool calls, cron activity, heartbeat activity, and non-truncated output. The wrapper still suppresses the noisy recurring `Gateway health status: 200` line.

For optional security configuration, place a `.security.yml` file in `/share/picoclaw/` — the wrapper copies it to the runtime directory at each startup.

---

## Architecture

### Design Philosophy

**This is a wrapper, not a fork.**

- Home Assistant owns: add-on packaging, storage, ingress, config validation, release automation
- PicoClaw owns: agent behavior, launcher, gateway, models, tools, MCP, channels

The wrapper applies a single small patch on the upstream code (for Ingress compatibility and English defaults). Everything else is upstream `sipeed/picoclaw` built from official release tags.

### Storage Layout

```
/share/picoclaw/                  <-- Editable (File Editor, Samba, SSH)
  workspace/                      <-- Agent workspace (AGENT.md, USER.md, TOOLS.md, config.full.json, ...)
  workspace/config.full.json      <-- Full normalized shared config used by the add-on
  workspace/launcher-config.json  <-- Launcher web settings managed by the wrapper/UI
  .security.yml                   <-- Optional, copied to runtime at startup

/data/picoclaw/                   <-- Managed by the add-on (not user-facing)
  config.json                     <-- Symlink to workspace/config.full.json
  launcher-config.json            <-- Symlink to workspace/launcher-config.json
  .security.yml                   <-- Runtime secrets file, kept outside the workspace
  workspace -> /share/...         <-- Symlink to shared workspace
```

### Repository Structure

```
repository.yaml                   # HA add-on repo metadata
scripts/set-version.sh            # Bump upstream + wrapper versions
.github/workflows/
  ci.yml                          # YAML/JSON validation, smoke test
  publish.yml                     # Multi-arch build + push to GHCR
  sync-upstream-release.yml       # Weekly check for new upstream releases
picoclaw/
  config.yaml                     # Add-on manifest
  build.yaml                      # Build versions and base images
  Dockerfile                      # Multi-stage build (Go + Alpine)
  run.sh                          # Entrypoint: validation, normalization, launch
  patches/                        # Ingress + English defaults patch
  DOCS.md                         # Full operational documentation
```

---

## Learn More

**PicoClaw upstream:**
- [Documentation](https://docs.picoclaw.io/)
- [Getting Started](https://docs.picoclaw.io/docs/getting-started/)
- [Configuration Reference](https://docs.picoclaw.io/docs/configuration/config-reference/)
- [Model Configuration](https://docs.picoclaw.io/docs/configuration/model-list/)
- [Tools & MCP](https://docs.picoclaw.io/docs/configuration/tools/)
- [Security Sandbox](https://docs.picoclaw.io/docs/configuration/security-sandbox/)

**Home Assistant:**
- [Custom Add-on Repositories](https://developers.home-assistant.io/docs/add-ons/repository)
- [Add-on Ingress](https://developers.home-assistant.io/docs/add-ons/presentation)
- [Add-on Communication](https://developers.home-assistant.io/docs/add-ons/communication/)

**This project:**
- [Full operational docs](picoclaw/DOCS.md)
- [Example configuration](picoclaw/examples/raw_json_config.example.json)
- [Upstream source](https://github.com/sipeed/picoclaw)
