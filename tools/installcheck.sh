#!/usr/bin/env bash
# installcheck.sh <node> - install the node's kit, verify it, run the smoke test
# against the installed image, and remove it again.  This changes the system
# while it runs (PCSI database, SYS$COMMON:[DIFFUTILS], DIFFUTILS$ROOT); run kit.sh first.
# Output: out/install-<node>.txt (don't redirect this script's stdout there).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: installcheck.sh <node>}
. "$top/upstream.conf"
REMOTE=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
"$top/tools/vms.sh" "$node" put "$top/tools/vms_installcheck.com" >/dev/null
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
job=$top/cache/installcheck-$node.com
printf '$ set noon\n$ @%sVMS_INSTALLCHECK.COM %s\n' "$WORKDIR" "$REMOTE" > "$job"
VMS_TIMEOUT=1800 "$top/tools/vms.sh" "$node" run "$job" > "$top/out/install-$node.txt" 2>&1
grep -aE 'install status|Installed|startup procedure|SMOKE:|SUCREMOVE|after removal|items found' "$top/out/install-$node.txt"
grep -q 'SMOKE: [0-9]* passed, 0 failed' "$top/out/install-$node.txt" &&
    grep -q 'DIFFUTILS\$ROOT after removal: \[\]' "$top/out/install-$node.txt" &&
    grep -q 'startup after removal: \[\]' "$top/out/install-$node.txt"
