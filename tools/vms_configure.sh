#!/usr/bin/env bash
# vms_configure.sh <node> - run upstream configure with VSI C on <node> as the compiler.
#
# configure runs here in cross mode (--host=<arch>-hp-openvms); every compile,
# link and preprocessor test goes through tools/vmscc to vms_ccserver.com on
# the node.  Run-time tests cannot run, so their answers come from gnulib's
# cross-compiling guesses or overlay/vms/config/vms-manual.site.
#
# Result: overlay/vms/config/configure-<node>.cache, the complete set of
# configure answers for VMS.  Commit it; prepare.sh reuses it offline.
# Slow (a few seconds per test, several hundred tests) - run once per release.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: vms_configure.sh <node>}
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
stage=$top/staging/$name
cfgdir=$top/overlay/vms/config
work=$top/cache/vmscfg-$name-$node

read -r _ ARCH HOST PORT USER WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
[ -n "${HOST:-}" ] || { echo "unknown node $node" >&2; exit 2; }
case $ARCH in IA64) triplet=ia64-hp-openvms ;; X86_64) triplet=x86_64-hp-openvms ;; *) exit 2 ;; esac

# One run per node.  The lock fd is inherited by configure and its children,
# so a stray earlier run keeps holding it until every process has exited.
mkdir -p "$top/cache"
exec 9> "$top/cache/vmscfg-$node.lock"
flock -n 9 || { echo "vms_configure: another run for $node is still active" >&2; exit 1; }

[ -x "$stage/configure" ] || { echo "run tools/prepare.sh first (needs $stage)" >&2; exit 1; }
# Work from a private copy so prepare.sh can rebuild staging/ meanwhile.
src=$top/cache/vmscfg-src-$name-$node
rm -rf "$src"; cp -a "$stage" "$src"

# One shared ssh connection for all the sftp sessions vmscc makes.
ctl=/tmp/vmscm-$node-$$
ssh -i "${VMS_SSH_KEY:-$HOME/.ssh/vms_ed25519}" -o BatchMode=yes -p "$PORT" \
    -o ControlMaster=yes -o "ControlPath=$ctl" -o ControlPersist=yes -MNf "$USER@$HOST"
cleanup() {
    local empty; empty=$(mktemp)
    printf 'cd %s/ccserv\nput %s CCSERVER.STOP\n' "$SFTPDIR" "$empty" |
        sftp -P "$PORT" -o "ControlPath=$ctl" -b - "$USER@$HOST" >/dev/null 2>&1 || true
    rm -f "$empty"
    ssh -o "ControlPath=$ctl" -O exit "$USER@$HOST" 2>/dev/null || true
}
trap cleanup EXIT

echo "vms_configure: starting compile server on $node"
"$top/tools/vms.sh" "$node" dcl "create/directory ${WORKDIR%]}.CCSERV]" >/dev/null
"$top/tools/vms.sh" "$node" put "$top/tools/vms_ccserver.com"
ccq=$(cat "$cfgdir/ccflags.txt")
"$top/tools/vms.sh" "$node" dcl \
    "submit/noprint/log_file=${WORKDIR}CCSERVER_$node.LOG/parameters=(\"${WORKDIR%]}.CCSERV]\",\"$ccq\") ${WORKDIR}VMS_CCSERVER.COM" |
    { grep -v '^$' || true; }

rm -rf "$work"; mkdir -p "$work"
python3 "$top/tools/nextheaders_site.py" "$src/configure" "$cfgdir/crtl_modules.txt" \
    | cat - "$cfgdir/vms-manual.site" > "$work/vms.site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
echo "vms_configure: running configure (log: $work/config.log, calls: $work/vmscc.log)"
start=$(date +%s)
(cd "$work" &&
 VMSCC_NODE=$node VMSCC_SUBDIR=ccserv VMSCC_CTL=$ctl VMSCC_LOG=$work/vmscc.log \
 VMSCC_MEMO=$top/cache/vmscc-memo/$node \
 CC=$top/tools/vmscc CONFIG_SITE=$work/vms.site \
 "$src/configure" -C --build="$("$src/build-aux/config.guess")" --host=$triplet \
     "${cfgargs[@]}" > configure.out 2>&1) || { tail -20 "$work/configure.out"; exit 1; }

# A lost connection or a stopped server turns every later test into "fail";
# such answers must not be kept.  (Memoised results are only real answers.)
if grep -qE '^[a-z]+ (timeout|transport) ' "$work/vmscc.log"; then
    echo "vms_configure: $(grep -cE '^[a-z]+ (timeout|transport) ' "$work/vmscc.log")" \
         "tests got no answer from $node (connection or server lost); answers not saved." \
         "Re-run: completed tests come from the memo." >&2
    exit 1
fi

# Keep the answers, minus host-specific noise (paths of host tools, env).
grep -v -e '^ac_cv_env_' -e 'ac_cv_path_' -e 'ac_cv_prog_' -e '^acl_cv_' -e '^am_cv_[^l]' \
    -e '^ac_cv_build=' -e '^ac_cv_host=' "$work/config.cache" > "$cfgdir/configure-$node.cache"
echo "vms_configure: done in $(( ($(date +%s) - start) / 60 )) min," \
     "$(grep -c ' vms ' "$work/vmscc.log" || true) compiled on VMS," \
     "$(grep -c ' memo ' "$work/vmscc.log" || true) from memo -> overlay/vms/config/configure-$node.cache"
