/* vms_fwrite.c - fwrite() through putc() on OpenVMS.

   For record-oriented output (a terminal, a log file, a mailbox) the VSI C
   RTL writes each fwrite() item as a record of its own, so diff's lines,
   written in pieces, appeared one piece (or one character) per line.
   putc() output is assembled into records at newlines.  lib/stdio.h
   (patch 0009) routes fwrite() here.  (As grep does in vms-grep.)

   Part of the OpenVMS port of GNU tar
   (github.com/issinoho/vms-tar); distributed under the GNU General
   Public License, version 3 or later.  */

#define VMS_FWRITE_IMPLEMENTATION 1
#include <config.h>
#include <stdio.h>

size_t
vms_fwrite (const void *ptr, size_t size, size_t n, FILE *stream)
{
  const unsigned char *p = ptr;
  size_t item, i;
  if (size == 0)
    return 0;
  for (item = 0; item < n; item++)
    for (i = 0; i < size; i++)
      if (putc (*p++, stream) == EOF)
        return item;
  return n;
}
