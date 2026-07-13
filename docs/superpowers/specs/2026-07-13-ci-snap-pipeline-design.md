# CI + auto-update pipeline for the nanomq snap

**Date:** 2026-07-13
**Status:** Approved
**Reference implementation:** `giaever-online-iot/zwave-js-ui` (workflows, scripts, and release model ported from there)

## Goal

Give this snap-packaging repo the same CI/release pipeline as the sibling zwave-js-ui repo, plus automatic tracking of upstream NanoMQ releases, so a new upstream release flows: Renovate PR → multi-arch build → per-PR store channel → merge → promotion to stable channels — with no manual snapcraft runs.

## Decisions (made with the maintainer)

1. **Full parity** with zwave-js-ui CI: all five workflows, including fork-PR blocking and lint/helper tests.
2. **Renovate** for upstream update PRs (already active on this org; proven on zwave-js-ui).
3. **Per-minor store tracks** (`v0.23`, `v0.24`, …): PRs publish to `v<MM>/edge/<PR#>`, merges promote to `v<MM>/stable` + `latest/*`.
   **Amended 2026-07-14:** the Snap Store track guardrail granted for nanomq only permits **bare `<major>`** names (zwave-js-ui's permits `v<major>.<minor>`; here create-track 400ed on `v0.23` with "Missing guardrails" pre-guardrail and on `v0` with "Invalid track name" post-guardrail). Tracks are therefore bare majors (`0`, `1`, …, node-snap style): PRs publish to `<major>/edge/<PR#>`, merges promote to `<major>/stable` + `latest/*`.

Confirmed preconditions: the `nanomq` store name is owned by publisher Giaever.online (giaever-online); upstream releases are plain semver tags without a `v` prefix (e.g. `0.24.14`).

## Components

### Workflows (`.github/workflows/`)

| Workflow | Trigger | Behavior |
|---|---|---|
| `pr-build-snap.yml` | PR to main; dispatch | `changes` gates on `snap/**`, `src/**`; `meta` reads version/track/archs from snapcraft.yaml (6 archs: amd64, arm64, armhf, ppc64el, s390x, riscv64); `ensure-track` creates `v<MM>` via storefront API; per-arch matrix Launchpad remote-build + immediate publish to `v<MM>/edge/<PR#>`; sticky PR comment; always-on `gate` job (branch-protection safe) |
| `release-on-merge.yml` | PR merged touching build inputs | Promotes `v<MM>/edge/<PR#>` → `v<MM>/stable`, gated `latest/candidate` + `latest/edge` (no downgrades), previous major's final → `latest/stable` on major bump, closes PR channel, bumps default track. Refuses stale-version promotion. |
| `block-fork-prs.yml` | pull_request_target | Auto-label + close PRs from forks or wrong-target. Verbatim from sibling. |
| `helper-tests.yml` | PR touching `.github/scripts/**` | shellcheck + `*.test.sh` for the CI helpers. Verbatim from sibling. |
| `lint-test.yml` | PR touching `src/**`, `tests/**` | shellcheck (`--severity=warning -x`) on `src/bin/* src/wrappers/* src/helpers/*` + repo unit tests in `tests/` |

### CI helper scripts (`.github/scripts/`)

Ported from the sibling: `retry.sh`, `remote-build.sh`, `snap-create-track.sh`, `pr-comment.sh` (SNAP_NAME default → `nanomq`), `snap-release.sh`, plus all `*.test.sh` and fixtures.

**snap-release.sh adaptations (the one real change):**

- `channel-version`'s awk matched versions with `/^v[0-9]/`; nanomq versions are un-prefixed (`0.23.1`). New field pattern `/^v?[0-9]+\./` — requires a dot so numeric Revision fields still never match; `↑` inherited markers and `-` empties keep not matching. Track names remain v-prefixed (`v0.23`), so the track-carry regex is unchanged.
- `_vercmp` hardening: upstream occasionally publishes suffixed tags (`0.25.2-2`). Each dot component is truncated at the first non-digit and defaults to 0, so `0.25.2-2` compares as `0.25.2` instead of tripping bash arithmetic. Documented as: suffix is ignored for ordering.
- Tests keep the sibling's v-prefixed cases and add un-prefixed + suffixed cases with a nanomq-style `snapcraft status` fixture.

`version-to-track 0.23.1` already yields `v0.23` with the sibling logic (it strips an optional `v`, then prefixes `v`). **Amended 2026-07-14:** per the guardrail amendment above, `version-to-track` now emits the bare major instead (`0.23.1` → `0`), and `channel-version`'s track-carry regex accepts bare-numeric track names.

### renovate.json

Regex custom manager over `snap/snapcraft.yaml`: `version: (?<currentValue>...)` (no `v`), `depName nanomq/nanomq`, datasource `github-releases` (stable releases only — tag-only or prerelease uploads like `0.25.2-2` are ignored until released). Package rule: labels `dependencies`, `no-stale`; commit topic `nanomq`. `config:recommended` also keeps the workflows' action pins updated.

Current state 0.23.1 vs upstream 0.24.14 means Renovate's first run opens a bump PR immediately — the pipeline's live end-to-end test.

### src/ shellcheck fixes (behavior-preserving only)

`lint-test.yml` runs at `--severity=warning`, so the existing findings must be resolved: quote `"$@"` (SC2068 ×4), `cd "$SNAP" || exit` (SC2164), `[ x -a y ]` → `[ x ] && [ y ]` (SC2166), `mapfile -t` for `search_conf` output (SC2207/SC2206 — output is newline-separated `find` results; config paths contain no whitespace), rename the copy-destination variable that shadowed the `CONF_RW` array (SC2178/SC2128), and rework the `fn` string-assign of `$@` (SC2124). Verified by diffing `src/bin/conf` menu output against the local `test/SNAP*` harness before/after.

### tests/ (new, mirrors sibling's repo-level tests)

- `functions_test.sh` — unit tests for `path`, `fn`, `search_conf` (documents the `nanomq[_<name>].conf` naming convention).
- `snapcraft_state_test.sh` — asserts the committed snapcraft.yaml has `parts.nanomq.source == https://github.com/nanomq/nanomq.git` and a `source-tag` — fails fast if someone commits after `make local-source`.

Note: `tests/` (plural) is tracked; the gitignored `test/` (singular) mock trees stay local-only.

### Docs

CLAUDE.md gains a CI/contribution section (PR-only flow, per-PR channels, promotion model, Renovate version flow) and clarifies the `crash` part: a deliberate hook — flip its override to a failing command to get dropped into the build container under `snapcraft --debug`.

## Failure modes (inherited from sibling, verified applicable)

- Missing/expired `SNAPCRAFT_SESSION_COOKIE` → `ensure-track` fails; builds still run; report comment says release was blocked, publish is skipped; gate blocks merge.
- Partial-arch build (slow/flaky Launchpad archs — riscv64/s390x are emulated) → published archs ship to the PR channel; the failed leg is red for targeted re-run; `report` fails until all six publish.
- Merging a PR built on a stale base → `release-on-merge` refuses the version-mismatched promotion with manual-recovery instructions.

## Rollout / manual action items (maintainer)

1. Repo secrets (values live in the zwave-js-ui repo's secrets; copy them): `LAUNCHPAD_CREDENTIALS`, `SNAPCRAFT_STORE_CREDENTIALS`, `SNAPCRAFT_SESSION_COOKIE`.
2. Grant the Renovate app access to `giaever-online-iot/nanomq`.
3. Optional: branch-protect `main` requiring the `gate` check.
4. Merge the CI PR; expect Renovate to open the 0.24.x bump PR which exercises build → publish → promote end to end.
