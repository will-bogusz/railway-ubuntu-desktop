#!/usr/bin/env bash
# Build linux/amd64 and push to GHCR. Run on a docker host:
#   ./build.sh 24.04-YYYYMMDD --push
set -euo pipefail
cd "$(dirname "$0")"
IMAGE=ghcr.io/will-bogusz/railway-ubuntu-desktop
TAG="${1:-24.04-$(date -u +%Y%m%d)}"
docker build --platform linux/amd64 -t "$IMAGE:$TAG" .
[ "${2:-}" = "--push" ] && docker push "$IMAGE:$TAG" && docker image inspect "$IMAGE:$TAG" --format '{{index .RepoDigests 0}}'
