# Porting log

One entry per build or run problem, newest last. Triage codes:
- T toolchain
- P probe or configure
- H header
- L libc (CRTL)
- F filesystem
- S shell or process
- U upstream

## 2026-10-09: first builds (IA64 V8.4-2L3, x86-64 E9.2-4)

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| T | configure: "C compiler cannot create executables" | The VMS sshd closes a multiplexed ControlMaster when its first sftp session opens | `vmscc` and `vms_configure.sh` give sftp the key (86c7109) |
| P | configure answers identical on both nodes | Normal (as vms-gzip): the two C RTLs agree on every test; `vms-manual.site` settles `pthread_sigmask` | none |
| P | `HAVE_ICONV 1` inherited from Linux | iconv is in the C RTL on both; conversions need `SYS$I18N_ICONV` tables (x86: ISO8859-1 <-> UTF-8; IA64: none). tar keeps pax names unchanged when a conversion fails | Recorded in `vms-manual.site` |
| H | 523 UNMATCHENDIF, 151 DECLARATOR, implicit `vms_exit` | Patch 0003's `#if defined __VMS` had lost its `#` when it was rebased from vms-gzip | Patch fixed (6d24389) |
| H | `<malloc/scratch_buffer.gl.h>` not found | VSI C cannot open a name with two dots | `prepare.sh` rewrites the includes to the `_gl.h` copies |
| L | `fork`, `initgroups` undeclared in `rtapelib.c`, `misc.c` | Remote archives (`[user@]host:file` over rsh) | Patch 0006: no name is remote on VMS (every `DKA0:[DIR]X.TAR` has a colon); `xfork` and the rsh child helper are not built |
| H | DECLARATOR in `scratch_buffer_gl.h` (4 files; hence `canonicalize_file_name` undefined) | The union member `__align` is a reserved word in VSI C | `prepare.sh` renames it `__gl_align` |
| P | `program_invocation_name` undefined at link | That link test keeps no cache variable, so `prepare.sh`'s host run found glibc's; the VSI C run had found none | `prepare.sh` corrects `HAVE_PROGRAM_INVOCATION_NAME`/`_SHORT_NAME`; `argp-pin.c` supplies them |
| T | `parse_datetime` undefined | The automake list names `parse-datetime.y` | `prepare.sh` takes the shipped `.c` |
| – | Warnings left | `%zu`/`%jd` in `rtapelib.c` (unreachable on VMS); INTOVERFL in gnulib's `ckd_sub` fallback (constant branch) | none needed |
| F | A text file archived with NUL padding, "file changed as we read it" | Record files' `st_size` is not what `read()` returns | D1: `vms_datasize.c` + patch 0007 |

## 2026-10-09: compressed archives

`-z`, `-j`, `-J` and `--zstd` (GitHub's `vms_tarsys.c` and `vms_spawn.c`: a temporary file and the family's own gzip, bzip2, xz and zstd kits) work on both nodes:
- create, list with automatic detection, and extract all exit with status success;
- the records round-trip, and no `SYS$SCRATCH:TAR_*` files are left;
- the archives read correctly with GNU tar on Linux, with the binary byte-identical;
- names with two dots work: `rt^.tar.gz` (VMS syntax) and `../rt2.tar.gz` (Unix syntax).

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| S | zstd printed progress lines on every compressed create or extract | The compressor's SYS$ERROR is the user's terminal; zstd reports progress there | `vms_tarsys.c` passes `-q` to every compressor (all four take it) |
