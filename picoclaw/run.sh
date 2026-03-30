#!/usr/bin/with-contenv bashio
set -euo pipefail

readonly SHARE_ROOT="/share/picoclaw"
readonly SHARED_WORKSPACE="${SHARE_ROOT}/workspace"
readonly SHARED_CONFIG="${SHARED_WORKSPACE}/config.full.json"
readonly SHARED_LAUNCHER_CONFIG="${SHARED_WORKSPACE}/launcher-config.json"
readonly SHARED_SECURITY_FILE="${SHARE_ROOT}/.security.yml"
readonly SHARED_IGNORED_OVERRIDE="${SHARE_ROOT}/config.override.json"

readonly RUNTIME_HOME="/data/picoclaw"
readonly RUNTIME_CONFIG="${RUNTIME_HOME}/config.json"
readonly RUNTIME_SECURITY_FILE="${RUNTIME_HOME}/.security.yml"
readonly RUNTIME_LAUNCHER_CONFIG="${RUNTIME_HOME}/launcher-config.json"
readonly RUNTIME_WORKSPACE_LINK="${RUNTIME_HOME}/workspace"
readonly RUNTIME_WORKSPACE_TEMPLATES_MARKER="${RUNTIME_HOME}/.workspace-templates-bootstrapped"

readonly WORKSPACE_TEMPLATES_SOURCE="/usr/local/share/picoclaw/workspace"

readonly PICOCLAW_UID="1000"
readonly PICOCLAW_GID="1000"

fail() {
    bashio::log.fatal "$1"
    exit 1
}

realpath_safe() {
    if readlink -f "$1" >/dev/null 2>&1; then
        readlink -f "$1"
        return
    fi

    if realpath "$1" >/dev/null 2>&1; then
        realpath "$1"
        return
    fi

    printf '%s\n' "$1"
}

directory_has_entries() {
    find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
}

count_top_level_entries() {
    find "$1" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l | tr -d ' '
}

ensure_directories() {
    mkdir -p "${SHARE_ROOT}" "${SHARED_WORKSPACE}" "${RUNTIME_HOME}"
    chown -R "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARE_ROOT}" "${RUNTIME_HOME}"
}

migrate_legacy_runtime_workspace() {
    if [ -d "${RUNTIME_WORKSPACE_LINK}" ] && [ ! -L "${RUNTIME_WORKSPACE_LINK}" ]; then
        bashio::log.warning "Found legacy runtime workspace directory at ${RUNTIME_WORKSPACE_LINK}. Migrating it into ${SHARED_WORKSPACE}."

        if directory_has_entries "${RUNTIME_WORKSPACE_LINK}"; then
            cp -a "${RUNTIME_WORKSPACE_LINK}/." "${SHARED_WORKSPACE}/"
            bashio::log.info "Copied legacy runtime workspace content into ${SHARED_WORKSPACE}"
        fi

        rm -rf "${RUNTIME_WORKSPACE_LINK}"
    fi
}

ensure_workspace_symlink() {
    migrate_legacy_runtime_workspace

    if [ -L "${RUNTIME_WORKSPACE_LINK}" ]; then
        local current_target
        current_target="$(readlink "${RUNTIME_WORKSPACE_LINK}")"
        if [ "${current_target}" != "${SHARED_WORKSPACE}" ]; then
            rm -f "${RUNTIME_WORKSPACE_LINK}"
            ln -s "${SHARED_WORKSPACE}" "${RUNTIME_WORKSPACE_LINK}"
        fi
        return
    fi

    if [ -e "${RUNTIME_WORKSPACE_LINK}" ]; then
        fail "Expected ${RUNTIME_WORKSPACE_LINK} to be a symlink to ${SHARED_WORKSPACE}, but another file already exists there."
    fi

    ln -s "${SHARED_WORKSPACE}" "${RUNTIME_WORKSPACE_LINK}"
}

ensure_runtime_file_link() {
    local link_path target_path label current_target

    link_path="$1"
    target_path="$2"
    label="$3"

    if [ -L "${link_path}" ]; then
        current_target="$(readlink "${link_path}")"
        if [ "${current_target}" != "${target_path}" ]; then
            rm -f "${link_path}"
            ln -s "${target_path}" "${link_path}"
        fi
        return
    fi

    if [ -e "${link_path}" ]; then
        rm -f "${link_path}"
        bashio::log.info "Replaced legacy runtime ${label} at ${link_path} with a symlink to ${target_path}"
    fi

    ln -s "${target_path}" "${link_path}"
}

ensure_runtime_config_links() {
    ensure_runtime_file_link "${RUNTIME_CONFIG}" "${SHARED_CONFIG}" "config file"
    ensure_runtime_file_link "${RUNTIME_LAUNCHER_CONFIG}" "${SHARED_LAUNCHER_CONFIG}" "launcher config file"
}

bootstrap_workspace_templates() {
    local copied_count source_path relative_path target_path

    if [ -f "${RUNTIME_WORKSPACE_TEMPLATES_MARKER}" ]; then
        return
    fi

    if [ ! -d "${WORKSPACE_TEMPLATES_SOURCE}" ]; then
        bashio::log.warning "Workspace templates source ${WORKSPACE_TEMPLATES_SOURCE} is missing."
        return
    fi

    copied_count=0

    while IFS= read -r source_path; do
        relative_path="${source_path#${WORKSPACE_TEMPLATES_SOURCE}/}"
        target_path="${SHARED_WORKSPACE}/${relative_path}"

        if [ -d "${source_path}" ]; then
            mkdir -p "${target_path}"
            continue
        fi

        if [ -e "${target_path}" ]; then
            continue
        fi

        mkdir -p "$(dirname "${target_path}")"
        cp -a "${source_path}" "${target_path}"
        copied_count=$((copied_count + 1))
    done < <(find "${WORKSPACE_TEMPLATES_SOURCE}" -mindepth 1 | sort)

    touch "${RUNTIME_WORKSPACE_TEMPLATES_MARKER}"
    chown -R "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARED_WORKSPACE}" "${RUNTIME_WORKSPACE_TEMPLATES_MARKER}"
    bashio::log.info "Bootstrapped ${copied_count} workspace template file(s) into ${SHARED_WORKSPACE}"
}

bootstrap_wrapper_workspace_files() {
    if [ ! -e "${SHARED_WORKSPACE}/TOOLS.md" ]; then
        cat > "${SHARED_WORKSPACE}/TOOLS.md" <<'EOF'
# Tool Preferences

Use this file to customize how the agent should use tools in this workspace.

## Example preferences

- Prefer asking before destructive actions.
- Explain risky commands briefly before running them.
- Keep tool usage concise unless the user explicitly asks for detail.
- Prefer editing files inside the workspace over writing elsewhere.

## Your tool instructions

Add your tool-specific preferences below this line.
EOF
        chmod 644 "${SHARED_WORKSPACE}/TOOLS.md"
        chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARED_WORKSPACE}/TOOLS.md"
        bashio::log.info "Created workspace template ${SHARED_WORKSPACE}/TOOLS.md"
    fi

    if [ ! -e "${SHARED_WORKSPACE}/HEARTBEAT.md" ]; then
        cat > "${SHARED_WORKSPACE}/HEARTBEAT.md" <<'EOF'
# Heartbeat Check List

This file contains tasks for the heartbeat service to check periodically.

## Examples

- Check for unread messages
- Review upcoming calendar events
- Check device status

## Instructions

- Execute ALL tasks listed below. Do NOT skip any task.
- For simple tasks, respond directly.
- For complex tasks that may take time, use the spawn tool to create a subagent.
- The spawn tool is async - subagent results will be sent to the user automatically.
- After spawning a subagent, CONTINUE to process remaining tasks.
- Only respond with HEARTBEAT_OK when ALL tasks are done AND nothing needs attention.

---

Add your heartbeat tasks below this line:
EOF
        chmod 644 "${SHARED_WORKSPACE}/HEARTBEAT.md"
        chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARED_WORKSPACE}/HEARTBEAT.md"
        bashio::log.info "Created workspace template ${SHARED_WORKSPACE}/HEARTBEAT.md"
    fi
}

log_workspace_diagnostics() {
    local runtime_realpath shared_realpath symlink_target top_level_entries config_realpath launcher_realpath

    runtime_realpath="$(realpath_safe "${RUNTIME_WORKSPACE_LINK}")"
    shared_realpath="$(realpath_safe "${SHARED_WORKSPACE}")"
    config_realpath="$(realpath_safe "${RUNTIME_CONFIG}")"
    launcher_realpath="$(realpath_safe "${RUNTIME_LAUNCHER_CONFIG}")"
    symlink_target="$(readlink "${RUNTIME_WORKSPACE_LINK}" 2>/dev/null || printf '<missing>')"
    top_level_entries="$(count_top_level_entries "${SHARED_WORKSPACE}")"

    bashio::log.info "Shared workspace path: ${SHARED_WORKSPACE}"
    bashio::log.info "Runtime workspace path: ${RUNTIME_WORKSPACE_LINK}"
    bashio::log.info "Runtime workspace symlink target: ${symlink_target}"
    bashio::log.info "Runtime workspace realpath: ${runtime_realpath}"

    if [ "${runtime_realpath}" = "${shared_realpath}" ]; then
        bashio::log.info "Runtime workspace link is valid and resolves to the shared workspace."
    else
        bashio::log.warning "Runtime workspace path does not resolve to the shared workspace. Check ${RUNTIME_WORKSPACE_LINK} and ${SHARED_WORKSPACE}."
    fi

    bashio::log.info "Shared workspace top-level entries: ${top_level_entries}"
    bashio::log.info "Shared config path: ${SHARED_CONFIG}"
    bashio::log.info "Runtime config path: ${RUNTIME_CONFIG}"
    bashio::log.info "Runtime config realpath: ${config_realpath}"
    bashio::log.info "Shared launcher config path: ${SHARED_LAUNCHER_CONFIG}"
    bashio::log.info "Runtime launcher config realpath: ${launcher_realpath}"
}

copy_optional_security_file() {
    if [ -f "${SHARED_SECURITY_FILE}" ]; then
        install -m 600 -o "${PICOCLAW_UID}" -g "${PICOCLAW_GID}" "${SHARED_SECURITY_FILE}" "${RUNTIME_SECURITY_FILE}"
        bashio::log.info "Loaded optional security data from ${SHARED_SECURITY_FILE}"
    fi

    if [ -f "${SHARED_IGNORED_OVERRIDE}" ]; then
        bashio::log.warning "Ignoring ${SHARED_IGNORED_OVERRIDE}; use ${SHARED_CONFIG} as the editable shared config file instead."
    fi
}

write_launcher_config() {
    cat > "${SHARED_LAUNCHER_CONFIG}" <<'EOF'
{
  "port": 18800,
  "public": true
}
EOF
    chmod 600 "${SHARED_LAUNCHER_CONFIG}"
    chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARED_LAUNCHER_CONFIG}"
}

normalize_config_json() {
    jq --sort-keys --arg workspace "${SHARED_WORKSPACE}" '
        def scrub_secrets:
            del(
                .model_list[]?.api_key,
                .model_list[]?.api_keys,
                .channels.telegram.token,
                .channels.feishu.app_secret,
                .channels.feishu.encrypt_key,
                .channels.feishu.verification_token,
                .channels.discord.token,
                .channels.weixin.token,
                .channels.qq.app_secret,
                .channels.dingtalk.client_secret,
                .channels.slack.bot_token,
                .channels.slack.app_token,
                .channels.matrix.access_token,
                .channels.line.channel_secret,
                .channels.line.channel_access_token,
                .channels.onebot.access_token,
                .channels.wecom.secret,
                .channels.pico.token,
                .channels.irc.password,
                .channels.irc.nickserv_password,
                .channels.irc.sasl_password,
                .tools.web.brave.api_key,
                .tools.web.brave.api_keys,
                .tools.web.tavily.api_key,
                .tools.web.tavily.api_keys,
                .tools.web.perplexity.api_key,
                .tools.web.perplexity.api_keys,
                .tools.web.glm_search.api_key,
                .tools.web.baidu_search.api_key,
                .tools.skills.github.token,
                .tools.skills.registries.clawhub.auth_token
            );
        def ensure_enabled(path):
            if getpath(path) == null then setpath(path; true) else . end;
        def ensure_default(path; value):
            if getpath(path) == null or getpath(path) == "" then setpath(path; value) else . end;
        def ensure_default_port(path; value):
            if getpath(path) == null or getpath(path) == 0 then setpath(path; value) else . end;
        scrub_secrets |
        .version = 1 |
        .agents = (.agents // {}) |
        .agents.defaults = (.agents.defaults // {}) |
        .gateway = (.gateway // {}) |
        .tools = (.tools // {}) |
        .tools.web = (.tools.web // {}) |
        .agents.defaults.workspace = $workspace |
        ensure_default(["gateway", "host"]; "127.0.0.1") |
        ensure_default_port(["gateway", "port"]; 18790) |
        if .tools.web.prefer_native == null then .tools.web.prefer_native = false else . end |
        ensure_enabled(["tools", "skills", "enabled"]) |
        ensure_enabled(["tools", "find_skills", "enabled"]) |
        ensure_enabled(["tools", "install_skill", "enabled"]) |
        ensure_enabled(["tools", "list_dir", "enabled"]) |
        ensure_enabled(["tools", "read_file", "enabled"]) |
        ensure_enabled(["tools", "write_file", "enabled"]) |
        ensure_enabled(["tools", "append_file", "enabled"]) |
        ensure_enabled(["tools", "edit_file", "enabled"])
    '
}

extract_embedded_security_json() {
    jq --sort-keys '
        def prune:
            if type == "object" then
                with_entries(.value |= prune) |
                with_entries(select(.value != null and .value != {} and .value != [] and .value != ""))
            elif type == "array" then
                map(prune) | map(select(. != null and . != ""))
            else
                .
            end;
        def first_key_array:
            if . == null then []
            elif type == "array" then map(select(type == "string" and . != ""))
            elif type == "string" and . != "" then [.]
            else []
            end;
        def model_keys(model):
            (model.api_keys // model.api_key // null) | first_key_array;
        {
            "model_list": (
                reduce (.model_list // [])[] as $model ({};
                    ($model.model_name // "") as $model_name |
                    (model_keys($model)) as $keys |
                    if $model_name == "" or ($keys | length) == 0 then
                        .
                    else
                        . + {($model_name): {"api_keys": $keys}}
                    end
                )
            ),
            "channels": {
                "telegram": (if (.channels.telegram.token? // "") != "" then {"token": .channels.telegram.token} else null end),
                "feishu": (
                    if (.channels.feishu.app_secret? // "") != "" or (.channels.feishu.encrypt_key? // "") != "" or (.channels.feishu.verification_token? // "") != "" then
                        {
                            "app_secret": .channels.feishu.app_secret,
                            "encrypt_key": .channels.feishu.encrypt_key,
                            "verification_token": .channels.feishu.verification_token
                        }
                    else
                        null
                    end
                ),
                "discord": (if (.channels.discord.token? // "") != "" then {"token": .channels.discord.token} else null end),
                "weixin": (if (.channels.weixin.token? // "") != "" then {"token": .channels.weixin.token} else null end),
                "qq": (if (.channels.qq.app_secret? // "") != "" then {"app_secret": .channels.qq.app_secret} else null end),
                "dingtalk": (if (.channels.dingtalk.client_secret? // "") != "" then {"client_secret": .channels.dingtalk.client_secret} else null end),
                "slack": (
                    if (.channels.slack.bot_token? // "") != "" or (.channels.slack.app_token? // "") != "" then
                        {
                            "bot_token": .channels.slack.bot_token,
                            "app_token": .channels.slack.app_token
                        }
                    else
                        null
                    end
                ),
                "matrix": (if (.channels.matrix.access_token? // "") != "" then {"access_token": .channels.matrix.access_token} else null end),
                "line": (
                    if (.channels.line.channel_secret? // "") != "" or (.channels.line.channel_access_token? // "") != "" then
                        {
                            "channel_secret": .channels.line.channel_secret,
                            "channel_access_token": .channels.line.channel_access_token
                        }
                    else
                        null
                    end
                ),
                "onebot": (if (.channels.onebot.access_token? // "") != "" then {"access_token": .channels.onebot.access_token} else null end),
                "wecom": (if (.channels.wecom.secret? // "") != "" then {"secret": .channels.wecom.secret} else null end),
                "pico": (if (.channels.pico.token? // "") != "" then {"token": .channels.pico.token} else null end),
                "irc": (
                    if (.channels.irc.password? // "") != "" or (.channels.irc.nickserv_password? // "") != "" or (.channels.irc.sasl_password? // "") != "" then
                        {
                            "password": .channels.irc.password,
                            "nickserv_password": .channels.irc.nickserv_password,
                            "sasl_password": .channels.irc.sasl_password
                        }
                    else
                        null
                    end
                )
            },
            "web": {
                "brave": (
                    ((.tools.web.brave.api_keys // .tools.web.brave.api_key // null) | first_key_array) as $keys |
                    if ($keys | length) > 0 then {"api_keys": $keys} else null end
                ),
                "tavily": (
                    ((.tools.web.tavily.api_keys // .tools.web.tavily.api_key // null) | first_key_array) as $keys |
                    if ($keys | length) > 0 then {"api_keys": $keys} else null end
                ),
                "perplexity": (
                    ((.tools.web.perplexity.api_keys // .tools.web.perplexity.api_key // null) | first_key_array) as $keys |
                    if ($keys | length) > 0 then {"api_keys": $keys} else null end
                ),
                "glm_search": (if (.tools.web.glm_search.api_key? // "") != "" then {"api_key": .tools.web.glm_search.api_key} else null end),
                "baidu_search": (if (.tools.web.baidu_search.api_key? // "") != "" then {"api_key": .tools.web.baidu_search.api_key} else null end)
            },
            "skills": {
                "github": (if (.tools.skills.github.token? // "") != "" then {"token": .tools.skills.github.token} else null end),
                "clawhub": (if (.tools.skills.registries.clawhub.auth_token? // "") != "" then {"auth_token": .tools.skills.registries.clawhub.auth_token} else null end)
            }
        } | prune
    '
}

extract_runtime_security() {
    local source_json extracted_security

    source_json="$1"
    extracted_security="$(printf '%s' "${source_json}" | extract_embedded_security_json)"

    if [ "${extracted_security}" = "{}" ]; then
        return
    fi

    if [ -f "${RUNTIME_SECURITY_FILE}" ]; then
        bashio::log.warning "Sensitive fields were detected in the config source, but ${RUNTIME_SECURITY_FILE} already exists. Keeping the existing runtime security file and stripping sensitive fields from ${SHARED_CONFIG}."
        return
    fi

    printf '%s\n' "${extracted_security}" > "${RUNTIME_SECURITY_FILE}"
    chmod 600 "${RUNTIME_SECURITY_FILE}"
    chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${RUNTIME_SECURITY_FILE}"
    bashio::log.info "Extracted sensitive fields from the config source into ${RUNTIME_SECURITY_FILE}"
}

write_runtime_config() {
    local raw_json trimmed parser_error normalized_json source_json source_label

    if [ -f "${SHARED_CONFIG}" ]; then
        source_json="$(cat "${SHARED_CONFIG}")"
        source_label="${SHARED_CONFIG}"
        bashio::log.info "Using shared workspace config ${SHARED_CONFIG} as the source of truth."
    else
        raw_json="$(bashio::config 'raw_json_config')"
        trimmed="${raw_json//[$'\t\r\n ']}"

        if [ -z "${trimmed}" ]; then
            fail "No shared config exists at ${SHARED_CONFIG}, and option raw_json_config is empty. Create ${SHARED_CONFIG} or paste a complete PicoClaw JSON object into the add-on configuration before starting the add-on."
        fi

        source_json="${raw_json}"
        source_label="Home Assistant option raw_json_config"
        bashio::log.info "Seeding ${SHARED_CONFIG} from raw_json_config because no shared config file exists yet."
    fi

    if ! parser_error="$(printf '%s' "${source_json}" | jq -e 'type == "object"' 2>&1 >/dev/null)"; then
        fail "Invalid ${source_label}. jq reported: ${parser_error}. Provide a valid JSON object."
    fi

    extract_runtime_security "${source_json}"
    normalized_json="$(printf '%s' "${source_json}" | normalize_config_json)"

    printf '%s\n' "${normalized_json}" > "${SHARED_CONFIG}"
    chmod 600 "${SHARED_CONFIG}"
    chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARED_CONFIG}"
}

start_launcher() {
    local gateway_log_level

    export HOME="${RUNTIME_HOME}"
    export PICOCLAW_HOME="${RUNTIME_HOME}"
    export PICOCLAW_CONFIG="${SHARED_CONFIG}"
    export PICOCLAW_SECURITY_DIR="${RUNTIME_HOME}"
    export PICOCLAW_BINARY="/usr/local/bin/picoclaw"
    export PICOCLAW_GATEWAY_HOST="0.0.0.0"
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"

    bashio::log.info "Workspace: ${SHARED_WORKSPACE}"
    bashio::log.info "Runtime home: ${RUNTIME_HOME}"
    bashio::log.info "Effective config: ${SHARED_CONFIG}"
    bashio::log.info "Effective security dir: ${RUNTIME_HOME}"
    bashio::log.info "Starting PicoClaw launcher on Home Assistant ingress port 18800"

    gateway_log_level="$(jq -r '.gateway.log_level // empty' "${SHARED_CONFIG}")"
    if [ "${gateway_log_level}" = "debug" ]; then
        bashio::log.info "Gateway debug mode requested through the shared config. The launcher will start PicoClaw with detailed gateway logs enabled."
    fi

    exec su-exec "${PICOCLAW_UID}:${PICOCLAW_GID}" \
        /usr/local/bin/picoclaw-launcher \
        -console \
        -no-browser \
        -lang en \
        -public \
        "${RUNTIME_CONFIG}"
}

ensure_directories
ensure_workspace_symlink
ensure_runtime_config_links
bootstrap_workspace_templates
bootstrap_wrapper_workspace_files
log_workspace_diagnostics
copy_optional_security_file
write_launcher_config
write_runtime_config
start_launcher
