#!/usr/bin/env bash
# prepare.sh - build a VMS-ready source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. run the upstream configure on this host, with every platform answer
#      taken from VMS probe results (probed.site) or hand-settled values
#      (vms-manual.site) instead of from Linux
#   4. generate gnulib's headers and config.h, copy them into the tree
#   5. write the MMS source lists and the configuration snapshot
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name
hostcfg=$top/cache/hostcfg-$name
cfgdir=$top/overlay/vms/config
snapshot=$top/snapshot
# Configuration answers come from this node's VSI C run; both architectures
# share one CRTL feature set (see docs/vms-environment.md).
PRIMARY_NODE=${PRIMARY_NODE:-ia64}
PRIMARY_TRIPLET=ia64-hp-openvms

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

# --- 2. extract, patch, overlay -------------------------------------------
step "extracting $name"
rm -rf "$stage"
mkdir -p "$top/staging"
tar -xJf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

# --- 3. host configure with VMS answers ----------------------------------
step "configure (host, VMS answers)"
rm -rf "$hostcfg"
mkdir -p "$hostcfg"
site=$hostcfg/vms.site
# Answers: the VSI C configure run (vms_configure.sh) if there is one, else the
# function/header probes; vms-manual.site last so it always wins.
answers=$cfgdir/configure-$PRIMARY_NODE.cache
if [ ! -f "$answers" ]; then
    # First pass of a new release: stage the tree for vms_configure.sh, which
    # writes the answers.  The result is not buildable on VMS yet.
    answers=$hostcfg/no-answers.site; : > "$answers"
    step "WARNING: no $(basename "$cfgdir")/configure-$PRIMARY_NODE.cache yet:" \
         "Linux answers (run tools/vms_configure.sh, then prepare again)"
fi
step "answers from $(basename "$answers")"
python3 "$top/tools/nextheaders_site.py" "$stage/configure" "$cfgdir/crtl_modules.txt" \
    > "$cfgdir/next-headers.site"
cat "$answers" "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
# Same --host as vms_configure.sh so configure takes the same code paths.
(cd "$hostcfg" && CONFIG_SITE=$site "$stage/configure" -q -C \
    --build="$("$stage/build-aux/config.guess")" --host=$PRIMARY_TRIPLET CC=gcc "${cfgargs[@]}" \
    > configure.out 2>&1) || { tail -20 "$hostcfg/configure.out"; die "configure failed"; }

# --- 4. generated headers and config.h -------------------------------------
printvar() {  # printvar <dir> <make variable>
    make -s -C "$hostcfg/$1" -f Makefile -f "$top/tools/printvar.mk" "print-$2"
}
# tar's gnulib is in gnu/ (libgnu.a); its own libtar.a is in lib/.
built=$(printvar gnu BUILT_SOURCES)
step "generating $(echo $built | wc -w) gnulib headers"
make -s -C "$hostcfg/gnu" $built >/dev/null
for h in $built; do
    # Some are shipped in the source tree and not rebuilt (unicase tables).
    [ -f "$hostcfg/gnu/$h" ] || { [ -f "$stage/gnu/$h" ] && continue; die "no generated $h"; }
    mkdir -p "$stage/gnu/$(dirname "$h")"
    cp "$hostcfg/gnu/$h" "$stage/gnu/$h"
done
# libtar's generated headers (rmt-command.h, attr/xattr.h when needed).
libbuilt=$(printvar lib BUILT_SOURCES)
make -s -C "$hostcfg/lib" $libbuilt >/dev/null
for h in $libbuilt; do
    mkdir -p "$stage/lib/$(dirname "$h")"
    cp "$hostcfg/lib/$h" "$stage/lib/$h"
done
cp "$hostcfg/config.h" "$stage/config.h"   # AC_CONFIG_HEADERS([config.h])
# VSI C cannot #include a name with two dots: generated gnu/malloc/*.gl.h
# become *_gl.h (a patch includes them by that name on VMS).
for f in "$stage"/gnu/malloc/*.gl.h; do
    [ -e "$f" ] || continue
    sed 's|<malloc/\([a-z_-]*\)\.gl\.h>|<malloc/\1_gl.h>|g' "$f" > "${f%.gl.h}_gl.h"
    rm "$f"
done

# --- 5. MMS source lists ---------------------------------------------------
# Objects for libgnu (gnulib): automake sources after conditionals, plus LIBOBJS.
lib_srcs=$( { printvar gnu libgnu_a_SOURCES
              printvar gnu libgnu_a_LIBADD | tr ' ' '\n' | sed -n 's/^libgnu_a-//; s/\.o$/.c/p'
            } | tr ' ' '\n' | grep '\.c$' | sort -u)
# Leave out what cannot work on VMS (overlay/vms/lib-exclude.txt, with reasons).
while read -r pat; do
    case $pat in ''|'#'*) continue ;; esac
    lib_srcs=$(echo "$lib_srcs" | while read -r f; do
        case $(basename "$f") in $pat) ;; *) echo "$f" ;; esac; done)
done < "$top/overlay/vms/lib-exclude.txt"
src_srcs=$(printvar src tar_SOURCES | tr ' ' '\n' | grep '\.c$' | sort -u)
# libtar's sources are compiled with the VMS files as extra sources.
libtar_srcs=$(printvar lib libtar_a_SOURCES | tr ' ' '\n' | grep '\.c$' | sed 's|^|lib/|' | sort -u)
# Object names must be unique within each object directory (lib objects go to
# their own, so lib/hash.c and src/hash.c can coexist).
for list in "$lib_srcs" "$src_srcs"; do
    dups=$(echo "$list" | xargs -n1 basename | sort | uniq -d)
    [ -z "$dups" ] || die "duplicate object names: $dups"
done

mkdir -p "$stage/vms"
echo "$lib_srcs" > "$hostcfg/lib-sources.txt"
echo "$src_srcs" > "$hostcfg/src-sources.txt"
{ cat "$top/overlay/vms/extra-sources.txt"; echo "$libtar_srcs"; } > "$hostcfg/extra-sources.txt"
GEN_MMS_LIB_BASE=gnu GEN_MMS_CONFIG_DIR= python3 "$top/tools/gen_mms.py" "$cfgdir/ccflags.txt" "$hostcfg/lib-sources.txt" \
    "$hostcfg/src-sources.txt" "$hostcfg/extra-sources.txt" > "$stage/vms/sources.mms"

if [ -d "$stage/vms/kit" ]; then
step "PCSI kit inputs (to come)"
fi

# --- snapshot: the resolved configuration, committed and reviewed ----------
mkdir -p "$snapshot"
cp "$hostcfg/config.h" "$snapshot/config.h"
echo "$lib_srcs" > "$snapshot/lib-sources.txt"
echo "$src_srcs" > "$snapshot/src-sources.txt"
# Every cached answer, and where it came from.
cat "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$hostcfg/manual.site"
python3 "$top/tools/cfgreport.py" "$hostcfg/config.cache" "$answers" \
    "$hostcfg/manual.site" > "$snapshot/cache-answers.txt"
step "inherited-from-Linux answers: $(grep -c ' host$' "$snapshot/cache-answers.txt" || true)" \
     "(see snapshot/cache-answers.txt)"

step "staged $stage"
if ! git -C "$top" diff --quiet -- snapshot 2>/dev/null; then
    step "snapshot/ changed - review with: git diff -- snapshot"
fi
