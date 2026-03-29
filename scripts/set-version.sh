#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <upstream-version> [wrapper-revision]" >&2
    exit 1
fi

upstream_version="$1"
wrapper_revision="${2:-ha.1}"
wrapper_version="${upstream_version}-${wrapper_revision}"

perl -0pi -e "s/PICOCLAW_VERSION: .*\n/PICOCLAW_VERSION: ${upstream_version}\n/" picoclaw/build.yaml
perl -0pi -e "s/PICOCLAW_WRAPPER_VERSION: .*\n/PICOCLAW_WRAPPER_VERSION: ${wrapper_version}\n/" picoclaw/build.yaml
perl -0pi -e "s/version: .*\n/version: ${wrapper_version}\n/" picoclaw/config.yaml
perl -0pi -e "s/ARG PICOCLAW_VERSION=.*/ARG PICOCLAW_VERSION=${upstream_version}/" picoclaw/Dockerfile
perl -0pi -e "s/ARG PICOCLAW_WRAPPER_VERSION=.*/ARG PICOCLAW_WRAPPER_VERSION=${wrapper_version}/" picoclaw/Dockerfile
