#!/usr/bin/env bash
# build-docker.sh – Build the Sonarr Docker image locally from source.
#
# The build context is the repository root so that both src/ (backend) and
# frontend/ can be accessed by the multi-stage Dockerfile.
#
# For CI/CD use the GitHub Actions workflow at .github/workflows/docker-build.yml
# which builds multi-arch images and pushes them to GHCR automatically.
#
# Usage (local development):
#   ./distribution/docker/build-docker.sh [--version <label>] [--tag <image_tag>] [--push] [--platform <platform>]
#
# Environment variables (all optional – defaults shown):
#   IMAGE_TAG    – Docker image name:tag              (default: sonarr:local)
#   VERSION      – Version label baked into the image (default: local-<short-sha>)
#   BUILD_DATE   – ISO-8601 build timestamp           (default: current UTC time)
#   PLATFORM     – Target platform                    (default: local host arch)
#   PUSH         – Set to "true" to push after build

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── defaults ──────────────────────────────────────────────────────────────────
IMAGE_TAG="${IMAGE_TAG:-sonarr:local}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
PLATFORM="${PLATFORM:-}"
PUSH="${PUSH:-false}"

# Derive VERSION from git if not set
if [[ -z "${VERSION:-}" ]]; then
  if git -C "${REPO_ROOT}" describe --tags --exact-match HEAD 2>/dev/null; then
    VERSION=$(git -C "${REPO_ROOT}" describe --tags --exact-match HEAD | sed 's/^v//')
  else
    VERSION="local-$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  fi
fi

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   VERSION="$2";    shift 2 ;;
    --tag)       IMAGE_TAG="$2";  shift 2 ;;
    --platform)  PLATFORM="$2";   shift 2 ;;
    --push)      PUSH="true";     shift   ;;
    *) echo "Unknown option: $1"; exit 1  ;;
  esac
done

# ── build ─────────────────────────────────────────────────────────────────────
echo ""
echo "Building Docker image: ${IMAGE_TAG}"
echo "  Context    : ${REPO_ROOT}"
echo "  Dockerfile : distribution/docker/Dockerfile"
echo "  VERSION    : ${VERSION}"
echo "  BUILD_DATE : ${BUILD_DATE}"
[[ -n "${PLATFORM}" ]] && echo "  PLATFORM   : ${PLATFORM}"
echo ""

PLATFORM_ARG=()
[[ -n "${PLATFORM}" ]] && PLATFORM_ARG=(--platform "${PLATFORM}")

docker buildx build \
  --file "${REPO_ROOT}/distribution/docker/Dockerfile" \
  --build-arg "BUILD_DATE=${BUILD_DATE}" \
  --build-arg "VERSION=${VERSION}" \
  --tag "${IMAGE_TAG}" \
  "${PLATFORM_ARG[@]}" \
  $( [[ "${PUSH}" == "true" ]] && echo "--push" || echo "--load" ) \
  "${REPO_ROOT}"

echo ""
echo "Build complete: ${IMAGE_TAG}"
