$! TEST_SMOKE.COM - quick functional check of a built or installed TAR.EXE
$!
$! Usage:  @[.VMS]TEST_SMOKE [tar-image]
$!         The default image is [.BIN_<arch>]TAR.EXE in this tree.
$! Exits with SS$_NORMAL if every test passes, otherwise reports failures.
$! The compressed-archive tests run only where the family's compressor kits
$! are installed (GZIP$ROOT, XZ$ROOT); otherwise they are reported as SKIP.
$!
$ set noon
$ on control_y then goto finish
$ saved_default = f$environment("DEFAULT")
$ saved_parse = f$getjpi("", "PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ image = p1
$ if image .eqs. "" then image = f$parse("[.BIN_''arch']TAR.EXE")
$ if f$search(image) .eqs. ""
$ then
$   write sys$error "SMOKE: no image ''image'"
$   exit 44
$ endif
$ tar := $'image'
$ pass == 0
$ fail == 0
$ skip == 0
$! Start from an empty work directory each run.
$ if f$search("SMOKE_TMP.DIR") .eqs. "" then create/directory [.SMOKE_TMP]
$ set default [.SMOKE_TMP]
$ call emptydir
$!
$! --- fixtures -------------------------------------------------------------
$! CREATE writes variable-length records: a VMS text file, whose st_size
$! counts record overhead (DECISIONS D1).
$ create ref.txt
the first line
line two, a little longer than the first
line three
$ create/directory [.tree.sub]
$ create/directory [.tree.empty]
$ copy/nolog ref.txt [.tree]one.txt
$ copy/nolog ref.txt [.tree.sub]two.txt
$ create bad.tar
this is not a tar archive
$!
$! --- tests: name, expected exit code, expected output (| = newline), args --
$ call t version   0 ""  "--version"
$ call t missing   2 "tar: nosuch.tar: Cannot open: no such file or directory|tar: Error is not recoverable: exiting now" "-tf nosuch.tar"
$ call t corrupt   2 "tar: This does not look like a tar archive|tar: Exiting with failure status due to previous errors" "-tf bad.tar"
$!
$! A tree by its VMS name; the members get Unix names (DECISIONS D2).
$ treelist = "tree/|tree/empty/|tree/one.txt|tree/sub/|tree/sub/two.txt"
$ call t create-vms  0 ""          "-cf t1.tar [.tree]"
$ call t list-vms    0 "''treelist'"  "-tf t1.tar"
$ call t create-unix 0 ""          "-cf t2.tar tree"
$ call t list-unix   0 "''treelist'"  "-tf t2.tar"
$ call t create-dir  0 ""          "-cf t3.tar tree.dir"
$ call t list-dir    0 "''treelist'"  "-tf t3.tar"
$ call t create-file 0 ""          "-cf t4.tar [.tree.sub]two.txt;1"
$ call t list-file   0 "tree/sub/two.txt" "-tf t4.tar"
$ call t create-c    0 ""          "-cf t5.tar -C [.tree] one.txt"
$ call t list-c      0 "one.txt"   "-tf t5.tar"
$!
$! Extract the tree: the text comes back record for record, and the empty
$! directory is created.
$ create/directory [.x1]
$ set default [.x1]
$ call t extract   0 ""  "-xf [-]t1.tar"
$ set default [-]
$ call same TEXT-ROUNDTRIP [.x1.tree]one.txt []ref.txt
$ call same TREE-ROUNDTRIP [.x1.tree.sub]two.txt []ref.txt
$ call check EMPTY-DIR "f$search(""[.x1.tree]empty.dir"") .nes. """""
$!
$! One member, selected by its VMS name.
$ create/directory [.x2]
$ set default [.x2]
$ call t extract-one 0 ""  "-xf [-]t1.tar [.tree.sub]two.txt"
$ set default [-]
$ call check ONE-ONLY "f$search(""[.x2.tree.sub]two.txt"") .nes. """" .and. f$search(""[.x2.tree]one.txt"") .eqs. """""
$!
$! Binary data (fixed-length 512-byte records, as an image or a kit) is
$! archived byte for byte.  tar writes Stream_LF; with the record
$! attributes set back, the file must be identical to the original.
$ copy/nolog 'image' bin.exe
$ call t binary    0 ""  "-cf t6.tar bin.exe"
$ create/directory [.x3]
$ set default [.x3]
$ call t unbinary  0 ""  "-xf [-]t6.tar"
$ set default [-]
$ set file/attributes=(rfm:fix,lrl:512,mrs:512,rat:none) [.x3]bin.exe
$ checksum [.x3]bin.exe
$ c1 = checksum$checksum
$ checksum bin.exe
$ if c1 .eq. checksum$checksum
$ then
$   write sys$output "PASS BINARY-ROUNDTRIP"
$   pass == pass + 1
$ else
$   write sys$output "FAIL BINARY-ROUNDTRIP: checksum ''c1' (want ''checksum$checksum')"
$   fail == fail + 1
$ endif
$!
$! Compressed archives, through the family's compressor kits.
$ if f$trnlnm("GZIP$ROOT") .nes. ""
$ then
$   call t create-gz 0 ""         "-czf t7.tar.gz [.tree]"
$   call t list-gz   0 "''treelist'" "-tf t7.tar.gz"
$ else
$   write sys$output "SKIP GZIP (no GZIP$ROOT)"
$   skip == skip + 1
$ endif
$ if f$trnlnm("XZ$ROOT") .nes. ""
$ then
$   call t create-xz 0 ""         "-cJf t8.tar.xz [.tree]"
$   call t list-xz   0 "''treelist'" "-tf t8.tar.xz"
$ else
$   write sys$output "SKIP XZ (no XZ$ROOT)"
$   skip == skip + 1
$ endif
$!
$! Under DCL a failure must have error severity, so ON ERROR and
$! IF .NOT. $STATUS see it.
$ define/user sys$output nl:
$ define/user sys$error nl:
$ tar -tf nosuch.tar
$ if $severity .eq. 2
$ then
$   write sys$output "PASS SEVERITY"
$   pass == pass + 1
$ else
$   write sys$output "FAIL SEVERITY: $SEVERITY ''$severity' (want 2)"
$   fail == fail + 1
$ endif
$!
$finish:
$ set default 'vmsdir'
$ set default [-]
$ set process/parse_style='saved_parse'
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed, ''skip' skipped (''image')"
$ set default 'saved_default'
$ if fail .eq. 0 .and. pass .gt. 0 then exit 1
$ exit 44
$!
$! --- T name expected-exit expected-output args -------------------------
$t: subroutine
$ set noon
$ if f$search("out.txt") .nes. "" then delete/nolog out.txt;*
$ if f$search("err.txt") .nes. "" then delete/nolog err.txt;*
$! Separate files: two streams on one name would make two versions.
$ define/user sys$output out.txt
$ define/user sys$error err.txt
$ tar 'p4'
$ st = $status
$! _POSIX_EXIT: the C exit code is in bits 3..10 of the VMS status.
$ code = (st .and. %X7F8) / 8
$ got = ""
$ do = "out.txt"
$readfile:
$ if f$search(do) .eqs. "" then goto nextfile
$ open/read f 'do'
$readloop:
$ read/end=readdone f line
$ if got .nes. "" then got = got + "|"
$ got = got + f$edit(line, "TRIM,COMPRESS")
$ if f$length(got) .gt. 300 then goto readdone
$ goto readloop
$readdone:
$ close f
$nextfile:
$ if do .eqs. "err.txt" then goto compare
$ do = "err.txt"
$ goto readfile
$compare:
$ ok = code .eq. f$integer(p2)
$! (DCL upper-cases the unquoted test name.)
$ if p1 .nes. "VERSION" then ok = ok .and. (got .eqs. f$edit(p3, "TRIM,COMPRESS"))
$ if p1 .eqs. "VERSION" then ok = ok .and. (f$locate("tar (GNU tar) 1.", got) .eq. 0)
$ if ok
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": exit ", code, " (want ", p2, "), output [", got, "] (want [", p3, "])"
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
$!
$! --- CHECK name dcl-expression ----------------------------------------
$check: subroutine
$ if 'p2'
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": ", p2
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
$!
$! --- SAME name file1 file2: the files have the same records ------------
$same: subroutine
$ set noon
$ if f$search("same.dif") .nes. "" then delete/nolog same.dif;*
$ define/user sys$error nl:
$ differences/output=same.dif 'p2' 'p3'
$ search/nooutput same.dif "Number of difference records found: 0"
$ if $severity .eq. 1
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": ''p2' and ''p3' differ"
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
$!
$! --- EMPTYDIR: delete everything below the current directory ------------
$! Directory files must be writable and empty to go, so repeat the delete
$! until nothing is left (the tests nest three levels below [.SMOKE_TMP]).
$emptydir: subroutine
$ set noon
$ if f$search("[...]*.*;*") .eqs. "" then exit 1
$ define/user sys$output nl:
$ define/user sys$error nl:
$ set protection=(s:rwed,o:rwed) [...]*.*;*
$ n = 0
$emptyloop:
$ define/user sys$output nl:
$ define/user sys$error nl:
$ delete/nolog [...]*.*;*
$ n = n + 1
$ if f$search("[...]*.*;*") .nes. "" .and. n .lt. 6 then goto emptyloop
$ exit 1
$ endsubroutine
