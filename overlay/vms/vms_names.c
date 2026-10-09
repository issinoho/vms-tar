/* vms_names.c - file operands in VMS syntax, as Unix names (DECISIONS D2).

   tar names a member after the operand it was given, so "[.in]" would make
   members called "[.in]/top.txt" (if it could open the directory at all:
   the C RTL stats "[.in]" but tar's openat path does not), and "in.dir"
   opens the directory file as a plain file.  On VMS, tar passes every file
   operand (command line, -T lists and -C) through vms_unix_name first:

     [.in]            -> in
     [.in]top.txt;1   -> in/top.txt
     [-.a]b.c         -> ../a/b.c
     in.dir           -> in          (only when it is a directory)
     DKA0:[x]y        -> /DKA0/x/y   (tar strips the leading "/" as usual)

   A name with a "/" is already a Unix name and is left alone, as is one
   with none of "[", "<", ":", ";" and no ".DIR" ending.  The conversion is
   the C RTL's decc$translate_vms; a name it cannot convert ("[.in...]") is
   left as it is, and tar reports it.

   Part of the OpenVMS port of GNU tar (github.com/issinoho/vms-tar);
   distributed under the GNU General Public License, version 3 or later.  */

#include <config.h>

#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/stat.h>

/* decc$translate_vms, declared here: <unixlib.h> clashes with gnulib's
   mkdir replacement.  Upper case, as the C RTL exports it (/NAMES=AS_IS).  */
extern char *DECC$TRANSLATE_VMS (char const *vms_filespec);

char *vms_unix_name (char const *name);

static int
ends_in_dir (char const *name, size_t len)
{
  return len > 4 && strcasecmp (name + len - 4, ".dir") == 0;
}

/* NAME in Unix syntax: NAME itself (cast) when it needs no change,
   otherwise a new string from malloc.  */
char *
vms_unix_name (char const *name)
{
  char *unix_name, *r;
  size_t len;
  struct stat st;

  if (strchr (name, '/'))
    return (char *) name;
  len = strlen (name);
  if (!strpbrk (name, "[<:;") && !ends_in_dir (name, len))
    return (char *) name;

  r = DECC$TRANSLATE_VMS (name);
  if (r == NULL || r == (char *) -1)
    return (char *) name;
  while (r[0] == '.' && r[1] == '/')
    r += 2;
  unix_name = strdup (*r ? r : ".");
  if (unix_name == NULL)
    return (char *) name;

  /* "in.dir" names the directory "in".  */
  len = strlen (unix_name);
  if (ends_in_dir (unix_name, len)
      && stat (unix_name, &st) == 0 && S_ISDIR (st.st_mode))
    unix_name[len - 4] = '\0';
  return unix_name;
}
