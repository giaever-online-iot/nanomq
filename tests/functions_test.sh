#!/usr/bin/env bash
# Characterization tests for the pure helpers in src/helpers/functions.
# No `set -u`: the helpers are written for the snap's plain bash runtime and
# reference $1 unconditionally; the production entry points don't run with -u.
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

# logp routes through `logger`; stub it so tests are silent and offline.
logger() { :; }
. "$ROOT/src/helpers/functions"

fail=0
check() { # desc expected actual
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n       expected: [%s]\n       actual:   [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}

# path — joins two segments, collapsing runs of slashes (and ./.. runs)
check "path joins"              "a/b"                "$(path "a" "b")"
check "path collapses slashes"  "/x/y"               "$(path "/x//" "/y")"
check "path trailing slash"     "test/SNAP_DATA/"    "$(path "test/SNAP_DATA" "/")"

# fn — builds the nanomq[_<name>].conf filename pattern used by the conf app
check "fn no args is main conf" "nanomq.conf"        "$(fn)"
check "fn glob"                 "nanomq*.conf"       "$(fn "*")"
check "fn one name"             "nanomq_bridge.conf" "$(fn bridge)"
check "fn joins multi words"    "nanomq_a_b.conf"    "$(fn a b)"

# search_conf — find wrapper over the fn pattern
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
touch "$tmp/nanomq.conf" "$tmp/nanomq_bridge.conf" "$tmp/nanomq_old.conf" "$tmp/other.conf"

all="$(search_conf "$tmp" "/" "*" | xargs -rn1 basename | LC_ALL=C sort | paste -sd, -)"
check "search_conf glob finds nanomq*.conf only" "nanomq.conf,nanomq_bridge.conf,nanomq_old.conf" "$all"

one="$(search_conf "$tmp" "/" bridge | xargs -rn1 basename)"
check "search_conf named" "nanomq_bridge.conf" "$one"

none="$(search_conf "$tmp" "/" missing | xargs -rn1 basename)"
check "search_conf no match" "" "$none"

[ "$fail" -eq 0 ] && echo "All functions tests passed."
exit "$fail"
