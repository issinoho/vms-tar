/* vms_spawn.h - run a program in a subprocess on OpenVMS.  */
#ifndef VMS_SPAWN_H
#define VMS_SPAWN_H

/* Run the image IMAGE with the arguments ARGV[1...] (ARGV ends with a null
   pointer), its standard input and output being the files IN and OUT
   (e.g. "NL:").  Return its exit code (0 for success), or -1 if it could
   not be run.  PREFIX names the temporary files in SYS$SCRATCH.  */
int vms_spawn_image (char const *prefix, char const *image,
                     char const *const *argv,
                     char const *in, char const *out);

/* Write a new temporary file name for PREFIX and WHAT into BUF.  */
void vms_temp_name (char *buf, int size, char const *prefix, char const *what);

/* Delete every version of NAME.  */
void vms_delete_all (char const *name);

#endif
