/* vms_datasize.c - the number of bytes read() returns for a file on OpenVMS.

   tar writes a member's size into its header before the data, so the size
   must be exact.  For a record file, st_size counts the record structure
   (length words, padding) rather than the bytes the C RTL's read() returns:
   a variable-length text file of 79 bytes of lines can have st_size 92, so
   tar archived 13 NULs after the text and warned that the file changed.

   st_size is exact for stream files (STM, STMLF, STMCR), and for fixed or
   undefined-format files without carriage control (read() returns the
   records as they are).  For any other file (variable-length, VFC, or with
   carriage control, where read() adds a newline per record), count the
   bytes by reading the file once, then seek back.

   Part of the OpenVMS port of GNU tar (github.com/issinoho/vms-tar);
   distributed under the GNU General Public License, version 3 or later.  */

#include <config.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <fabdef.h>

off_t vms_data_size (int fd, struct stat const *st);

off_t
vms_data_size (int fd, struct stat const *st)
{
  static char buf[32768];
  int rfm = (unsigned char) st->st_fab_rfm;
  int rat = (unsigned char) st->st_fab_rat;
  off_t n = 0, here;
  ssize_t r;

  if (rfm == FAB$C_STM || rfm == FAB$C_STMLF || rfm == FAB$C_STMCR)
    return st->st_size;
  if ((rfm == FAB$C_FIX || rfm == FAB$C_UDF)
      && !(rat & (FAB$M_CR | FAB$M_FTN | FAB$M_PRN)))
    return st->st_size;

  here = lseek (fd, 0, SEEK_CUR);
  if (here < 0 || lseek (fd, 0, SEEK_SET) != 0)
    return st->st_size;
  while ((r = read (fd, buf, sizeof buf)) > 0)
    n += r;
  if (r < 0)
    n = st->st_size;            /* let tar's own read report the error */
  lseek (fd, here, SEEK_SET);
  return n;
}
