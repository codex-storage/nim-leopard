# allocAligned, freeAligned, and helpers adapted from mratsim/weave:
# https://github.com/mratsim/weave/blob/master/weave/memory/allocs.nim

func isPowerOfTwo(n: int): bool {.inline.} =
  (n and (n - 1)) == 0

func roundNextMultipleOf(x, n: Natural): int {.inline.} =
  (x + n - 1) and not (n - 1)

when defined(windows):
  proc aligned_alloc_windows(size, alignment: csize_t): pointer
    {.header: "<malloc.h>", importc: "_aligned_malloc", sideeffect.}

  proc aligned_free_windows(p: pointer)
    {.header: "<malloc.h>", importc: "_aligned_free", sideeffect.}

  proc freeAligned*(p: pointer) =
    if not p.isNil:
      aligned_free_windows(p)

elif defined(osx):
  proc posix_memalign(mem: var pointer, alignment, size: csize_t)
    {.header: "<stdlib.h>", importc, sideeffect.}

  proc aligned_alloc(alignment, size: csize_t): pointer {.inline.} =
    posix_memalign(result, alignment, size)

else:
  proc aligned_alloc(alignment, size: csize_t): pointer
    {.header: "<stdlib.h>", importc, sideeffect.}

when not defined(windows):
  proc c_free(p: pointer) {.header: "<stdlib.h>", importc: "free".}

  proc freeAligned*(p: pointer) {.inline.} =
    if not p.isNil:
      c_free(p)

proc allocAligned*(size: int, alignment: static Natural): pointer {.inline.} =
  static:
    assert alignment.isPowerOfTwo()

  let
    requiredMem = size.roundNextMultipleOf(alignment)

  when defined(windows):
    aligned_alloc_windows(csize_t requiredMem, csize_t alignment)
  else:
    aligned_alloc(csize_t alignment, csize_t requiredMem)
