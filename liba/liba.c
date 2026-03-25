#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <mono/metadata/class-internals.h>
#include <mono/mini/interp/interp-internals.h>
#include <mono/mini/mini-runtime.h>
#include <mono/mini/mini.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wint-conversion"

int32_t _mincore(void *addr, void *length, void *vec) {
  return mincore(addr, length, vec);
}

int32_t _mkstemp(void *template) { return mkstemp(template); }

void *_mmap(void *addr, void *length, int32_t prot, int32_t flags, int32_t fd,
            int32_t offset) {
  return mmap(addr, length, prot, flags, fd, offset);
}

int32_t _mprotect(void *addr, void *len, int32_t prot) {
  // return mprotect(addr, len, prot);
  return 0;
}

int _munmap(void *addr, size_t len) { return munmap(addr, len); }

int _pipe2(int pipefd[2], int flags) {
  // return pipe2(pipefd, flags);
  return 0;
}

void *_read(int fd, void *buf, void *count) { return read(fd, buf, count); }

void *_write(int fd, const void *buf, void *count) {
  return write(fd, buf, count);
}

int64_t _sysconf(int32_t name) { return sysconf(name); }

int32_t _uname(void *x) { return uname(x); }

static InterpMethod *ftnptr_to_imethod_local(gpointer ftnptr) {
  if (!ftnptr)
    return NULL;

  if (mono_llvm_only) {
    MonoFtnDesc *ftndesc = (MonoFtnDesc *)ftnptr;
    if (!ftndesc || !ftndesc->method)
      return NULL;

    if (!ftndesc->interp_method) {
      InterpMethod *imethod = mono_interp_get_imethod(ftndesc->method);
      ftndesc->interp_method = imethod;
    }

    return INTERP_IMETHOD_UNTAG_UNBOX(ftndesc->interp_method);
  }

  return INTERP_IMETHOD_UNTAG_UNBOX(ftnptr);
}

MonoMethodHeader *get_header(gpointer ftnptr) {
  InterpMethod *mono = ftnptr_to_imethod_local(ftnptr);
  if (!mono || !mono->method)
    return NULL;
  if (mono->method->klass)
    mono_class_get_image(mono->method->klass)->has_updates = FALSE;
  MonoMethodHeader *header = mono_method_get_header(mono->method);
  if (mono->method->klass)
    mono_class_get_image(mono->method->klass)->has_updates = TRUE;
  return header;
}

const void *magictranslate(gpointer ftnptr) {
  InterpMethod *mono = ftnptr_to_imethod_local(ftnptr);
  MonoMethodHeader *header = get_header(ftnptr);
  if (!header)
    return NULL;

  const void *code = header->code;

  mono_metadata_free_mh(header);
  return code;
}

uint32_t magictranslatelen(gpointer ftnptr) {
  MonoMethodHeader *header = get_header(ftnptr);
  if (!header)
    return 0;

  uint32_t code_size = header->code_size;

  mono_metadata_free_mh(header);
  return code_size;
}

void magicinvalidate(gpointer ftnptr) {
  InterpMethod *mono = ftnptr_to_imethod_local(ftnptr);
  if (!mono)
    return;
  mono->transformed = 0;
}

extern void hot_reload_insert_detour(MonoImage *image, guint32 token,
                                     gpointer code);
extern void hot_reload_remove_detour(MonoImage *image, guint32 token);

int magicdetour2allowed(gpointer ftnptr) {
  InterpMethod *mono = ftnptr_to_imethod_local(ftnptr);
  if (!mono || !mono->method)
    return 0;
  return !mono->method->is_inflated &&
         mono->method->wrapper_type == MONO_WRAPPER_NONE &&
         !mono->method->sre_method;
}

void magicdetour2(gpointer ftnptr, gpointer code) {
  InterpMethod *mono = ftnptr_to_imethod_local(ftnptr);
  if (!mono || !mono->method || !mono->method->klass)
    return;
  mono_class_get_image(mono->method->klass)->has_updates = TRUE;
  hot_reload_insert_detour(mono_class_get_image(mono->method->klass),
                           mono_metadata_token_index(mono->method->token),
                           code);
}

void magicundetour2(gpointer ftnptr) {
  InterpMethod *mono = ftnptr_to_imethod_local(ftnptr);
  if (!mono || !mono->method || !mono->method->klass)
    return;
  hot_reload_remove_detour(mono_class_get_image(mono->method->klass),
                           mono_metadata_token_index(mono->method->token));
}
