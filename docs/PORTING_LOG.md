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

## 2026-10-09: directories

`tar -cvf x.tar in` and `in/` now archive the whole tree (files, subdirectories, an empty directory), and extraction rebuilds it, on both nodes with status success.

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| L | `in: Cannot open: No such file or directory` for a directory | The C RTL cannot `open()` a directory by its Unix name (ENOENT; `stat()` works) | Patch 0008: gnulib's `open()` takes its directory fallback (`/dev/null` registered with the name, as on mingw) for ENOENT too; `openat.c` calls `rpl_open` on VMS, where there is no `openat()` |
| P | The fallback still failed with ENOENT | Registering the name calls `getcwd`; the PATH_MAX run test guessed "no", so gnulib's `getcwd` never called the C RTL's and walked `..` instead, which fails on VMS | `vms-manual.site`: `getcwd` is "partly working" and `getcwd (NULL, 0)` allocates (probed: it returns `/DISK$USER/USERNAME/X`) |
| P | `HAVE_GETPAGESIZE` now comes from Linux | A new host-run check came with the getcwd answer | none: nothing in tar calls it, and both nodes link clean |
| S | A failed run left DCL a success status | `main` returns instead of calling `exit()`, which patch 0003 routes through `vms_exit` | Patch 0008: on VMS `main` calls `exit()`; failures now give `%X1035A012` |
| F | `[.in]` (Cannot stat) and `in.dir` (Cannot savedir) | VMS-syntax names for a directory | D2: `vms_names.c` + patch 0009 convert VMS-syntax operands (command line, `-T`, `-C`) to Unix names |
| H | `%CC-E-NOTCOMPAT` on `rpl_mkdir` in `vms_names.c` | `<unixlib.h>` redeclares `mkdir` after gnulib replaced it | Declare `DECC$TRANSLATE_VMS` directly |

## 2026-10-09: program name

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| S | Messages began `/DISK$USER/USERNAME/VMS_TAR/tar-1_35/BIN_IA64/TAR.EXE:`; `--help` said `Usage: TAR.EXE` | On VMS `argv[0]` is the image's full file name | Patch 0010: on VMS `main` replaces `argv[0]` with `getprogname ()` ("tar", patch 0002). Verified on both nodes: errors, `--usage`, a bad option |

## 2026-10-09: smoke test

`[.VMS]TEST_SMOKE.COM` (run by `tools/test.sh`) passes 27 of 27 on both nodes. It covers:
- `--version`, a missing archive, and a corrupt archive;
- a tree created by its VMS, Unix and `.DIR` names, plus one file and `-C`;
- extraction, with the records compared and the empty directory checked;
- selecting one member by its VMS name;
- a binary round trip, compared by checksum;
- `-z` and `-J`, which are skipped without GZIP$ROOT or XZ$ROOT;
- DCL error severity.

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| L | A missing archive: "Cannot open: permission denied" | Patch 0008's directory fallback set EACCES when the name was not a directory, overwriting ENOENT | Patch 0008 keeps `open()`'s errno |
| F | `tar -czf x.tar.gz ...` exited 0, but the archive was in SYS$LOGIN, not the current directory | `rename()` takes a missing device and directory from the old name (as `$RENAME` does), and the old name was the temporary file in SYS$SCRATCH. The earlier tests named a directory (`[-]`, `../`) | `vms_tarsys.c` renames to `[]name` when the name has no directory |
