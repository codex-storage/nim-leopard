import pkg/stew/results
import pkg/upraises

import ./leopard/wrapper

export LEO_ALIGN_BYTES, results

push: {.upraises: [].}

const
  LeopardBadCodeMsg = "Bad RS code"
  LeopardInconsistentSizeMsg =
    "Buffer sizes must all be the same multiple of 64 bytes"
  LeopardNeedLessDataMsg = "Too much recovery data received"
  LeopardNotEnoughDataMsg = "Buffer counts are too low"

  MinBufferSize* = 64.uint
  MinSymbols* = 1.uint
  MaxTotalSymbols* = 65536.uint

type
  Data* = seq[seq[byte]]

  LeopardDefect* = object of Defect

  # It should not be necessary to redefine LeopardResult, but if that's not
  # done here then defining LeopardError as `object of CatchableError` will
  # cause a mystery crash at compile-time (symbol not found). Can workaround by
  # defining as just `object`, but then when trying to work with LeopardResult
  # errors in e.g. tests/test_leopard.nim the same mystery crash happens at
  # compile-time. The problem may be related to use of importcpp in
  # leopard/wrapper.nim, so it could be a compiler bug. By redefining
  # LeopardResult in this module (and casting wrapper.LeopardResult values) the
  # the problem is avoided.
  LeopardResult* = enum
    LeopardNotEnoughData    = -11.cint # Buffer counts are too low
    LeopardNeedLessData     = -10.cint # Too much recovery data received
    LeopardInconsistentSize =  -9.cint # Buffer sizes must all be the same multiple of 64 bytes
    LeopardBadCode          =  -8.cint # Bad RS code
    LeopardCallInitialize   = wrapper.LeopardCallInitialize
    LeopardPlatform         = wrapper.LeopardPlatform
    LeopardInvalidInput     = wrapper.LeopardInvalidInput
    LeopardInvalidCounts    = wrapper.LeopardInvalidCounts
    LeopardInvalidSize      = wrapper.LeopardInvalidSize
    LeopardTooMuchData      = wrapper.LeopardTooMuchData
    LeopardNeedMoreData     = wrapper.LeopardNeedMoreData
    LeopardSuccess          = wrapper.LeopardSuccess

  LeopardError* = object of CatchableError
    code*: LeopardResult

  ParityData* = Data

  ReedSolomonCode* = tuple[codeword, data, parity: uint] # symbol counts

# workaround for https://github.com/nim-lang/Nim/issues/19619
# necessary for use of nim-leopard in nimbus-build-system projects because nbs
# ships libbacktrace by default
proc `$`*(err: LeopardError): string {.nosideeffect.} =
  $err

# https://github.com/catid/leopard/issues/12
# https://www.cs.cmu.edu/~guyb/realworld/reedsolomon/reed_solomon_codes.html
#
# RS(255,239)
# ---------------------------------
# codeword symbols = 255
# data symbols     = 239
# parity symbols   = 255 - 239 = 16

proc RS*(codeword, data: Positive): ReedSolomonCode =
  var
    parity = codeword - data

  if parity < 0: parity = 0
  (codeword: codeword.uint, data: data.uint, parity: parity.uint)

func isValid*(code: ReedSolomonCode): bool =
  not ((code.codeword - code.data != code.parity) or
       (code.parity > code.data) or (code.codeword < MinSymbols + 1) or
       (code.data < MinSymbols) or (code.parity < MinSymbols) or
       (code.codeword > MaxTotalSymbols))

# alloc/freeAligned and helpers adapted from mratsim/weave:
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
  ## aligned_alloc requires allocating in multiple of the alignment.
  static:
    assert alignment.isPowerOfTwo()

  let
    requiredMem = size.roundNextMultipleOf(alignment)

  when defined(windows):
    aligned_alloc_windows(csize_t requiredMem, csize_t alignment)
  else:
    aligned_alloc(csize_t alignment, csize_t requiredMem)

proc leoInit*() =
  if wrapper.leoInit() != 0:
    raise (ref LeopardDefect)(msg: "Leopard-RS failed to initialize")

proc encode*(code: ReedSolomonCode, data: Data):
    Result[ParityData, LeopardError] =
  if not code.isValid:
    return err LeopardError(code: LeopardBadCode, msg: LeopardBadCodeMsg)

  var
    data = data

  let
    symbolBytes = data[0].len

  if data.len < code.data.int:
    return err LeopardError(code: LeopardNotEnoughData,
      msg: LeopardNotEnoughDataMsg)

  elif data.len > code.data.int:
    return err LeopardError(code: LeopardTooMuchData,
      msg: $leoResultString(wrapper.LeopardTooMuchData))

  if symbolBytes < MinBufferSize.int or symbolBytes mod MinBufferSize.int != 0:
    return err LeopardError(code: LeopardInvalidSize,
      msg: $leoResultString(wrapper.LeopardInvalidSize))

  var
    enData = newSeq[pointer](code.data)

  for i in 0..<code.data:
    if data[i].len != symbolBytes:
      for i in 0..<code.data: freeAligned enData[i]
      return err LeopardError(code: LeopardInconsistentSize,
        msg: LeopardInconsistentSizeMsg)

    enData[i] = allocAligned(symbolBytes, LEO_ALIGN_BYTES)
    moveMem(enData[i], addr data[i][0], symbolBytes)

  let
    workCount = leoEncodeWorkCount(code.data.cuint, code.parity.cuint)

  if workCount == 0:
    for i in 0..<code.data: freeAligned enData[i]
    return err LeopardError(code: LeopardInvalidInput,
      msg: $leoResultString(wrapper.LeopardInvalidInput))

  var
    workData = newSeq[pointer](workCount)

  for i in 0..<workCount:
    workData[i] = allocAligned(symbolBytes, LEO_ALIGN_BYTES)

  let
    encodeRes = leoEncode(
      symbolBytes.uint64,
      code.data.cuint,
      code.parity.cuint,
      workCount,
      addr enData[0],
      addr workData[0]
    )

  if encodeRes != wrapper.LeopardSuccess:
    for i in 0..<code.data: freeAligned enData[i]
    for i in 0..<workCount: freeAligned workData[i]
    return err LeopardError(code: cast[LeopardResult](encodeRes),
      msg: $leoResultString(encodeRes))

  var
    parityData: ParityData

  newSeq(parityData, code.parity)
  for i in 0..<code.parity:
    newSeq(parityData[i], symbolBytes)
    moveMem(addr parityData[i][0], workData[i], symbolBytes)

  for i in 0..<code.data: freeAligned enData[i]
  for i in 0..<workCount: freeAligned workData[i]

  ok parityData

proc decode*(code: ReedSolomonCode, data: Data, parityData: ParityData,
    symbolBytes: uint): Result[Data, LeopardError] =
  if not code.isValid:
    return err LeopardError(code: LeopardBadCode, msg: LeopardBadCodeMsg)

  var
    data = data
    parityData = parityData
    holes: seq[int]

  if data.len < code.data.int:
    return err LeopardError(code: LeopardNotEnoughData,
      msg: LeopardNotEnoughDataMsg)

  elif data.len > code.data.int:
    return err LeopardError(code: LeopardTooMuchData,
      msg: $leoResultString(wrapper.LeopardTooMuchData))

  if parityData.len < code.parity.int:
    return err LeopardError(code: LeopardNeedMoreData,
      msg: $leoResultString(wrapper.LeopardNeedMoreData))

  elif parityData.len > code.parity.int:
    return err LeopardError(code: LeopardNeedLessData,
      msg: LeopardNeedLessDataMsg)

  if symbolBytes < MinBufferSize or symbolBytes mod MinBufferSize != 0:
    return err LeopardError(code: LeopardInvalidSize,
      msg: $leoResultString(wrapper.LeopardInvalidSize))

  var
    deData = newSeq[pointer](code.data)

  for i in 0..<code.data:
    if data[i].len != 0:
      if data[i].len != symbolBytes.int:
        for i in 0..<code.data: freeAligned deData[i]
        return err LeopardError(code: LeopardInconsistentSize,
          msg: LeopardInconsistentSizeMsg)

      deData[i] = allocAligned(symbolBytes.int, LEO_ALIGN_BYTES)
      moveMem(deData[i], addr data[i][0], symbolBytes)

    else:
      holes.add i.int

  if holes.len == 0:
    for i in 0..<code.data: freeAligned deData[i]
    return ok data

  var
    paData = newSeq[pointer](code.parity)

  for i in 0..<code.parity:
    if parityData[i].len != 0:
      if parityData[i].len != symbolBytes.int:
        for i in 0..<code.data: freeAligned deData[i]
        for i in 0..<code.parity: freeAligned paData[i]
        return err LeopardError(code: LeopardInconsistentSize,
          msg: LeopardInconsistentSizeMsg)

      paData[i] = allocAligned(symbolBytes.int, LEO_ALIGN_BYTES)
      moveMem(paData[i], addr parityData[i][0], symbolBytes)

  let
    workCount = leoDecodeWorkCount(code.data.cuint, code.parity.cuint)

  if workCount == 0:
    for i in 0..<code.data: freeAligned deData[i]
    for i in 0..<code.parity: freeAligned paData[i]
    return err LeopardError(code: LeopardInvalidInput,
      msg: $leoResultString(wrapper.LeopardInvalidInput))

  var
    workData = newSeq[pointer](workCount)

  for i in 0..<workCount:
    workData[i] = allocAligned(symbolBytes.int, LEO_ALIGN_BYTES)

  let
    decodeRes = leoDecode(
      symbolBytes.uint64,
      code.data.cuint,
      code.parity.cuint,
      workCount,
      addr deData[0],
      addr paData[0],
      addr workData[0]
    )

  if decodeRes != wrapper.LeopardSuccess:
    for i in 0..<code.data: freeAligned deData[i]
    for i in 0..<code.parity: freeAligned paData[i]
    for i in 0..<workCount: freeAligned workData[i]
    return err LeopardError(code: cast[LeopardResult](decodeRes),
      msg: $leoResultString(decodeRes))

  var
    recoveredData: Data

  newSeq(recoveredData, workCount)
  for i in 0..<workCount:
    newSeq(recoveredData[i], symbolBytes)
    moveMem(addr recoveredData[i][0], workData[i], symbolBytes)

  for i in holes:
    data[i] = recoveredData[i]

  for i in 0..<code.data: freeAligned deData[i]
  for i in 0..<code.parity: freeAligned paData[i]
  for i in 0..<workCount: freeAligned workData[i]

  ok data
