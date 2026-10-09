/* vms_crtl_init.c - set C RTL feature switches before main() runs.

   Called through LIB$INITIALIZE.  Each feature is set only if the user has
   not defined the corresponding DECC$ logical name, so a site can still
   override any of them.

   Part of the OpenVMS port of GNU tar (from the GNU grep port); distributed under the GNU
   General Public License, version 3 or later.  */

#include <config.h>

#include <stdlib.h>
/* gnulib renames getcwd and mkdir (lib/unistd.h, lib/sys/stat.h);
   <unixlib.h> redeclares the CRTL's versions, which would then clash.
   Neither is used here.  */
#undef getcwd
#undef mkdir
#include <unixlib.h>

struct feature { const char *name; int value; };

static const struct feature features[] = {
  /* Keep the case of command-line arguments when the process has
     SET PROCESS/PARSE_STYLE=EXTENDED.  */
  { "DECC$ARGV_PARSE_STYLE", 1 },
  /* ODS-5 extended file names, case preserved.  */
  { "DECC$EFS_CHARSET", 1 },
  { "DECC$EFS_CASE_PRESERVE", 1 },
  /* Report file names in Unix form, as grep prints them back.  */
  { "DECC$FILENAME_UNIX_REPORT", 1 },
  { "DECC$FILENAME_UNIX_NO_VERSION", 1 },
  /* readdir() returns "foo", not "foo.", for files without a type.  */
  { "DECC$READDIR_DROPDOTNOTYPE", 1 },
  /* Prefer a Unix path over a same-named logical name.  */
  { "DECC$UNIX_PATH_BEFORE_LOGNAME", 1 },
  /* Allow other processes to read files grep has open.  */
  { "DECC$FILE_SHARING", 1 },
};

static void
vms_crtl_init (void)
{
  size_t i;
  for (i = 0; i < sizeof features / sizeof features[0]; i++)
    {
      int index;
      if (getenv (features[i].name) != NULL)
        continue;
      index = decc$feature_get_index (features[i].name);
      if (index >= 0)
        decc$feature_set_value (index, 1, features[i].value);
    }
}

/* Contribute vms_crtl_init to the LIB$INITIALIZE table.  The table entries
   must be 32-bit pointers in a psect with these exact attributes.  */
#pragma nostandard
#pragma extern_model save
#pragma extern_model strict_refdef "LIB$INITIALIZE" nopic, con, rel, gbl, noshr, noexe, nowrt, novec, long
#if __INITIAL_POINTER_SIZE
# pragma __pointer_size __save
# pragma __pointer_size 32
#else
# pragma __required_pointer_size __save
# pragma __required_pointer_size 32
#endif
void (* const vms_crtl_init_entry[]) (void) = { vms_crtl_init };
#if __INITIAL_POINTER_SIZE
# pragma __pointer_size __restore
#else
# pragma __required_pointer_size __restore
#endif

/* Reference LIB$INITIALIZE so the linker includes it in the image.  */
int LIB$INITIALIZE (void);
#pragma extern_model strict_refdef
int vms_lib_initialize_ref = (int) LIB$INITIALIZE;
#pragma extern_model restore
#pragma standard
