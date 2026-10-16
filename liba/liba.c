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

/*
 * MonoMod's WasmDetourFactory (MonoMod.Core/Platforms/WasmDetourFactory.cs) calls these by P/Invoke. They are thin
 * shims over the runtime's body-replacement primitive (dotnet-runtime-jspi, mini/interp/tiering.c mono_body_*): the
 * runtime installs the detour stub, sets NoInlining, retires every compilation of the old body -- interpreter, its
 * tier-up, the wasm JIT's -- and routes new calls to the new one. The P/Invoke surface MonoMod uses is unchanged.
 *
 * What went away: imethod->transformed = 0 (re-transformed an InterpMethod other threads were running, and did
 * nothing for the JIT), the image->has_updates toggling around header reads (other threads briefly saw the original
 * IL), the (image, token) table the replaced hot-reload component served headers from (hit every instantiation of a
 * generic method; wrappers and SRE methods have no token), and the in-place IL overwrite (tore the IL under a
 * concurrent transform). Undo now invalidates too; it used not to.
 */
extern int mono_body_set_il (MonoMethod *target, const guint8 *blob, guint32 len, int flags);
extern int mono_body_clear (MonoMethod *target, int flags);
#define MONO_BODY_HOOK 1

/* The method a function pointer names, without creating anything: a MonoFtnDesc in llvm-only mode, else a (tagged)
 * InterpMethod. */
static MonoMethod *ftnptr_to_method(gpointer ftnptr) {
  if (!ftnptr)
    return NULL;
  if (mono_llvm_only)
    return ((MonoFtnDesc *)ftnptr)->method;
  return INTERP_IMETHOD_UNTAG_UNBOX(ftnptr)->method;
}

/* Kept for the MagicOverwrite strategy's P/Invoke surface; that strategy is never chosen now (magicdetour2allowed
 * accepts every method with a body), so these report "no IL to overwrite". */
const void *magictranslate(gpointer ftnptr) { return NULL; }

uint32_t magictranslatelen(gpointer ftnptr) { return 0; }

/* The install already invalidated (mono_body_set_il / mono_body_clear). */
void magicinvalidate(gpointer ftnptr) {}

int magicdetour2allowed(gpointer ftnptr) {
  MonoMethod *m = ftnptr_to_method(ftnptr);
  return m && !mono_method_has_no_body(m);
}

void magicdetour2(gpointer ftnptr, gpointer code) {
  MonoMethod *m = ftnptr_to_method(ftnptr);
  if (m)
    mono_body_set_il(m, (const guint8 *)code, 0, MONO_BODY_HOOK);
}

void magicundetour2(gpointer ftnptr) {
  MonoMethod *m = ftnptr_to_method(ftnptr);
  if (m)
    mono_body_clear(m, MONO_BODY_HOOK);
}

