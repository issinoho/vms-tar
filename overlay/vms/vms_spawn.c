/* vms_spawn.c - run a program in a subprocess on OpenVMS.

   OpenVMS has no fork(), and a child started with vfork()/execv() inherits
   the parent's SYS$OUTPUT: when that is redirected to a file the child
   opens it again, leaving a new, empty version of the user's file.  So the
   program runs in a subprocess (LIB$SPAWN) executing a small generated DCL
   procedure that drops the SYS$OUTPUT and SYS$ERROR it inherits, points
   its own SYS$INPUT and SYS$OUTPUT at the given files, and runs the image
   with every argument quoted, so DCL keeps their case.  The subprocess's
   own output (the image's messages) goes to a temporary log, copied to
   stderr afterwards.  (As in vms-bison and vms-flex.)

   Part of the OpenVMS port of GNU tar
   (github.com/issinoho/vms-tar); distributed under the GNU General
   Public License, version 3 or later.  */

#include <config.h>
#include "vms_spawn.h"

#include <descrip.h>
#include <lib$routines.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

void
vms_delete_all (char const *name)
{
  char spec[256];
  struct dsc$descriptor_s d;
  snprintf (spec, sizeof spec, "%s;*", name);
  d.dsc$w_length = (unsigned short) strlen (spec);
  d.dsc$b_dtype = DSC$K_DTYPE_T;
  d.dsc$b_class = DSC$K_CLASS_S;
  d.dsc$a_pointer = spec;
  lib$delete_file (&d, 0, 0, 0, 0, 0, 0, 0, 0, 0);
}

void
vms_temp_name (char *buf, int size, char const *prefix, char const *what)
{
  static unsigned int counter;
  snprintf (buf, size, "SYS$SCRATCH:%s_%08X_%u_%s.TMP",
            prefix, (unsigned int) getpid (), ++counter, what);
}

int
vms_spawn_image (char const *prefix, char const *image,
                 char const *const *argv, char const *in, char const *out)
{
  char com[96], log[96], spawncmd[112];
  struct dsc$descriptor_s cmd_d, log_d;
  unsigned int status, completion = 0;
  char const *const *a;
  FILE *c;
  int rc;

  vms_temp_name (com, sizeof com, prefix, "COM");
  vms_temp_name (log, sizeof log, prefix, "LOG");
  c = fopen (com, "w");
  if (!c)
    return -1;
  fputs ("$ set noon\n"
         "$ set message/nofacility/noseverity/noidentification/notext\n"
         "$ if f$trnlnm(\"SYS$OUTPUT\",\"LNM$PROCESS\",,\"USER\") .nes. \"\""
         " then deassign/user sys$output\n"
         "$ if f$trnlnm(\"SYS$OUTPUT\",\"LNM$PROCESS\",,\"SUPERVISOR\") .nes. \"\""
         " then deassign sys$output\n"
         "$ if f$trnlnm(\"SYS$ERROR\",\"LNM$PROCESS\",,\"USER\") .nes. \"\""
         " then deassign/user sys$error\n"
         "$ if f$trnlnm(\"SYS$ERROR\",\"LNM$PROCESS\",,\"SUPERVISOR\") .nes. \"\""
         " then deassign sys$error\n"
         "$ set message/facility/severity/identification/text\n", c);
  fprintf (c, "$ define/user sys$input %s\n", in);
  fprintf (c, "$ define/user sys$output %s\n", out);
  fprintf (c, "$ mcr %s", image);
  /* One argument per line: DCL limits the length of a record.  */
  for (a = argv + 1; *a; a++)
    {
      char const *p;
      fputs (" -\n \"", c);
      for (p = *a; *p; p++)
        {
          if (*p == '"')
            putc ('"', c);      /* DCL doubles quotes */
          putc (*p, c);
        }
      putc ('"', c);
    }
  fputs ("\n$ exit $status\n", c);
  if (fclose (c) != 0)
    {
      vms_delete_all (com);
      return -1;
    }

  snprintf (spawncmd, sizeof spawncmd, "@%s", com);
  cmd_d.dsc$w_length = (unsigned short) strlen (spawncmd);
  cmd_d.dsc$b_dtype = DSC$K_DTYPE_T;
  cmd_d.dsc$b_class = DSC$K_CLASS_S;
  cmd_d.dsc$a_pointer = spawncmd;
  log_d.dsc$w_length = (unsigned short) strlen (log);
  log_d.dsc$b_dtype = DSC$K_DTYPE_T;
  log_d.dsc$b_class = DSC$K_CLASS_S;
  log_d.dsc$a_pointer = log;
  fflush (stdout);
  fflush (stderr);
  status = lib$spawn (&cmd_d, 0, &log_d, 0, 0, 0, &completion,
                      0, 0, 0, 0, 0, 0);
  vms_delete_all (com);
  c = fopen (log, "r");
  if (c)
    {
      int ch;
      while ((ch = getc (c)) != EOF)
        putc (ch, stderr);
      fclose (c);
    }
  vms_delete_all (log);
  if (!(status & 1))
    return -1;
  if (completion & 1)
    return 0;
  /* A C program's exit (N) is %X35A000 + N*8 + severity (see vms_exit.c);
     anything else is a VMS condition: report it as 2 (trouble).  */
  rc = (completion & 0x7F8) >> 3;
  if ((completion & 0x0FFFF800) != 0x0035A000 || rc == 0)
    rc = 2;
  return rc;
}
