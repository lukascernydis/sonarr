# syntax=docker/dockerfile:1

# ── Stage 1: Build frontend ───────────────────────────────────────────────────
FROM node:20-alpine AS frontend-builder

WORKDIR /src

# Project uses Yarn 1 (classic) – pin the same version as volta in package.json
RUN npm install -g yarn@1.22.19

# Install dependencies before copying source for better layer cache reuse
COPY package.json yarn.lock .yarnrc ./
RUN yarn install --frozen-lockfile --network-timeout 120000

# Copy source files required by webpack
COPY tsconfig.json ./
COPY frontend/ ./frontend/

# Output lands in _output/UI/
RUN yarn run build --env production

# ── Stage 2: Build backend ────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:6.0 AS backend-builder

WORKDIR /src

# global.json is intentionally omitted to avoid SDK version pinning inside the
# container – the image SDK is used as-is.
COPY src/ ./src/

# Self-contained publish for linux/amd64 (musl = Alpine compatible).
# Bundles the .NET runtime so no runtime package is needed in the final image.
RUN dotnet publish src/NzbDrone.Console/Sonarr.Console.csproj \
      -c Release \
      -r linux-musl-x64 \
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

# Native libraries required at runtime
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

# s6-overlay service definitions
COPY distribution/docker/root/ /

EXPOSE 8989
VOLUME /config

