## Nim-Leopard
## Copyright (c) 2022 Status Research & Development GmbH
## Licensed under either of
##  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
##  * MIT license ([LICENSE-MIT](LICENSE-MIT))
## at your option.
## This file may not be copied, modified, or distributed except according to
## those terms.

import pkg/upraises
push: {.upraises: [].}

{.deadCodeElim: on.}

import system/ansi_c

import pkg/stew/ptrops
import ./cpuinfo_x86

## inspired by https://github.com/mratsim/weave/blob/master/weave/memory/allocs.nim

let
  LeoAlignBytes* = if hasAvx2(): 32'u else: 16'u

when defined(windows):
  proc alignedAlloc(alignment, size: csize_t): pointer =
    alignedAllocWindows(size, alignment)

  proc alignedAllocWindows(size, alignment: csize_t): pointer
    {.sideeffect, importc: "_aligned_malloc", header: "<malloc.h>".}
    # Beware of the arg order!

  proc alignedFree*[T](p: ptr T)
    {.sideeffect, importc: "_aligned_free", header: "<malloc.h>".}
elif defined(osx):
  proc posix_memalign(mem: var pointer, alignment, size: csize_t)
    {.sideeffect, importc, header:"<stdlib.h>".}

  proc alignedAlloc(alignment, size: csize_t): pointer {.inline.} =
    posix_memalign(result, alignment, size)

  proc alignedFree*[T](p: ptr T) {.inline.} =
    c_free(p)
elif defined(unix):
  proc alignedAlloc(alignment, size: csize_t): pointer
    {.sideeffect, importc: "aligned_alloc", header: "<stdlib.h>".}

  proc alignedFree*[T](p: ptr T) {.inline.} =
    {.sideeffect, importc: "free_aligned", header: "<stdlib.h>".}
    c_free(p)
else:
  {.warning: "Falling back to manual pointer alignment, might end-up using more memory!".}
  proc alignedAlloc*(size, align: Positive): pointer {.inline.}  =
    var
      data = c_malloc(align + size)

    if not isNil(data):
      var
        doffset = cast[uint](data) mod align

      data = data.offset((align + doffset).int)
      var
        offsetPtr = cast[pointer](cast[uint](data) - 1'u)
      moveMem(offsetPtr, addr doffset, sizeof(doffset))

      return data

  proc freeAligned*[T](p: ptr T, align: Positive) {.inline.} =
    var data = p
    if not isNil(data):
      let offset = cast[uint](data) - 1'u
      if offset >= align:
          return

      data = cast[pointer](cast[uint](data) - (align - offset))
      c_free(data)

proc leoAlloc*(size: Positive): pointer {.inline.} =
  alignedAlloc(LeoAlignBytes, size.csize_t)

proc leoFree*[T](p: ptr T) =
  alignedFree(p)
