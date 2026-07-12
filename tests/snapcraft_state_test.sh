#!/usr/bin/env bash
# Guards the committed snapcraft.yaml against the `make local-source` state.
# `make local-source` rewrites parts.nanomq.source to a machine-local clone and
# deletes source-tag for local snapcraft runs; committing that state breaks CI
# and store builds. Run `make remote-source` before committing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML="$(dirname "$HERE")/snap/snapcraft.yaml"

fail=0
err() { printf 'FAIL - %s\n' "$1"; fail=1; }

src="$(yq e '.parts.nanomq.source' "$YAML")"
tag="$(yq e '.parts.nanomq.source-tag' "$YAML")"
ver="$(yq e '.version' "$YAML")"

[ "$src" = "https://github.com/nanomq/nanomq.git" ] \
  || err "parts.nanomq.source is '$src' — committed after 'make local-source'? Run 'make remote-source'."

[ "$tag" = "\$SNAPCRAFT_PROJECT_VERSION" ] \
  || err "parts.nanomq.source-tag is '$tag' (expected \$SNAPCRAFT_PROJECT_VERSION)."

# Upstream nanomq tags are plain semver, optionally suffixed (0.25.2-2).
[[ "$ver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.]+)?$ ]] \
  || err "version '$ver' does not look like an upstream nanomq tag (plain semver, no 'v')."

[ "$fail" -eq 0 ] && echo "snapcraft.yaml state OK (remote source, tag \$SNAPCRAFT_PROJECT_VERSION, version $ver)."
exit "$fail"
