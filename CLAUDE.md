# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Snap packaging for [NanoMQ](https://nanomq.io/), the MQTT broker / edge messaging platform. The NanoMQ C source is **not** tracked here — snapcraft pulls it from the upstream repo (https://github.com/nanomq/nanomq.git) at the tag matching `version:` in `snap/snapcraft.yaml`, or from a local clone in the gitignored `nanomq/<version>/` directory. The code that actually lives in this repo is:

- `snap/snapcraft.yaml` — the snap build definition (core24, strict confinement)
- `src/` — bash scripts shipped verbatim into the snap by the `local` part
- `Makefile` — developer workflow driver (requires `snapcraft` and mikefarah `yq` v4)

## Commands

One-time setup: `make init-snap-env` (installs snapcraft, logs into snap store).

- `make build-local` — rewrites snapcraft.yaml to use a local upstream clone, clones/pulls `nanomq/<version>` at the version tag, then builds
- `make build-remote` — rewrites snapcraft.yaml back to the upstream GitHub URL with `source-tag: $SNAPCRAFT_PROJECT_VERSION`, then builds
- `make install` / `make uninstall` — install the built `.snap` with `--devmode` / remove it
- `make enter-shell` — open a shell inside the snap's confinement
- `make clean-build` — `snapcraft clean`
- `make clean-local` — restore remote source in the yaml, uninstall, clean, and delete local clones and `.snap` artifacts

**Gotcha:** `local-source`/`remote-source` edit `snap/snapcraft.yaml` in place via `yq`. The committed state must be the *remote* state (GitHub URL + `source-tag`). After `make build-local`, run `make remote-source` before committing, or you will commit a machine-local source path.

There is no automated test suite. The gitignored `test/SNAP` and `test/SNAP_DATA` trees mock the snap runtime so `src/bin/conf` can be run directly from the repo root outside confinement — the script falls back to `$(pwd)/src` for `$SNAP`, `$(pwd)/test/SNAP_DATA/nanomq.conf` for `$NANOMQ_CONF`, and `SNAP_UID=0`, so `./src/bin/conf` exercises the menu/copy/edit flow locally.

## Architecture

### snapcraft.yaml

Three parts: `nanomq` (cmake build of upstream with TLS, SQLite, ACL, and rule engine enabled — the commented block at the bottom of the yaml catalogs all other available cmake flags), `local` (dumps `src/` into the snap and stages `vim-tiny`), and `crash` (a nil part ordered after the others, used as a build-stage hook).

Three snap apps are exposed:

- `nanomq` — the broker daemon (`nanomq start --conf $NANOMQ_CONF`), wrapped by `src/wrappers/daemon` via command-chain; restarts always
- `nanomq.cli` — upstream's `nanomq_cli`
- `nanomq.conf` — `src/bin/conf`, an interactive config editor

`NANOMQ_CONF` is set snap-wide to `$SNAP_DATA/nanomq.conf`.

### The bash scripts (src/)

`src/helpers/functions` holds shared helpers sourced by both entry points; `fn`/`search_conf` encode the config naming convention `nanomq[_<name>].conf`.

`src/wrappers/daemon` gates daemon startup: it requires root and refuses to start (exit 1) until `$NANOMQ_CONF` exists, directing the user to run `sudo nanomq.conf`.

`src/bin/conf` is the main UX: it lists writable configs from `$SNAP_DATA` and read-only examples from `$SNAP/usr/local/etc/`, copies a chosen read-only example into `$SNAP_DATA` (renaming `nanomq.conf` / `nanomq_old.conf` / `nanomq_example.conf` variants to the `$NANOMQ_CONF` basename, keeping other names like `nanomq_bridge.conf` as-is), opens it in `vim.tiny`, and on save restarts the daemon with `snapctl restart`.

### Version bumps

Everything derives from `version:` in `snap/snapcraft.yaml` — the Makefile reads it with `yq` to name the local clone directory, pick the upstream git tag, and name the `.snap` file. To bump: change that one field (the upstream tag must exist), then `make build-remote` (or `build-local`) and `make install` to verify.
