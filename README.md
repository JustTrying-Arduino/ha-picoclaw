# PicoClaw for Home Assistant

Bring the official [PicoClaw](https://github.com/sipeed/picoclaw) experience into Home Assistant without turning this repository into a long-lived fork.

This project rebuilds PicoClaw as a thin Home Assistant add-on wrapper around the official `sipeed/picoclaw` release tags. The goal is simple:

- keep PicoClaw itself upstream
- make it feel natural inside Home Assistant
- expose a real editable workspace
- keep the wrapper small enough to survive upstream changes

## Why This Repository Exists

PicoClaw is an ambitious personal AI agent project with its own launcher, gateway, workspace model, and fast-moving runtime. Home Assistant users want that power too, but with Home Assistant ergonomics:

- installable as a normal add-on
- reachable from the sidebar through Ingress
- editable from File Editor or Samba
- persistent across restarts
- updateable through a predictable HA release flow

This repository is the bridge between those two worlds.

## The HA <-> PicoClaw Link

Home Assistant is the host and UX shell.
PicoClaw is the actual agent runtime.

This repo does not try to reimplement PicoClaw logic. Instead, it adapts the official upstream release into a Home Assistant add-on contract:

- Home Assistant owns add-on packaging, startup, storage mapping, ingress, and updates
- PicoClaw owns agent behavior, launcher behavior, gateway behavior, models, tools, and runtime semantics

That split is intentional. The thinner the wrapper stays, the easier it is to track upstream safely.

## Source of Truth

The source of PicoClaw in this repository is the official upstream project:

- Upstream repo: [sipeed/picoclaw](https://github.com/sipeed/picoclaw)
- Upstream releases: [GitHub Releases](https://github.com/sipeed/picoclaw/releases)

This repository follows upstream release tags only. It does not track `main`, does not vendor the entire upstream repository, and does not depend on random community images.

## What Has Been Implemented Here

The repository now contains a full Home Assistant add-on rebuild in [`picoclaw/`](picoclaw/):

- `repository.yaml` so Home Assistant can consume the repository
- a real add-on manifest, Dockerfile, startup script, docs, translations, icon, and logo
- build logic that compiles `picoclaw`, `picoclaw-launcher`, and `picoclaw-launcher-tui` from an official upstream tag
- a split storage model:
  `/share/picoclaw/workspace` for user files
  `/data/picoclaw` for runtime state
- a single Home Assistant option:
  `raw_json_config`
- startup validation that rejects invalid JSON early and writes the normalized config to `/data/picoclaw/config.json`
- a deterministic workspace contract that always forces PicoClaw onto `/share/picoclaw/workspace`
- HA-safe file and skill tools injected by default when the user config omits them
- Home Assistant Ingress as the primary UI via `picoclaw-launcher`
- English-first launcher defaults with a very small HA-specific patch set
- optional `.security.yml` compatibility without making it mandatory for first boot
- GitHub Actions for CI, image publishing, and upstream release tracking

## Install in Home Assistant

1. Open Home Assistant and go to the add-on store.
   On recent versions this is usually `Settings -> Add-ons -> Add-on Store`.
2. Add this repository as a custom add-on repository:
   `https://github.com/JustTrying-Arduino/ha-picoclaw`
3. Refresh the store, open `PicoClaw`, and install it.
4. After install, open the add-on configuration and fill `raw_json_config`.
5. Start the add-on.
6. Open the UI with the add-on's `Open Web UI` button or through the Home Assistant sidebar entry exposed by Ingress.

By default, Home Assistant can build the add-on image directly from this repository's `Dockerfile`. That is useful while GHCR publication is not set up yet or if the registry package is still private.

The Home Assistant developer docs explain the custom repository flow here:
[Create an app repository](https://developers.home-assistant.io/docs/add-ons/repository).

## Configure It

This add-on intentionally exposes one Home Assistant option only:

- `raw_json_config`

You paste the full PicoClaw JSON configuration into that field, and the wrapper will:

- validate that it is valid JSON
- require it to be a JSON object
- write it to `/data/picoclaw/config.json`
- force `agents.defaults.workspace` to `/share/picoclaw/workspace`

That means Home Assistant remains the config entry point, while PicoClaw keeps its native JSON config model.

The wrapper also injects the core file and skill tools Home Assistant users expect when they are absent from the raw JSON, so a minimal config still results in a usable workspace-aware agent.

If you want a quick starting point, use:

- [`picoclaw/examples/raw_json_config.example.json`](picoclaw/examples/raw_json_config.example.json)

If you want the full operational details, read:

- [`picoclaw/DOCS.md`](picoclaw/DOCS.md)

## Access the UI

The primary interface is the upstream `picoclaw-launcher`, exposed through Home Assistant Ingress.

In practice:

- start the add-on
- click `Open Web UI` from the add-on page
- optionally pin the add-on in the Home Assistant sidebar for direct access

This repository does not expose host ports by default. Home Assistant handles the embedded UI path through Ingress, which is exactly the experience add-ons are meant to provide.
The launcher should be treated as an Ingress app first. `http://<host>:18800/` is not part of the stable add-on contract unless a host port is explicitly published later.

Background on Ingress:
[Presenting your addon](https://developers.home-assistant.io/docs/add-ons/presentation)

## Where Files Live

Editable workspace:

- `/share/picoclaw/workspace`

Runtime state:

- `/data/picoclaw/config.json`
- `/data/picoclaw/.security.yml`
- `/data/picoclaw/launcher-config.json`
- `/data/picoclaw/logs`

This split is deliberate:

- `/share` is for files you want to edit from File Editor or Samba
- `/data` is for runtime state the add-on should keep to itself

Once PicoClaw has initialized, the shared workspace should contain files such as `USER.md`, `HEARTBEAT.md`, `AGENTS.md`, `IDENTITY.md`, `SOUL.md`, plus `skills/`, `memory/`, `sessions/`, and `state/`.

For troubleshooting, you can enable detailed gateway logging with:

```json
{
  "gateway": {
    "log_level": "debug"
  }
}
```

In this wrapper that does two things at once:

- it sets the upstream gateway log level to `debug`
- it makes the launcher start the gateway with `-d --no-truncate`, so detailed logs also appear in the Home Assistant add-on logs

## Good Sources for Going Further

For Home Assistant:

- Custom add-on repositories:
  [Home Assistant Developer Docs](https://developers.home-assistant.io/docs/add-ons/repository)
- Add-on presentation and Ingress:
  [Home Assistant Developer Docs](https://developers.home-assistant.io/docs/add-ons/presentation)
- Add-on communication on the internal HA network:
  [Home Assistant Developer Docs](https://developers.home-assistant.io/docs/add-ons/communication/)

For PicoClaw itself:

- Project home:
  [docs.picoclaw.io](https://docs.picoclaw.io/)
- Getting started:
  [Getting Started](https://docs.picoclaw.io/docs/getting-started/)
- Full JSON reference:
  [Full Configuration Reference](https://docs.picoclaw.io/docs/configuration/config-reference/)
- Model configuration:
  [Model Configuration](https://docs.picoclaw.io/docs/configuration/model-list/)
- Tools and MCP:
  [Tools Configuration](https://docs.picoclaw.io/docs/configuration/tools/)
- Sandbox behavior:
  [Security Sandbox](https://docs.picoclaw.io/docs/configuration/security-sandbox/)

## Design Philosophy

This is a wrapper, not a fork.

That means HA-specific behavior lives here:

- filesystem layout
- validation and startup
- ingress compatibility
- release automation
- polish for HA users

And PicoClaw-specific behavior stays upstream:

- launcher internals
- gateway internals
- model behavior
- tools, MCP, and channel runtime
- rapid feature evolution

## Why It Should Feel Better in Home Assistant

The add-on is built around the practical pain points Home Assistant users hit first:

- the workspace is visible in `/share`, so editing files is easy
- runtime clutter stays under `/data`
- the launcher opens through Ingress instead of asking users to manage host ports
- the config surface stays minimal instead of exploding into dozens of HA-specific knobs
- upstream compatibility stays high because the wrapper keeps its patch set small

## Repository Layout

- [`picoclaw/`](picoclaw/) contains the add-on
- [`picoclaw/DOCS.md`](picoclaw/DOCS.md) contains the operational contract
- [`.github/workflows/`](.github/workflows/) contains CI, publishing, and upstream-sync automation
- [`scripts/set-version.sh`](scripts/set-version.sh) updates the wrapper version to follow a new upstream tag

## Current Positioning

If you want the official PicoClaw runtime, but with a Home Assistant-native install and workflow, that is exactly what this repository is for.

If you want a deep PicoClaw fork with HA-specific runtime features welded into the agent itself, that is intentionally not what this repository does.
