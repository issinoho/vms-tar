$! TAR$SETUP.COM - define the GNU tar commands for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @TAR$ROOT:[000000]TAR$SETUP.COM
$!
$! Quote upper-case options, or SET PROCESS/PARSE_STYLE=EXTENDED: traditional DCL
$! parsing changes the case of unquoted arguments; batch jobs use the traditional style.
$!
$ if f$trnlnm("TAR$ROOT") .eqs. ""
$ then
$   write sys$error "TAR$SETUP: TAR$ROOT is not defined; run TAR$STARTUP.COM first"
$   exit 44
$ endif
$ tar :== $TAR$ROOT:[BIN]TAR.EXE
$ exit 1
