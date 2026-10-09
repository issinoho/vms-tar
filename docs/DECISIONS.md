# Design decisions

Each entry stays *proposed* until the user approves it.

## D1. Exact member sizes for record files: count the bytes
**Status:** approved by the user (2026-10-09).

tar writes a member's size into its header before the data. For a VMS record file, `st_size` counts the record structure, not the bytes `read()` returns. This applies to variable-length and VFC files, and to fixed-length files with carriage control, where the C RTL adds a newline per record.

- **The symptom:** a DCL-written text file of 79 bytes of lines had `st_size` 92. tar archived 13 NULs after the text and warned "file changed as we read it" (exit status 1).
- **Where `st_size` is exact:** stream files (STM, STMLF, STMCR), and fixed or undefined-format files without carriage control.
- **For every other file:** `vms/vms_datasize.c` reads the file once to count the bytes, then seeks back. Patch 0007 makes tar use that count for the header and compare the raw `st_size` in its "file changed" check.

Cost: record files are read twice. That's acceptable next to the alternatives.

**Alternatives rejected:**
- Copying each record file to a temporary stream file first: more I/O and scratch space.
- Archiving `st_size` as is: corrupt members.

Verified on both nodes: VAR, VFC (print carriage control), FIX 80 with CR, Stream_LF and FIX 512 binary archive with exact sizes and status success, and the text files extract with identical records.

Extracted files are Stream_LF. A binary's original record format (e.g. FIX 512) is not restored, as in vms-gzip.
