# syntax=docker/dockerfile:1

# ── Stage 1: Build frontend ───────────────────────────────────────────────────
FROM node:20-alpine AS frontend-builder

WORKDIR /src

# pnpm 8 matches lockfileVersion 6.0 in pnpm-lock.yaml
RUN npm install -g pnpm@8

# Install dependencies before copying source for better layer cache reuse
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy source files required by webpack
COPY tsconfig.json ./
COPY frontend/ ./frontend/

# Output lands in _output/UI/
RUN pnpm run build --env production

# ── Stage 2: Build backend ────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:6.0 AS backend-builder

# Map Docker TARGETARCH → .NET musl RID for Alpine compatibility
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) echo "linux-musl-x64"   > /rid ;; \
      arm64) echo "linux-musl-arm64" > /rid ;; \
      arm)   echo "linux-arm"        > /rid ;; \
      *)     echo "linux-musl-x64"   > /rid ;; \
    esac

WORKDIR /src

# Copy source (global.json is intentionally omitted to avoid SDK version
# pinning inside the container; the image's SDK is used as-is)
COPY src/ ./src/

# Self-contained publish bundles the .NET runtime – no runtime needed in the final image
RUN RID=$(cat /rid) && \
    dotnet publish src/NzbDrone.Console/Sonarr.Console.csproj \
      -c Release \
      -r "${RID}" \
      -f net6.0 \
      --self-contained true \
      -o /app/sonarr/bin

# ── Stage 3: Final runtime image ─────────────────────────────────────────────
FROM ghcr.io/linuxserver/baseimage-alpine:3.23

ARG BUILD_DATE
ARG VERSION
LABEL build_version="Sonarr version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="sonarr"

ENV XDG_CONFIG_HOME="/config/xdg" \
    COMPlus_EnableDiagnostics=0 \
    TMPDIR=/run/sonarr-temp

# Native libraries required at runtime (ICU for globalisation, sqlite, xmlstarlet for healthcheck)
RUN apk add --no-cache \
      icu-libs \
      sqlite-libs \
      xmlstarlet

# Backend binary (self-contained – includes the .NET runtime)
COPY --from=backend-builder /app/sonarr/bin/ /app/sonarr/bin/

# Frontend (webpack output)
COPY --from=frontend-builder /src/_output/UI/ /app/sonarr/bin/UI/

# Write container metadata files consumed by linuxserver base scripts
RUN printf "UpdateMethod=docker\nBranch=main\nPackageVersion=%s\nPackageAuthor=sonarr.tv" \
      "${VERSION:-LocalBuild}" > /app/sonarr/package_info && \
    printf "Version: %s\nBuild-date: %s" "${VERSION:-LocalBuild}" "${BUILD_DATE}" > /build_version

# s6-overlay service definitions (run/check/init scripts)
COPY distribution/docker/root/ /

EXPOSE 8989
VOLUME /config

