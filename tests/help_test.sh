#!/usr/bin/env bash
# Characterization tests for src/bin/help: it must run unprivileged outside
# the snap runtime and mention every command and path a user needs.
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

fail=0
check() { # desc expected-in actual
  if grep -qF "$2" <<<"$3"; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$2"
    fail=1
  fi
}

out="$(env -u SNAP_INSTANCE_NAME -u SNAP_DATA -u SNAP_COMMON bash "$ROOT/src/bin/help")" \
  || { echo "FAIL - help exited non-zero"; exit 1; }

# Outside the snap runtime the script falls back to the real install's paths.
check "names the service"        "sudo snap start|stop|restart nanomq"      "$out"
check "names the cli app"        "nanomq.cli"                               "$out"
check "names the conf app"       "sudo nanomq.conf"                         "$out"
check "names the help app"       "nanomq.help"                              "$out"
check "active config path"       "/var/snap/nanomq/current/nanomq.conf"     "$out"
check "certs drop-in path"       "/var/snap/nanomq/current/certs"           "$out"
check "file log path"            "/var/snap/nanomq/common/log"              "$out"
check "documents naming scheme"  "nanomq[_<name>].conf"                     "$out"
check "REST API off by default"  "Disabled by default"                      "$out"

# Parallel installs get instance-suffixed names and paths.
out2="$(env -u SNAP_DATA -u SNAP_COMMON SNAP_INSTANCE_NAME=nanomq_dev bash "$ROOT/src/bin/help")"
check "honours instance name"    "nanomq_dev.cli"                           "$out2"
check "instance data path"       "/var/snap/nanomq_dev/current"             "$out2"

[ "$fail" -eq 0 ] && echo "All help tests passed."
exit "$fail"
