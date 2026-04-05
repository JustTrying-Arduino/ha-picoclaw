# PicoClaw

## What This Add-on Is

This add-on is a Home Assistant wrapper around the official `sipeed/picoclaw` releases. It does not try to fork PicoClaw behavior. The wrapper only owns Home Assistant concerns:

- storage layout
- startup validation
- ingress compatibility
- English-first defaults
- upstream release tracking

## Installation in Home Assistant

1. Open the Home Assistant add-on store.
   On current Home Assistant versions this is typically `Settings -> Add-ons -> Add-on Store`.
2. Add this GitHub repository as a custom add-on repository:
   `https://github.com/JustTrying-Arduino/ha-picoclaw`
3. Refresh the store, open `PicoClaw`, and click `Install`.
4. Wait for Home Assistant to build the image from the repository Dockerfile.
5. Open the configuration tab before the first start.

Home Assistant reference:
[Create an app repository](https://developers.home-assistant.io/docs/add-ons/repository)

Note:
This repository is currently configured so Home Assistant can build the add-on locally instead of requiring a pre-published GHCR image. This avoids install failures when the registry package is missing or still private.

## First Configuration

The add-on exposes one option only:

- `raw_json_config`

Paste a complete PicoClaw JSON object into that field.

The wrapper will then:

- validate the JSON with `jq`
- reject empty input
- require a JSON object
- seed `/share/picoclaw/workspace/config.full.json` if it does not exist yet
- normalize the effective shared config on every boot
- force `agents.defaults.workspace` to `/share/picoclaw/workspace`
- auto-enable HA-safe file and skill tools if they are absent from the JSON:
  `skills`, `find_skills`, `install_skill`, `list_dir`, `read_file`, `write_file`, `append_file`, `edit_file`

If the add-on fails to start, check the logs first. The wrapper is designed to fail fast with a clear config error instead of silently starting with a broken runtime.

Starter example:

- [`examples/raw_json_config.example.json`](examples/raw_json_config.example.json)

## Storage Contract

User-editable workspace:

- `/share/picoclaw/workspace`
- `/share/picoclaw/workspace/config.full.json`
- `/share/picoclaw/workspace/launcher-config.json`

Internal runtime state:

- `/data/picoclaw/.security.yml`
- `/data/picoclaw/config.json -> /share/picoclaw/workspace/config.full.json`
- `/data/picoclaw/launcher-config.json -> /share/picoclaw/workspace/launcher-config.json`
- `/data/picoclaw/logs`
- `/data/picoclaw/workspace -> /share/picoclaw/workspace`

Important: `/share` was chosen for editability from File Editor and Samba, not for the strongest encapsulated backup semantics. Runtime state still lives in `/data`.

What to expect in the shared workspace after PicoClaw initializes:

- `AGENT.md`
- `USER.md`
- `HEARTBEAT.md`
- `TOOLS.md`
- `TOOLS.injected.json`
- `SOUL.md`
- `memory/`
- `skills/`
- `config.full.json`

Runtime-created folders such as `sessions/`, `state/`, and `cron/` appear as the agent starts working.

If you inspect `/data/picoclaw/workspace`, that path should resolve to the same shared workspace through a symlink. The reference location to check from Home Assistant is always `/share/picoclaw/workspace`.

Builtin skills shipped by upstream are copied into `/share/picoclaw/workspace/skills` on first boot. This makes them visible from Home Assistant File Editor and allows you to disable one by deleting its folder from the shared workspace.

The wrapper also bootstraps top-level workspace files into `/share/picoclaw/workspace`. Upstream provides files such as `AGENT.md`, `USER.md`, and `SOUL.md`; the Home Assistant wrapper additionally ensures `TOOLS.md`, `TOOLS.injected.json`, and `HEARTBEAT.md` are present even when upstream did not pre-create them.

Use them like this:

- `TOOLS.md`: your custom tool-usage instructions for the system prompt
- `TOOLS.injected.json`: the exact tools currently visible to the LLM, including names, descriptions, and JSON Schemas

## Backups

Home Assistant backups store add-on data from two separate locations. Both must be included to get a complete PicoClaw backup.

### What lives where

| Path | Backup option | Contents |
|------|--------------|----------|
| `/data/picoclaw/` | **Add-on data** (included when PicoClaw is checked in the backup) | `.security.yml` (API keys and secrets), workspace symlink, template markers, logs |
| `/share/picoclaw/` | **Share folder** (separate checkbox in backup settings) | The entire workspace: `config.full.json`, `AGENT.md`, `USER.md`, `HEARTBEAT.md`, conversation sessions, long-term memory, skills, cron jobs |

### Important

The Share folder contains everything that makes your agent unique: its configuration, personality, conversation history, memory, and skills. If you only back up the add-on data without the Share folder, you lose all of that and only keep the secrets file.

Always enable **both**:

1. Check **PicoClaw** in the add-on list when creating a backup.
2. Check **Share** in the folder list.

### Restoring

After restoring a backup:

1. The wrapper re-creates symlinks and runtime directories automatically on startup.
2. `.security.yml` is restored from `/data/picoclaw/`, so API keys are preserved.
3. The workspace in `/share/picoclaw/workspace/` is restored as-is, including sessions and memory.
4. No manual steps are needed. Start the add-on normally.

## Configuration Contract

This add-on exposes one option only:

- `raw_json_config`

Rules:

- it must be valid JSON
- it must parse to a JSON object
- if `/share/picoclaw/workspace/config.full.json` is missing, the wrapper seeds it from `raw_json_config`
- on every boot, the wrapper normalizes `/share/picoclaw/workspace/config.full.json`
- sensitive values are kept in `/data/picoclaw/.security.yml`, not in `config.full.json`
- on every boot, the wrapper forces `agents.defaults.workspace` to `/share/picoclaw/workspace`
- if the HA-safe file and skill tools are absent, the wrapper injects them automatically

Empty or invalid JSON fails fast before PicoClaw starts.

## Minimal Example

```json
{
  "agents": {
    "defaults": {
      "model_name": "gpt-5.4",
      "restrict_to_workspace": true
    }
  },
  "model_list": [
    {
      "model_name": "gpt-5.4",
      "model": "openai/gpt-5.4",
      "api_key": "sk-your-openai-key",
      "api_base": "https://api.openai.com/v1"
    }
  ],
  "tools": {
    "exec": {
      "enabled": true,
      "enable_deny_patterns": true
    },
    "skills": {
      "enabled": true
    },
    "find_skills": {
      "enabled": true
    },
    "install_skill": {
      "enabled": true
    },
    "list_dir": {
      "enabled": true
    },
    "read_file": {
      "enabled": true
    },
    "write_file": {
      "enabled": true
    },
    "append_file": {
      "enabled": true
    },
    "edit_file": {
      "enabled": true
    },
    "web": {
      "enabled": true
    },
    "mcp": {
      "enabled": false,
      "servers": {
        "home-assistant": {
          "enabled": false,
          "type": "http",
          "url": "http://homeassistant:8123/api/mcp",
          "headers": {
            "Authorization": "Bearer YOUR_LONG_LIVED_ACCESS_TOKEN"
          }
        }
      }
    }
  },
  "gateway": {
    "log_level": "debug"
  }
}
```

The MCP block is optional. Startup succeeds even when MCP is absent.
The wrapper will still inject the same file and skill tools when they are missing, so this example is more explicit than strictly required.

## Accessing the UI

The main UI is the upstream web launcher:

- Home Assistant Ingress -> `picoclaw-launcher`

Typical flow:

1. Start the add-on.
2. Open the add-on page.
3. Click `Open Web UI`.
4. Optionally enable the Home Assistant sidebar entry for direct access.

No host port mapping is required by default. The add-on is designed to be used through Home Assistant Ingress.
The `http://<host>:18800/` URL is not part of the supported Home Assistant contract unless you intentionally expose a host port yourself.

Home Assistant background on Ingress:
[Presenting your addon](https://developers.home-assistant.io/docs/add-ons/presentation)

Why `:18800` is not the supported access path in HA:

- Home Assistant already proxies the add-on UI through Ingress
- the add-on manifest does not publish a host port
- the launcher is now patched to understand the Home Assistant Ingress base path directly
- using Ingress keeps the add-on aligned with the normal Home Assistant UX and permission model

## Optional `.security.yml`

If `/share/picoclaw/.security.yml` exists, the wrapper still copies it to `/data/picoclaw/.security.yml` during startup for backward compatibility.

This keeps compatibility with upstream secret separation without adding a second Home Assistant config surface in v1.

If `/share/picoclaw/config.override.json` exists, the wrapper ignores it intentionally in v1 to avoid split-brain configuration.

## Home Assistant UI

Primary UI:

- Home Assistant Ingress -> `picoclaw-launcher`

Power-user shell tool:

- `picoclaw-launcher-tui`

The TUI is installed in the image and available from an interactive shell into the add-on container, but it is not embedded into the Home Assistant frontend.

## English-First Behavior

The wrapper forces an English-first launcher experience by:

- starting the launcher with `-lang en`
- setting container locale variables to English
- applying a tiny upstream patch set so the web launcher defaults to English and avoids mixed Chinese labels in the default UI

Chinese localization support is still present upstream; the wrapper only changes the default presentation.

## Security Notes

- raw JSON in Home Assistant options may contain secrets
- v1 optimizes for a single configuration field, not for maximum secret isolation
- upstream `.security.yml` compatibility is preserved for future hardening
- no host ports are exposed by default
- the add-on uses Home Assistant Ingress and `share:rw` only

## Shell Access

Useful commands inside the container:

```sh
picoclaw-launcher-tui /data/picoclaw/config.json
picoclaw gateway
picoclaw agent -m "hello"
```

The add-on runtime always launches the web launcher in the foreground. Running commands manually is only for troubleshooting.

## Gateway Log Levels

The wrapper defaults `gateway.log_level` to `info` if not set.

Set the level in `/share/picoclaw/workspace/config.full.json` or in the HA `raw_json_config` option:

```json
{
  "gateway": {
    "log_level": "info"
  }
}
```

### What each level shows

| Level | What you see |
|-------|-------------|
| **info** (default) | Message routed, tool calls requested, tool execution with arguments preview, agent response preview, outbound message published, model routing decisions, heartbeat start/stop, steering events |
| **debug** | Everything from `info`, plus: full LLM request/response payloads, heartbeat execution details, tool results sent to user, model routing internals, message bus diagnostics |
| **warn** | Only warnings and errors: failed tool calls, context compression issues, steering failures, hook errors |

### Recommended usage

- **`info`**: day-to-day monitoring. Shows the full agent flow (message in -> tool calls -> response out) without overwhelming volume.
- **`debug`**: troubleshooting only. Includes raw LLM payloads which can be very large. Use temporarily when diagnosing a specific issue.

### Extra behavior when `debug` is set

In the Home Assistant wrapper, `gateway.log_level = "debug"` has an extra meaning:

- it starts `picoclaw gateway` with `-d --no-truncate`
- launcher and gateway logs are relayed into the add-on console logs
- the wrapper still suppresses the recurring `Gateway health status: 200` noise line
- inline tool feedback messages are still hidden in Telegram chats even though tool calls remain visible in the add-on logs

### Recommended debug flow

1. Set `gateway.log_level` to `debug`.
2. Restart the add-on.
3. Open the UI through `Open Web UI`.
4. Check `/share/picoclaw/workspace` for the generated workspace files.
5. Inspect the add-on logs for detailed gateway activity.

## Recommended Upstream Reading

If you want to go beyond the wrapper and tune PicoClaw itself, these are the best official references:

- PicoClaw docs homepage:
  [docs.picoclaw.io](https://docs.picoclaw.io/)
- Quick overview and launcher behavior:
  [Getting Started](https://docs.picoclaw.io/docs/getting-started/)
- Full JSON field reference:
  [Full Configuration Reference](https://docs.picoclaw.io/docs/configuration/config-reference/)
- Model providers and `model_list`:
  [Model Configuration](https://docs.picoclaw.io/docs/configuration/model-list/)
- Tools, exec, web, cron, and MCP:
  [Tools Configuration](https://docs.picoclaw.io/docs/configuration/tools/)
- Workspace restrictions and sandbox defaults:
  [Security Sandbox](https://docs.picoclaw.io/docs/configuration/security-sandbox/)

For Home Assistant internals and network behavior between add-ons:

- [Add-on communication](https://developers.home-assistant.io/docs/add-ons/communication/)
