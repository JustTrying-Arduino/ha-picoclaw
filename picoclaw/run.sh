#!/usr/bin/with-contenv bashio
set -euo pipefail

readonly SHARE_ROOT="/share/picoclaw"
readonly SHARED_WORKSPACE="${SHARE_ROOT}/workspace"
readonly SHARED_SECURITY_FILE="${SHARE_ROOT}/.security.yml"
readonly SHARED_IGNORED_OVERRIDE="${SHARE_ROOT}/config.override.json"

readonly RUNTIME_HOME="/data/picoclaw"
readonly RUNTIME_CONFIG="${RUNTIME_HOME}/config.json"
readonly RUNTIME_SECURITY_FILE="${RUNTIME_HOME}/.security.yml"
readonly RUNTIME_LAUNCHER_CONFIG="${RUNTIME_HOME}/launcher-config.json"
readonly RUNTIME_WORKSPACE_LINK="${RUNTIME_HOME}/workspace"

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

log_workspace_diagnostics() {
    local runtime_realpath shared_realpath symlink_target top_level_entries

    runtime_realpath="$(realpath_safe "${RUNTIME_WORKSPACE_LINK}")"
    shared_realpath="$(realpath_safe "${SHARED_WORKSPACE}")"
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
}

copy_optional_security_file() {
    if [ -f "${SHARED_SECURITY_FILE}" ]; then
        install -m 600 -o "${PICOCLAW_UID}" -g "${PICOCLAW_GID}" "${SHARED_SECURITY_FILE}" "${RUNTIME_SECURITY_FILE}"
        bashio::log.info "Loaded optional security data from ${SHARED_SECURITY_FILE}"
    fi

    if [ -f "${SHARED_IGNORED_OVERRIDE}" ]; then
        bashio::log.warning "Ignoring ${SHARED_IGNORED_OVERRIDE}; Home Assistant options remain the only config source in v1."
    fi
}

write_launcher_config() {
    cat > "${RUNTIME_LAUNCHER_CONFIG}" <<'EOF'
{
  "port": 18800,
  "public": true
}
EOF
    chmod 600 "${RUNTIME_LAUNCHER_CONFIG}"
    chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${RUNTIME_LAUNCHER_CONFIG}"
}

write_runtime_config() {
    local raw_json trimmed parser_error normalized_json

    raw_json="$(bashio::config 'raw_json_config')"
    trimmed="${raw_json//[$'\t\r\n ']}"

    if [ -z "${trimmed}" ]; then
        fail "Option raw_json_config is empty. Paste a complete PicoClaw JSON object into the add-on configuration before starting the add-on."
    fi

    if ! parser_error="$(printf '%s' "${raw_json}" | jq -e 'type == "object"' 2>&1 >/dev/null)"; then
        fail "Invalid raw_json_config. jq reported: ${parser_error}. Provide a valid JSON object."
    fi

    normalized_json="$(
        printf '%s' "${raw_json}" | jq --sort-keys --arg workspace "${SHARED_WORKSPACE}" '
            def ensure_enabled(path):
                if getpath(path) == null then setpath(path; true) else . end;
            .agents = (.agents // {}) |
            .agents.defaults = (.agents.defaults // {}) |
            .tools = (.tools // {}) |
            .agents.defaults.workspace = $workspace |
            ensure_enabled(["tools", "skills", "enabled"]) |
            ensure_enabled(["tools", "find_skills", "enabled"]) |
            ensure_enabled(["tools", "install_skill", "enabled"]) |
            ensure_enabled(["tools", "list_dir", "enabled"]) |
            ensure_enabled(["tools", "read_file", "enabled"]) |
            ensure_enabled(["tools", "write_file", "enabled"]) |
            ensure_enabled(["tools", "append_file", "enabled"]) |
            ensure_enabled(["tools", "edit_file", "enabled"])
        '
    )"

    printf '%s\n' "${normalized_json}" > "${RUNTIME_CONFIG}"
    chmod 600 "${RUNTIME_CONFIG}"
    chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${RUNTIME_CONFIG}"
}

start_launcher() {
    local gateway_log_level

    export HOME="${RUNTIME_HOME}"
    export PICOCLAW_HOME="${RUNTIME_HOME}"
    export PICOCLAW_CONFIG="${RUNTIME_CONFIG}"
    export PICOCLAW_BINARY="/usr/local/bin/picoclaw"
    export PICOCLAW_GATEWAY_HOST="0.0.0.0"
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"

    bashio::log.info "Workspace: ${SHARED_WORKSPACE}"
    bashio::log.info "Runtime home: ${RUNTIME_HOME}"
    bashio::log.info "Starting PicoClaw launcher on Home Assistant ingress port 18800"

    gateway_log_level="$(jq -r '.gateway.log_level // empty' "${RUNTIME_CONFIG}")"
    if [ "${gateway_log_level}" = "debug" ]; then
        bashio::log.info "Gateway debug mode requested through raw_json_config. The launcher will start PicoClaw with detailed gateway logs enabled."
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
log_workspace_diagnostics
copy_optional_security_file
write_launcher_config
write_runtime_config
start_launcher
