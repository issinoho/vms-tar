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

## D2. VMS-syntax file operands: translate to Unix names
**Status:** approved by the user (2026-10-09); implemented in `vms/vms_names.c` and patch 0009.

Directories given by Unix name (`tar -cf x.tar in`, `in/`) work (patch 0008). The VMS forms don't:
- `[.in]`: "Cannot stat"
- `in.dir`: the directory file opens as a file, then "Cannot savedir: not a directory"

Even if they opened, the member names would be `[.in]/top.txt`, which no other tar can use.

**Decision:** on VMS, tar translates every file operand in VMS syntax (it has `[`, `<`, a device `:` or a `;version`, or it is a `.DIR` naming a directory) to its Unix form before using it. That covers names on the command line and in `-T` lists, for create, list/extract selection and `-C`. The C RTL's `decc$translate_vms` does the conversion:
- `[.in]` → `in`
- `[.in]top.txt;1` → `in/top.txt`
- `[-.a]b.c` → `../a/b.c`
- `in.dir` → `in`
- `DKA0:[x]y` → `/DKA0/x/y` (tar then strips the leading `/`, as for any absolute name)

The archive name after `-f` needs nothing: the C RTL opens both syntaxes, as the compressed-archive tests showed.

**Alternative:** accept Unix names only and document that. That costs no code, but DCL users naturally type `[.dir]`.

Verified on both nodes: `[.in]`, `in.dir`, `[.in.sub]mid.txt;1`, a `-T` list of VMS names, `-C [.in]`, and extracting one member named `[.in.sub]mid.txt` all work, giving the same member names as the Unix forms. Not converted: `[.in...]` (decc$translate_vms rejects it; tar reports it), and a bare ODS-5 escape such as `a^.b` with no other VMS syntax, which stays as typed.
