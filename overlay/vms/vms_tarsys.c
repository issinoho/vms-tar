/* vms_tarsys.c - tar's subprocess operations on OpenVMS.

   tar compresses and decompresses archives by forking the compressor and
   joining it to tar with pipes (src/system.c).  OpenVMS has no fork(), so
   here the archive passes through a temporary file instead:

   - Creating: tar writes the plain archive to a temporary file.  When the
     archive is closed, the compressor compresses that file in place
     (gzip, bzip2, xz and zstd all write NAME.<suffix> and delete NAME), and
     the result becomes the archive.
   - Reading: the archive is copied to a temporary NAME.<suffix>, the
     compressor decompresses it in place, and tar reads NAME.

   The compressors are the OpenVMS ports of the same family, found through
   the logical names their kits define: GZIP$ROOT, BZIP2$ROOT, XZ$ROOT and
   ZSTD$ROOT ([BIN]<name>.EXE).  They run in a subprocess (vms_spawn.c).

   --to-command, --info-script and --checkpoint-action=exec run arbitrary
   commands with a pipe or environment variables; they are not supported.

   Part of the OpenVMS port of GNU tar (github.com/issinoho/vms-tar);
   distributed under the GNU General Public License, version 3 or later.  */

#include <system.h>
#include <dirname.h>
#include <quotearg.h>
#include <xalloc.h>
#include "common.h"
#include <rmt.h>
#include "vms_spawn.h"

#include <descrip.h>
#include <lib$routines.h>
#include <fcntl.h>

/* The compressors tar can use on OpenVMS.  */
struct vms_zip
{
  char const *name;             /* as tar names the program */
  char const *image;            /* the image of its OpenVMS kit */
  char const *suffix;           /* what it appends when compressing */
  int warning;                  /* exit code that is only a warning, or 0 */
};

static struct vms_zip const vms_zips[] =
{
  { "gzip",  "GZIP$ROOT:[BIN]GZIP.EXE",   ".gz",  2 },
  { "bzip2", "BZIP2$ROOT:[BIN]BZIP2.EXE", ".bz2", 0 },
  { "xz",    "XZ$ROOT:[BIN]XZ.EXE",       ".xz",  2 },
  { "zstd",  "ZSTD$ROOT:[BIN]ZSTD.EXE",   ".zst", 0 },
};

enum { VMS_ARGS_MAX = 16 };

/* What close_archive has to finish.  */
static enum { VMS_NONE, VMS_COMPRESS, VMS_UNCOMPRESS } vms_mode;
static struct vms_zip const *vms_zip;
static char *vms_args[VMS_ARGS_MAX + 4];  /* compressor options from -I */
static char vms_plain[256];     /* the uncompressed temporary file */
static char vms_packed[256];    /* the compressed temporary file */

static void
vms_cleanup (void)
{
  if (vms_plain[0])
    vms_delete_all (vms_plain);
  if (vms_packed[0])
    vms_delete_all (vms_packed);
}

/* Find the compressor for PROGRAM (e.g. "gzip" or "zstd -T0"), and keep
   any options it carries.  Return null if it is not one of ours.  */
static struct vms_zip const *
vms_find_zip (char const *program)
{
  static char *copy;
  char *word, *base;
  size_t i;
  int n = 0;

  free (copy);
  copy = xstrdup (program);
  word = strtok (copy, " \t");
  if (!word)
    return NULL;
  base = last_component (word);
  for (i = 0; i < sizeof vms_zips / sizeof vms_zips[0]; i++)
    if (strcasecmp (base, vms_zips[i].name) == 0
        || (strncasecmp (base, vms_zips[i].name, strlen (vms_zips[i].name)) == 0
            && strcasecmp (base + strlen (vms_zips[i].name), ".exe") == 0))
      {
        while ((word = strtok (NULL, " \t")) && n < VMS_ARGS_MAX)
          vms_args[n++] = word;
        vms_args[n] = NULL;
        return &vms_zips[i];
      }
  return NULL;
}

/* Run the compressor on FILE, with OPTION (e.g. "-d") before the options
   from -I.  */
static void
vms_run_zip (char const *option, char const *file)
{
  char const *argv[VMS_ARGS_MAX + 6];
  int n = 0, i, rc;

  if (access (vms_zip->image, X_OK) != 0)
    FATAL_ERROR ((0, 0, _("cannot run %s: %s not found (is its OpenVMS kit "
                          "installed?)"), vms_zip->name, vms_zip->image));
  argv[n++] = vms_zip->name;
  if (option)
    argv[n++] = option;
  argv[n++] = "-f";
  for (i = 0; vms_args[i]; i++)
    argv[n++] = vms_args[i];
  argv[n++] = file;
  argv[n] = NULL;
  rc = vms_spawn_image ("TAR", vms_zip->image, argv, "NL:", "NL:");
  if (rc < 0)
    FATAL_ERROR ((0, 0, _("cannot run %s"), vms_zip->image));
  if (rc != 0 && rc != vms_zip->warning)
    FATAL_ERROR ((0, 0, _("Child returned status %d"), rc));
}

/* Copy the file FROM to TO, byte for byte (TO is a Stream_LF file, as
   creat() makes, which keeps the bytes exactly).  */
static bool
vms_copy (char const *from, char const *to)
{
  char buf[32 * 1024];
  ssize_t n;
  int in, out;
  bool ok = true;

  in = open (from, O_RDONLY);
  if (in < 0)
    return false;
  out = open (to, O_WRONLY | O_CREAT | O_TRUNC, MODE_RW);
  if (out < 0)
    {
      close (in);
      return false;
    }
  while ((n = read (in, buf, sizeof buf)) > 0)
    if (full_write (out, buf, n) != n)
      {
        ok = false;
        break;
      }
  if (n < 0)
    ok = false;
  if (close (out) != 0)
    ok = false;
  close (in);
  return ok;
}

static void
vms_temp_names (void)
{
  static bool registered;
  if (!registered)
    {
      atexit (vms_cleanup);
      registered = true;
    }
  vms_temp_name (vms_plain, sizeof vms_plain, "TAR", "ARCHIVE");
  /* The compressor names its output NAME.<suffix>: use no type, so that
     NAME. becomes NAME.gz rather than NAME.TMP.gz.  */
  vms_plain[strlen (vms_plain) - strlen (".TMP")] = '\0';
  snprintf (vms_packed, sizeof vms_packed, "%s%s", vms_plain, vms_zip->suffix);
}

static char const *
vms_archive_file (void)
{
  char const *name = archive_name_array[0];
  if (strcmp (name, "-") == 0 || _remdev (name))
    FATAL_ERROR ((0, 0, _("On OpenVMS a compressed archive must be a local "
                          "file, not standard input or output or a remote "
                          "archive")));
  return name;
}

/* Set ARCHIVE for writing, then compressing an archive.  */
pid_t
sys_child_open_for_compress (void)
{
  vms_zip = vms_find_zip (use_compress_program_option);
  if (!vms_zip)
    FATAL_ERROR ((0, 0, _("%s: compression program not supported on OpenVMS "
                          "(use gzip, bzip2, xz or zstd)"),
                  use_compress_program_option));
  vms_archive_file ();
  vms_temp_names ();
  archive = open (vms_plain, O_WRONLY | O_CREAT | O_TRUNC, MODE_RW);
  if (archive < 0)
    open_fatal (vms_plain);
  vms_mode = VMS_COMPRESS;
  return 0;
}

/* Set ARCHIVE for uncompressing, then reading an archive.  */
pid_t
sys_child_open_for_uncompress (void)
{
  char const *name = vms_archive_file ();
  char const *p;
  int i;

  vms_zip = NULL;
  for (p = first_decompress_program (&i); p && !vms_zip;
       p = next_decompress_program (&i))
    vms_zip = vms_find_zip (p);
  if (!vms_zip)
    FATAL_ERROR ((0, 0, _("%s: cannot decompress this archive on OpenVMS "
                          "(gzip, bzip2, xz and zstd are supported)"),
                  quotearg_colon (name)));
  vms_temp_names ();
  if (!vms_copy (name, vms_packed))
    {
      int e = errno;
      vms_cleanup ();
      FATAL_ERROR ((0, e, _("cannot copy %s to %s"),
                    quotearg_colon (name), vms_packed));
    }
  vms_run_zip ("-d", vms_packed);
  archive = open (vms_plain, O_RDONLY);
  if (archive < 0)
    open_fatal (vms_plain);
  vms_mode = VMS_UNCOMPRESS;
  return 0;
}

/* Called once the archive has been closed.  */
void
sys_wait_for_child (pid_t child_pid, bool eof)
{
  if (vms_mode == VMS_COMPRESS)
    {
      char const *name = archive_name_array[0];
      vms_mode = VMS_NONE;
      vms_run_zip (NULL, vms_plain);
      vms_plain[0] = '\0';      /* the compressor deleted it */
      /* Replace the archive, which may be on another device.  */
      if (rename (vms_packed, name) != 0)
        {
          if (!vms_copy (vms_packed, name))
            {
              int e = errno;
              FATAL_ERROR ((0, e, _("cannot copy %s to %s"),
                            vms_packed, quotearg_colon (name)));
            }
          vms_delete_all (vms_packed);
        }
      vms_packed[0] = '\0';
    }
  else if (vms_mode == VMS_UNCOMPRESS)
    {
      vms_mode = VMS_NONE;
      vms_cleanup ();
      vms_plain[0] = vms_packed[0] = '\0';
    }
}

/* Start an interactive DCL subprocess (the '!' answer to a volume prompt).  */
void
sys_spawn_shell (void)
{
  unsigned int status = lib$spawn (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  if (!(status & 1))
    ERROR ((0, 0, _("cannot start a DCL subprocess")));
}

int
sys_exec_command (char *file_name, int typechar, struct tar_stat_info *st)
{
  FATAL_ERROR ((0, 0, _("--to-command is not supported on OpenVMS")));
}

void
sys_wait_command (void)
{
}

int
sys_exec_info_script (const char **archive_name, int volume_number)
{
  ERROR ((0, 0, _("--info-script is not supported on OpenVMS")));
  return -1;
}

void
sys_exec_checkpoint_script (const char *script_name,
                            const char *archive_name,
                            int checkpoint_number)
{
  WARN ((0, 0, _("--checkpoint-action=exec is not supported on OpenVMS")));
}
