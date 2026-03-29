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

ensure_directories() {
    mkdir -p "${SHARE_ROOT}" "${SHARED_WORKSPACE}" "${RUNTIME_HOME}"
    chown -R "${PICOCLAW_UID}:${PICOCLAW_GID}" "${SHARE_ROOT}" "${RUNTIME_HOME}"
}

ensure_workspace_symlink() {
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
            .agents = (.agents // {}) |
            .agents.defaults = (.agents.defaults // {}) |
            .agents.defaults.workspace = $workspace
        '
    )"

    printf '%s\n' "${normalized_json}" > "${RUNTIME_CONFIG}"
    chmod 600 "${RUNTIME_CONFIG}"
    chown "${PICOCLAW_UID}:${PICOCLAW_GID}" "${RUNTIME_CONFIG}"
}

start_launcher() {
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
copy_optional_security_file
write_launcher_config
write_runtime_config
start_launcher
