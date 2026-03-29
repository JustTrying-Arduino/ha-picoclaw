ARG BUILD_FROM
ARG PICOCLAW_VERSION=v0.2.4
ARG PICOCLAW_WRAPPER_VERSION=v0.2.4-ha.5

FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS builder

ARG PICOCLAW_VERSION
ARG TARGETARCH
ARG TARGETVARIANT

RUN apk add --no-cache git make nodejs npm patch ca-certificates tzdata
RUN npm install -g pnpm

WORKDIR /src

RUN git clone --branch "${PICOCLAW_VERSION}" --depth 1 https://github.com/sipeed/picoclaw.git .
COPY patches /patches
RUN set -eux; \
    find /patches -maxdepth 1 -type f -name '*.patch' -print | sort; \
    for patch in /patches/*.patch; do \
      [ -e "${patch}" ] || exit 0; \
      echo "Applying ${patch}"; \
      git apply "${patch}"; \
    done

RUN go generate ./...

RUN cd web/frontend && pnpm install --frozen-lockfile && pnpm build:backend

RUN set -eux; \
    VERSION="$(git describe --tags --always --dirty)"; \
    GIT_COMMIT="$(git rev-parse --short=8 HEAD)"; \
    BUILD_TIME="$(date +%FT%T%z)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    CONFIG_PKG="github.com/sipeed/picoclaw/pkg/config"; \
    LDFLAGS="-X ${CONFIG_PKG}.Version=${VERSION} -X ${CONFIG_PKG}.GitCommit=${GIT_COMMIT} -X ${CONFIG_PKG}.BuildTime=${BUILD_TIME} -X ${CONFIG_PKG}.GoVersion=${GO_VERSION} -s -w"; \
    export GOOS=linux; \
    export CGO_ENABLED=0; \
    case "${TARGETARCH}/${TARGETVARIANT}" in \
      amd64/*) export GOARCH=amd64 ;; \
      arm64/*) export GOARCH=arm64 ;; \
      arm/v7) export GOARCH=arm GOARM=7 ;; \
      *) echo "Unsupported target architecture: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /out; \
    go build -v -tags "goolm,stdjson" -ldflags "${LDFLAGS}" -o /out/picoclaw ./cmd/picoclaw; \
    go build -v -tags "goolm,stdjson" -ldflags "${LDFLAGS}" -o /out/picoclaw-launcher ./web/backend; \
    go build -v -tags "goolm,stdjson" -ldflags "${LDFLAGS}" -o /out/picoclaw-launcher-tui ./cmd/picoclaw-launcher-tui

FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_VERSION
ARG PICOCLAW_VERSION
ARG PICOCLAW_WRAPPER_VERSION

LABEL \
  io.hass.name="PicoClaw" \
  io.hass.description="Home Assistant wrapper for the official PicoClaw launcher and gateway" \
  io.hass.arch="${BUILD_ARCH}" \
  io.hass.type="addon" \
  org.opencontainers.image.title="PicoClaw Home Assistant Add-on" \
  org.opencontainers.image.description="Thin Home Assistant wrapper for PicoClaw" \
  org.opencontainers.image.version="${PICOCLAW_WRAPPER_VERSION}" \
  org.opencontainers.image.source="https://github.com/JustTrying-Arduino/ha-picoclaw" \
  org.opencontainers.image.revision="${BUILD_REF}"

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apk add --no-cache bash jq su-exec tzdata ca-certificates

RUN addgroup -S picoclaw && adduser -S -D -H -h /data/picoclaw -G picoclaw picoclaw

COPY --from=builder /out/picoclaw /usr/local/bin/picoclaw
COPY --from=builder /out/picoclaw-launcher /usr/local/bin/picoclaw-launcher
COPY --from=builder /out/picoclaw-launcher-tui /usr/local/bin/picoclaw-launcher-tui
COPY run.sh /run.sh

RUN chmod a+x /run.sh /usr/local/bin/picoclaw /usr/local/bin/picoclaw-launcher /usr/local/bin/picoclaw-launcher-tui

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:18800/launcher-login || exit 1

CMD ["/run.sh"]
