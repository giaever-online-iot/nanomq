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

Tests and lint (all plain bash, no framework — same harness style as the CI):

```bash
bash tests/functions_test.sh            # characterization tests for src/helpers/functions
bash tests/snapcraft_state_test.sh      # guards committed snapcraft.yaml against local-source state
for t in .github/scripts/*.test.sh; do bash "$t"; done   # CI helper unit tests
shellcheck --severity=warning -x src/bin/* src/wrappers/* src/helpers/* tests/*.sh
```

Note the naming split: `tests/` (plural) is the tracked test suite; the gitignored `test/` (singular) `SNAP`/`SNAP_DATA` trees mock the snap runtime so `src/bin/conf` can be exercised locally outside confinement (set `SNAP`, `NANOMQ_CONF`, `VIM`, `SNAP_UID=0`, `SNAP_INSTANCE_NAME` explicitly to mimic the snap environment).

## Architecture

### snapcraft.yaml

Three parts: `nanomq` (cmake build of upstream with TLS, SQLite, ACL, and rule engine enabled — the commented block at the bottom of the yaml catalogs all other available cmake flags), `local` (dumps `src/` into the snap and stages `vim-tiny`), and `crash` (a deliberate debugging hook: a nil part ordered after the others whose `override-prime` you flip to a failing command when you want `snapcraft --debug` to drop you into the build container after the real parts have built).

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

Everything derives from `version:` in `snap/snapcraft.yaml` — the Makefile and CI read it with `yq` to name the local clone directory, pick the upstream git tag, derive the store track, and name the `.snap` file. Upstream tags are plain semver with **no `v` prefix** (`0.24.14`). Renovate (`renovate.json`) watches `nanomq/nanomq` GitHub releases and opens PRs bumping that one field; manual bumps are the same one-field change.

## CI / release pipeline

Ported from `giaever-online-iot/zwave-js-ui`; all channel/version math lives in `.github/scripts/snap-release.sh` (unit-tested, handles nanomq's un-prefixed versions — store tracks stay v-prefixed but are **major-only**, e.g. version `0.24.14` → track `v0`, because the Snap Store track guardrail for nanomq only permits `v<major>` names, unlike zwave-js-ui's `v<major>.<minor>`).

- **PRs must target `main` from an in-repo branch** — fork PRs are auto-closed and labeled (`block-fork-prs.yml`).
- `pr-build-snap.yml`: PRs touching `snap/**` or `src/**` are remote-built on Launchpad for every arch in `platforms:` and each arch is **published to `v<major>/edge/<PR#>`** as soon as it finishes (the track is created first via the storefront API). A sticky PR comment shows the channel and install command; the always-on `gate` job is safe to require in branch protection. Docs-only PRs skip the build.
- `release-on-merge.yml`: on merge, **promotes** the PR's revisions to `v<major>/stable` plus `latest/candidate`/`latest/edge` (never downgrading a channel), and moves the default track forward.
- Required repo secrets: `LAUNCHPAD_CREDENTIALS`, `SNAPCRAFT_STORE_CREDENTIALS`, and `SNAPCRAFT_SESSION_COOKIE` (a snapcraft.io web session cookie — expires and needs periodic refresh; when track creation fails, this is the first suspect).
- `tests/snapcraft_state_test.sh` (run by `lint-test.yml`) fails if snapcraft.yaml is committed in the `make local-source` state.
