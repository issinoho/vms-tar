$! TAR$STARTUP.COM - system startup for GNU tar on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! TAR$ROOT, pointing at the installed [TAR] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:TAR$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign TAR$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the commands with
$!     $ @TAR$ROOT:[000000]TAR$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("TAR$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode TAR$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[TAR].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.TAR.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "TAR.]"
$ if root .eqs. dir + "TAR.]"
$ then
$   write sys$error "TAR$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed TAR$ROOT 'dev''root'
$ if f$search("TAR$ROOT:[BIN]TAR.EXE") .eqs. ""
$ then
$   write sys$error "TAR$STARTUP: TAR.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for GNU tar"
$ say ""
$ say "    At system startup: to define TAR$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:TAR$STARTUP.COM"
$ say "    For each user: to define the commands, add this line to LOGIN.COM:"
$ say "    $ @TAR$ROOT:[000000]TAR$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE TAR removes the product and deassigns TAR$ROOT."
$ say ""
$ exit 1
