$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the DIFFUTILS kit, verify, smoke-test
$! the installed image, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[DIFFUTILS], system logical DIFFUTILS$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install DIFFUTILS /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product DIFFUTILS /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:DIFFUTILS$STARTUP.COM"), "]"
$ show logical DIFFUTILS$ROOT
$ directory/nohead/notrail DIFFUTILS$ROOT:[000000...]*.*
$ @DIFFUTILS$ROOT:[000000]DIFFUTILS$SETUP.COM
$ show symbol gdiff
$ show symbol cmp
$ gdiff --version
$ write sys$output "=== SMOKE TEST on installed image"
$ smoke = tree - "]" + ".VMS]TEST_SMOKE.COM"
$ @'smoke' DIFFUTILS$ROOT:[BIN]
$ write sys$output "=== REMOVE"
$ product remove DIFFUTILS /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "DIFFUTILS$ROOT after removal: [", f$trnlnm("DIFFUTILS$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[DIFFUTILS...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:DIFFUTILS$STARTUP.COM"), "]"
$ product show product DIFFUTILS /producer=ISSINOHO
$ delete/symbol/global gdiff
$ delete/symbol/global cmp
$ delete/symbol/global diff3
$ delete/symbol/global sdiff
