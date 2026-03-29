# PicoClaw

Run the official PicoClaw launcher and gateway inside Home Assistant with a wrapper that stays close to upstream.

This add-on is designed for people who want PicoClaw to feel native in Home Assistant without rewriting PicoClaw itself.

## What You Get

- the official `sipeed/picoclaw` runtime built from release tags
- Home Assistant Ingress as the main UI through `picoclaw-launcher`
- an editable workspace at `/share/picoclaw/workspace`
- runtime state isolated under `/data/picoclaw`
- one Home Assistant option only: `raw_json_config`
- HA-safe file and skill tools auto-enabled when missing from the JSON
- `picoclaw-launcher-tui` included for shell troubleshooting

## Why This Add-on Exists

PicoClaw already has its own launcher, runtime model, and configuration system. Home Assistant already has its own add-on UX, storage model, and update flow.

This add-on is the glue:

- Home Assistant handles install, persistence, ingress, and repository updates
- PicoClaw stays the upstream engine

## Wrapper Responsibilities

This add-on owns only the Home Assistant side:

- storage layout
- config validation
- ingress compatibility
- English-first defaults
- release tracking and packaging

It does not try to become a permanent PicoClaw fork.

## Official Source

- Upstream project: [sipeed/picoclaw](https://github.com/sipeed/picoclaw)
- Add-on docs: [DOCS.md](DOCS.md)

Use this add-on when you want PicoClaw in Home Assistant, but still want upstream to remain the source of truth for PicoClaw itself.

## Install in Home Assistant

1. Open the Home Assistant add-on store.
2. Add this repository as a custom repository:
   `https://github.com/JustTrying-Arduino/ha-picoclaw`
3. Install `PicoClaw`.
4. Paste your PicoClaw JSON into `raw_json_config`.
5. Start the add-on.
6. Open it with `Open Web UI`.

If prebuilt registry images are not available yet, Home Assistant can build the add-on locally from the repository Dockerfile.
Use Home Assistant Ingress as the supported UI path. `:18800` is not considered a stable host URL unless you explicitly publish that port yourself.

## Configure It

The add-on uses one Home Assistant option only:

- `raw_json_config`

The wrapper always forces the workspace to `/share/picoclaw/workspace` and injects safe file/skill defaults if those tool blocks are absent.

Use the example config here:

- [`examples/raw_json_config.example.json`](examples/raw_json_config.example.json)

Read the full add-on usage guide here:

- [DOCS.md](DOCS.md)

For verbose troubleshooting, add this to your JSON and restart the add-on:

```json
{
  "gateway": {
    "log_level": "debug"
  }
}
```

## Learn More

- PicoClaw docs: [docs.picoclaw.io](https://docs.picoclaw.io/)
- PicoClaw full config reference: [Configuration Reference](https://docs.picoclaw.io/docs/configuration/config-reference/)
- PicoClaw model configuration: [Model Configuration](https://docs.picoclaw.io/docs/configuration/model-list/)
- PicoClaw tools and MCP: [Tools Configuration](https://docs.picoclaw.io/docs/configuration/tools/)
