# vms-tar

GNU tar 1.35 for OpenVMS (IA64 and x86-64), built natively with VSI C. **Work in
progress:** the repository is scaffolded and configured, but not yet built.

The repository stores only our changes over the signed upstream release: `patches/`
(changes to upstream files, applied in `patches/series` order) and `overlay/` (new files:
VMS build procedures, C RTL shims, PCSI kit). `tools/prepare.sh` combines them with the
tarball into `staging/`, which is pushed to a VMS node and built there with MMS. The tooling
is shared with the other ports in the family (see
[vms-grep](https://github.com/issinoho/vms-grep) for the list).

## Status

| Step | IA64 (V8.4-2L3) | x86-64 (E9.2-4) |
|------|-----------------|-----------------|
| Configure with VSI C (`tools/vms_configure.sh`) | done | done |
| Build (`tools/build.sh`) | not yet | not yet |
| Smoke test, PCSI kit, install check | not yet | not yet |

## Workflow

```sh
cp tools/nodes.conf.example tools/nodes.conf   # then fill in the real nodes
tools/prepare.sh                               # fetch, verify, patch, configure, stage
tools/build.sh <ia64|x86> [ALL|CLEAN]          # push staging/ and build with MMS
tools/test.sh <node>                           # DCL smoke test (to be written)
tools/kit.sh <node>                            # PCSI kit -> out/kits/
tools/installcheck.sh <node>                   # install kit, smoke-test it, remove (changes the system)
tools/vms_configure.sh <node>                  # once per upstream release: configure with VSI C
```

## VMS changes so far

| Patch / file | Why |
|---|---|
| `0001-getprogname-vms` | gnulib `getprogname()` from the image name (`JPI$_IMAGNAME`) |
| `0002-stdlib-vms-exit-severity` + `vms/vms_exit.c` | failures have error severity under DCL (exit 1, "files differ", is a warning); `$?` stays POSIX under GNV |
| `0003-config-h-assert-guard-vms` | VSI C `<assert.h>` include guard defeats gnulib's re-include |
| `0004-stdio-fwrite-records-vms` + `vms/vms_fwrite.c` | each `fwrite()` item became a record on record-oriented output |
| `vms/vms_crtl_init.c` | DECC$ features: ODS-5 names, Unix name reporting, argument case |

The four patches are vms-gzip's generic gnulib patches, rebased onto tar 1.35's older
gnulib. The main work ahead is in `CLAUDE.md` ("Known porting work"): compressors run through
`fork()`, and how to archive VMS record files.
