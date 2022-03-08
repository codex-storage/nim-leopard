import std/random

import pkg/leopard
import pkg/unittest2

randomize()

type
  Data = seq[seq[byte]]

proc genData(outerLen, innerLen: uint): Data =
  newSeq(result, outerLen)
  for i in 0..<outerLen:
    newSeq(result[i], innerLen)
    for j in 0..<innerLen:
      result[i][j] = rand(255).byte

var
  initialized = false

suite "Initialization":
  test "leoEncode and leoDecode should fail if Leopard-RS is not initialized":
    let
      bufferBytes = 64.uint64
      originalCount = 5.cuint
      recoveryCount = 3.cuint
      workCount = leoEncodeWorkCount(originalCount, recoveryCount)

    var
      dummy = 0
      originalData = cast[ptr pointer](addr dummy)
      workData = cast[ptr pointer](addr dummy)

    let
      encodeRes = leoEncode(
        bufferBytes,
        originalCount,
        recoveryCount,
        workCount,
        originalData,
        workData
      )

    check: encodeRes == LeopardCallInitialize

    var
      recoveryData = cast[ptr pointer](addr dummy)

    let
      decodeRes = leoDecode(
        bufferBytes,
        originalCount,
        recoveryCount,
        workCount,
        originalData,
        recoveryData,
        workData
      )

    check: decodeRes == LeopardCallInitialize

  test "initialization should succeed":
    let init = leoInit()

    check: init == 0

    if init == 0: initialized = true

suite "Encode + Decode":
  proc encodeDecode(decodeShouldFail = false) =
    let
      # together originalCount = 239+, recoveryCount = 17+, bufferBytes = 64+
      # seem to consistently trigger parallel processing with OpenMP
      bufferBytesMultiplier = rand(1..8)
      bufferBytes = (64 * bufferBytesMultiplier).uint64
      originalCount = rand(239..320).cuint
      recoveryCount = rand(17..originalCount.int).cuint
      losses =
        if decodeShouldFail:
          recoveryCount.int + 1
        else:
          rand(1..recoveryCount.int)
      recoveryDataHoleCount =
        if (losses - 1) == 0: 0 else: rand(1..(losses - 1))
      dataHoleCount = losses - recoveryDataHoleCount

    check: dataHoleCount + recoveryDataHoleCount == losses

    var
      originalData = genData(originalCount.uint, bufferBytes.uint)
      originalDataAligned = newSeq[pointer](originalCount)
      workCount = leoEncodeWorkCount(originalCount, recoveryCount)
      workData = newSeq[pointer](workCount)

    for i in 0..<originalCount:
      originalDataAligned[i] = allocAligned(bufferBytes.int, LEO_ALIGN_BYTES)
      for j in 0..<bufferBytes.int:
        copyMem(originalDataAligned[i].offset j, addr originalData[i][j], 1)

    for i in 0..<workCount:
      workData[i] = allocAligned(bufferBytes.int, LEO_ALIGN_BYTES)

    let
      encodeRes = leoEncode(
        bufferBytes,
        originalCount,
        recoveryCount,
        workCount,
        addr originalDataAligned[0],
        addr workData[0]
      )

    check: encodeRes == LeopardSuccess

    if encodeRes != LeopardSuccess:
      for i in 0..<originalCount: freeAligned originalDataAligned[i]
      for i in 0..<workCount: freeAligned workData[i]
      return

    var
      recoveryData: Data
      recoveryDataAligned = newSeq[pointer](recoveryCount)

    newSeq(recoveryData, recoveryCount)
    for i in 0..<recoveryCount:
      newSeq(recoveryData[i], bufferBytes)
      for j in 0..<bufferBytes.int:
        copyMem(addr recoveryData[i][j], workData[i].offset j, 1)

    for i in 0..<recoveryCount:
      recoveryDataAligned[i] = allocAligned(bufferBytes.int, LEO_ALIGN_BYTES)
      for j in 0..<bufferBytes.int:
        copyMem(recoveryDataAligned[i].offset j, addr recoveryData[i][j], 1)

    var
      dataHoles: seq[int]
      recoveryDataHoles: seq[int]
      holeyData = originalDataAligned
      holeyRecoveryData = recoveryDataAligned
      recoveredData = originalData

    for _ in 1..dataHoleCount:
      while true:
        let
          i = rand(originalCount.int - 1)

        if dataHoles.find(i) == -1:
          dataHoles.add i
          break

    check: dataHoles.len == dataHoleCount

    for i in dataHoles:
      holeyData[i] = nil
      recoveredData[i] = newSeq[byte](bufferBytes)

    for _ in 1..recoveryDataHoleCount:
      while true:
        let
          i = rand(recoveryCount.int - 1)

        if recoveryDataHoles.find(i) == -1:
          recoveryDataHoles.add i
          break

    check: recoveryDataHoles.len == recoveryDataHoleCount

    for i in recoveryDataHoles:
      holeyRecoveryData[i] = nil

    for i in 0..<workCount: freeAligned workData[i]
    workCount = leoDecodeWorkCount(originalCount, recoveryCount)
    workData = newSeq[pointer](workCount)
    for i in 0..<workCount:
      workData[i] = allocAligned(bufferBytes.int, LEO_ALIGN_BYTES)

    let
      decodeRes = leoDecode(
        bufferBytes,
        originalCount,
        recoveryCount,
        workCount,
        addr holeyData[0],
        addr holeyRecoveryData[0],
        addr workData[0]
      )

    if decodeShouldFail:
      for i in 0..<originalCount: freeAligned originalDataAligned[i]
      for i in 0..<recoveryCount: freeAligned recoveryDataAligned[i]
      for i in 0..<workCount: freeAligned workData[i]

      check: decodeRes == LeopardNeedMoreData
    else:
      check: decodeRes == LeopardSuccess

      if decodeRes != LeopardSuccess:
        for i in 0..<originalCount: freeAligned originalDataAligned[i]
        for i in 0..<recoveryCount: freeAligned recoveryDataAligned[i]
        for i in 0..<workCount: freeAligned workData[i]
        return

      for i in dataHoles:
        for j in 0..<bufferBytes.int:
          copyMem(addr recoveredData[i][j], workData[i].offset j, 1)

      for i in 0..<originalCount: freeAligned originalDataAligned[i]
      for i in 0..<recoveryCount: freeAligned recoveryDataAligned[i]
      for i in 0..<workCount: freeAligned workData[i]

      check: recoveredData == originalData

  test "should fail to recover data when loss count exceeds recovery count":
    check: initialized
    if not initialized: return

    for _ in 1..1000: encodeDecode(decodeShouldFail = true)

  test "should recover data otherwise":
    check: initialized
    if not initialized: return

    for _ in 1..1000: encodeDecode()
