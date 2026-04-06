# syntax=docker/dockerfile:1

# ── Stage 1: Build frontend ───────────────────────────────────────────────────
FROM node:20-alpine AS frontend-builder

WORKDIR /src

# Install dependencies before copying source for better layer cache reuse
# (node:20-alpine already ships with Yarn 1.x)
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
COPY Logo/ ./Logo/

# Self-contained publish for linux/amd64 (musl = Alpine compatible).
# Bundles the .NET runtime so no runtime package is needed in the final image.
# EnableAnalyzers=false skips StyleCop/Roslyn style checks (TreatWarningsAsErrors
# is true in Directory.Build.props and would otherwise fail the Docker build).
RUN dotnet publish src/NzbDrone.Console/Sonarr.Console.csproj \
      -c Release \
      -r linux-musl-x64 \
      -f net6.0 \
      --self-contained true \
      -p:EnableAnalyzers=false \
      -o /app/sonarr/bin

# Sonarr.Mono is NOT a direct reference – it is loaded at runtime by
# AssemblyLoader when running on Linux. Publish it separately and copy
# the DLL (+ its native helper) into the same bin directory.
RUN dotnet publish src/NzbDrone.Mono/Sonarr.Mono.csproj \
      -c Release \
      -r linux-musl-x64 \
      -f net6.0 \
      --self-contained false \
      -p:EnableAnalyzers=false \
      -o /tmp/mono-publish && \
    cp /tmp/mono-publish/Sonarr.Mono.dll        /app/sonarr/bin/ && \
    cp /tmp/mono-publish/Mono.Posix.NETStandard.dll /app/sonarr/bin/ 2>/dev/null || true && \
    find /tmp/mono-publish -name 'libMonoPosixHelper*' -exec cp {} /app/sonarr/bin/ \; && \
    rm -rf /tmp/mono-publish

# Ensure all native executables (ffprobe, ffmpeg, Sonarr, …) have the execute
# bit set.  NuGet sometimes unpacks binaries without +x on Linux hosts.
RUN find /app/sonarr/bin -maxdepth 1 -type f \
      \( -name 'ffprobe' -o -name 'ffmpeg' -o -name 'Sonarr' -o -name 'createdump' \) \
      -exec chmod +x {} +

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

# Windows git does not preserve the execute bit – restore it for every s6
# script that needs to be exec-able (run, check, up, finish …).
# Also strip any Windows CRLF line endings that break s6-rc-compile
# (the 'type' file must contain exactly "oneshot\n", not "oneshot\r\n").
RUN find /etc/s6-overlay/s6-rc.d -type f \
    -exec sed -i 's/\r//' {} + && \
    find /etc/s6-overlay/s6-rc.d -type f \( -name 'run' -o -name 'check' -o -name 'up' -o -name 'finish' \) \
    -exec chmod +x {} +

EXPOSE 8989
VOLUME /config

