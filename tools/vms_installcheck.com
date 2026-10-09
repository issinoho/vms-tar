$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the TAR kit, verify, smoke-test
$! the installed image, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[TAR], system logical TAR$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install TAR /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product TAR /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:TAR$STARTUP.COM"), "]"
$ show logical TAR$ROOT
$ directory/nohead/notrail TAR$ROOT:[000000...]*.*
$ @TAR$ROOT:[000000]TAR$SETUP.COM
$ show symbol tar
$ tar "--version"
$ write sys$output "=== SMOKE TEST on installed image"
$ smoke = tree - "]" + ".VMS]TEST_SMOKE.COM"
$ @'smoke' TAR$ROOT:[BIN]TAR.EXE
$ write sys$output "=== REMOVE"
$ product remove TAR /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "TAR$ROOT after removal: [", f$trnlnm("TAR$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[TAR...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:TAR$STARTUP.COM"), "]"
$ product show product TAR /producer=ISSINOHO
$ delete/symbol/global tar
