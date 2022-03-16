import std/random

import pkg/leopard
import pkg/unittest2

randomize()

proc genData(outerLen, innerLen: uint): Data =
  var
    data = newSeqOfCap[seq[byte]](outerLen)

  for i in 0..<outerLen.int:
    data.add newSeqUninitialized[byte](innerLen)
    for j in 0..<innerLen:
      data[i][j] = rand(255).byte

  data

var
  initialized = false

suite "Helpers":
  test "isValid should return false if RS code is nonsensical or is invalid per Leopard-RS":
    var
      rsCode = (codeword: 8.uint, data: 5.uint, parity: 1.uint)

    check: not rsCode.isValid

    rsCode = RS(110,10)

    check: not rsCode.isValid

    rsCode = RS(1,1)

    check: not rsCode.isValid

    rsCode = (codeword: 2.uint, data: 0.uint, parity: 2.uint)

    check: not rsCode.isValid

    rsCode = RS(2,2)

    check: not rsCode.isValid

    rsCode = RS(65537,65409)

    check: not rsCode.isValid

suite "Initialization":
  test "encode and decode should fail if Leopard-RS is not initialized":
    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      parityData = genData(rsCode.parity, symbolBytes)

    var
      data = genData(rsCode.data, symbolBytes)

    let
      encodeRes = rsCode.encode data

    # Related to a subtle race re: decode being called with data that has no
    # holes while Leopard-RS is not initialized, i.e. it would succeed by
    # simply returning the data without a call to leoDecode.
    data[0] = @[]

    let
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check:
      encodeRes.isErr
      encodeRes.error.code == LeopardCallInitialize
      decodeRes.isErr
      decodeRes.error.code == LeopardCallInitialize

  test "initialization should succeed else raise a Defect":
    leoInit()
    initialized = true

    check: initialized

suite "Encoder":
  test "should fail if RS code is nonsensical or is invalid per Leopard-RS":
    check: initialized
    if not initialized: return

    let
      symbolBytes = MinBufferSize

    var
      rsCode = RS(110,10)
      data = genData(rsCode.data, symbolBytes)
      encodeRes = rsCode.encode data

    check: encodeRes.isErr
    if encodeRes.isErr:
      check: encodeRes.error.code == LeopardBadCode

  test "should fail if outer length of data does not match the RS code":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      notEnoughData = genData(rsCode.data - 1, symbolBytes)
      tooMuchData = genData(rsCode.data + 1, symbolBytes)
      notEnoughEncodeRes = rsCode.encode notEnoughData
      tooMuchEncodeRes = rsCode.encode tooMuchData

    check:
        notEnoughEncodeRes.isErr
        tooMuchEncodeRes.isErr
    if notEnoughEncodeRes.isErr:
      check: notEnoughEncodeRes.error.code == LeopardNotEnoughData
    if tooMuchEncodeRes.isErr:
      check: tooMuchEncodeRes.error.code == LeopardTooMuchData

  test "should fail if length of data[0] is less than minimum buffer size":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize - 5
      data = genData(rsCode.data, symbolBytes)
      encodeRes = rsCode.encode data

    check: encodeRes.isErr
    if encodeRes.isErr:
      check: encodeRes.error.code == LeopardInvalidSize

  test "should fail if length of data[0] is not a multiple of minimum buffer size":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize * 2 + 1
      data = genData(rsCode.data, symbolBytes)
      encodeRes = rsCode.encode data

    check: encodeRes.isErr
    if encodeRes.isErr:
      check: encodeRes.error.code == LeopardInvalidSize

  test "should fail if length of data[0+N] does not equal length of data[0]":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize

    var
      data = genData(rsCode.data, symbolBytes)

    data[3] = @[1.byte, 2.byte, 3.byte]

    let
      encodeRes = rsCode.encode data

    check: encodeRes.isErr
    if encodeRes.isErr:
      check: encodeRes.error.code == LeopardInconsistentSize

  # With the current setup in leopard.nim it seems it's not possible to call
  # encode with an RS code that would result in leoEncodeWorkCount being called
  # with invalid parameters, i.e. that would result in it returning 0, because
  # a Result error will always be returned before leoEncodeWorkCount is called.

  # test "should fail if RS code parameters yield invalid parameters for leoEncodWorkCount":
  #   check: initialized
  #   if not initialized: return
  #
  #   let
  #     rsCode = RS(?,?)
  #     symbolBytes = MinBufferSize
  #     data = genData(rsCode.data, symbolBytes)
  #     encodeRes = rsCode.encode data
  #
  #   check: encodeRes.isErr
  #   if encodeRes.isErr:
  #     check: encodeRes.error.code == LeopardInvalidInput

  test "should succeed if RS code and data yield valid parameters for leoEncode":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      data = genData(rsCode.data, symbolBytes)
      encodeRes = rsCode.encode data

    check: encodeRes.isOk

suite "Decoder":
  test "should fail if RS code is nonsensical or is invalid per Leopard-RS":
    check: initialized
    if not initialized: return

    let
      symbolBytes = MinBufferSize

    var
      rsCode = RS(110,10)
      data = genData(rsCode.data, symbolBytes)
      parityData: ParityData
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isErr
    if decodeRes.isErr:
      check: decodeRes.error.code == LeopardBadCode

  test "should fail if outer length of data does not match the RS code":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      notEnoughData = genData(rsCode.data - 1, symbolBytes)
      tooMuchData = genData(rsCode.data + 1, symbolBytes)
      parityData = genData(rsCode.parity, symbolBytes)
      notEnoughDecodeRes = rsCode.decode(notEnoughData, parityData, symbolBytes)
      tooMuchDecodeRes = rsCode.decode(tooMuchData, parityData, symbolBytes)

    check:
        notEnoughDecodeRes.isErr
        tooMuchDecodeRes.isErr
    if notEnoughDecodeRes.isErr:
      check: notEnoughDecodeRes.error.code == LeopardNotEnoughData
    if tooMuchDecodeRes.isErr:
      check: tooMuchDecodeRes.error.code == LeopardTooMuchData

  test "should fail if outer length of parityData does not match the RS code":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      data = genData(rsCode.data, symbolBytes)
      notEnoughParityData = genData(rsCode.parity - 1, symbolBytes)
      tooMuchParityData = genData(rsCode.parity + 1, symbolBytes)
      notEnoughDecodeRes = rsCode.decode(data, notEnoughParityData, symbolBytes)
      tooMuchDecodeRes = rsCode.decode(data, tooMuchParityData, symbolBytes)

    check:
      notEnoughDecodeRes.isErr
      tooMuchDecodeRes.isErr
    if notEnoughDecodeRes.isErr:
      check: notEnoughDecodeRes.error.code == LeopardNeedMoreData
    if tooMuchDecodeRes.isErr:
      check: tooMuchDecodeRes.error.code == LeopardNeedLessData

  test "should fail if symbolBytes is less than minimum buffer size":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize - 5
      data = genData(rsCode.data, symbolBytes)
      parityData = genData(rsCode.parity, symbolBytes)
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isErr
    if decodeRes.isErr:
      check: decodeRes.error.code == LeopardInvalidSize

  test "should fail if symbolBytes is not a multiple of minimum buffer size":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize * 2 + 1
      data = genData(rsCode.data, symbolBytes)
      parityData = genData(rsCode.parity, symbolBytes)
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isErr
    if decodeRes.isErr:
      check: decodeRes.error.code == LeopardInvalidSize

  test "should fail if length of data[0+N] is not zero and does not equal symbolBytes":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      parityData = genData(rsCode.parity, symbolBytes)

    var
      data = genData(rsCode.data, symbolBytes)

    data[3] = @[1.byte, 2.byte, 3.byte]

    let
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isErr
    if decodeRes.isErr:
      check: decodeRes.error.code == LeopardInconsistentSize

  test "should fail if there are data losses and length of parityData[0+N] is not zero and does not equal symbolBytes":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize

    var
      data = genData(rsCode.data, symbolBytes)
      parityData = genData(rsCode.parity, symbolBytes)

    data[3] = @[]
    parityData[1] = @[1.byte, 2.byte, 3.byte]

    let
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isErr
    if decodeRes.isErr:
      check: decodeRes.error.code == LeopardInconsistentSize

  # With the current setup in leopard.nim it seems it's not possible to call
  # decode with an RS code that would result in leoDecodeWorkCount being called
  # with invalid parameters, i.e. that would result in it returning 0, because
  # a Result error will always be returned before leoDecodeWorkCount is called.

  # test "should fail if there are data losses and RS code parameters yield invalid parameters for leoDecodWorkCount":
  #   check: initialized
  #   if not initialized: return
  #
  #   let
  #     rsCode = RS(?,?)
  #     symbolBytes = MinBufferSize
  #     parityData = genData(rsCode.parity, symbolBytes)
  #
  #   var
  #     data = genData(rsCode.data, symbolBytes)
  #
  #   data[0] = @[]
  #
  #   let
  #     decodeRes = rsCode.decode(data, parityData, symbolBytes)
  #
  #   check: decodeRes.isErr
  #   if decodeRes.isErr:
  #     check: decodeRes.error.code == LeopardInvalidInput

  test "should succeed if there are no data losses even when all parity data is lost":
    check: initialized
    if not initialized: return

    let
      rsCode = RS(8,5)
      symbolBytes = MinBufferSize
      data = genData(rsCode.data, symbolBytes)

    var
      parityData = genData(rsCode.parity, symbolBytes)
      decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isOk

    parityData = genData(rsCode.parity, symbolBytes)
    parityData[1] = @[]
    decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isOk

    parityData = genData(rsCode.parity, symbolBytes)
    for i in 0..<parityData.len: parityData[i] = @[]
    decodeRes = rsCode.decode(data, parityData, symbolBytes)

    check: decodeRes.isOk

suite "Encode + Decode":
  test "should fail to recover data when losses exceed tolerance":
    check: initialized
    if not initialized: return

    var i = 0
    while i < 1000:
      let
        # together dataSymbols = 256+, paritySymbols = 17+, symbolBytes = 64+
        # seem to consistently trigger parallel processing with OpenMP
        dataSymbols = rand(256..320)
        paritySymbols = rand(17..dataSymbols)
        codewordSymbols = dataSymbols + paritySymbols
        symbolBytesMultip = rand(1..8)
        symbolBytes = MinBufferSize * symbolBytesMultip.uint
        rsCode = RS(codewordSymbols, dataSymbols)
        data = genData(rsCode.data, symbolBytes)
        losses = paritySymbols + 1
        parityDataHoleCount =
          if (losses - 1) == 0: 0 else: rand(1..(losses - 1))
        dataHoleCount = losses - parityDataHoleCount
        encodeRes = rsCode.encode data

      check: dataHoleCount + parityDataHoleCount == losses

      check: encodeRes.isOk
      if encodeRes.isOk:
        let
          parityData = encodeRes.get

        var
          dataWithHoles = data
          parityDataWithHoles = parityData

        var
          dataHoles: seq[int]

        for i in 1..dataHoleCount:
          while true:
            let
              j = rand(dataSymbols - 1)

            if dataHoles.find(j) == -1:
              dataHoles.add j
              break

        check: dataHoles.len == dataHoleCount

        for i in dataHoles:
          dataWithHoles[i] = @[]

        var
          parityDataHoles: seq[int]

        for i in 1..parityDataHoleCount:
          while true:
            let
              j = rand(paritySymbols - 1)

            if parityDataHoles.find(j) == -1:
              parityDataHoles.add j
              break

        check: parityDataHoles.len == parityDataHoleCount

        for i in parityDataHoles:
          parityDataWithHoles[i] = @[]

        let
          decodeRes = rsCode.decode(dataWithHoles, parityDataWithHoles,
            symbolBytes)

        check: decodeRes.isErr
        if decodeRes.isErr:
          check: decodeRes.error.code == LeopardNeedMoreData

      else:
        echo "encode error message: " & encodeRes.error.msg

      inc i

  test "should recover data otherwise":
    check: initialized
    if not initialized: return

    var i = 0
    while i < 1000:
      let
        # together dataSymbols = 256+, paritySymbols = 17+, symbolBytes = 64+
        # seem to consistently trigger parallel processing with OpenMP
        dataSymbols = rand(256..320)
        paritySymbols = rand(17..dataSymbols)
        codewordSymbols = dataSymbols + paritySymbols
        symbolBytesMultip = rand(1..8)
        symbolBytes = MinBufferSize * symbolBytesMultip.uint
        rsCode = RS(codewordSymbols, dataSymbols)
        data = genData(rsCode.data, symbolBytes)
        losses = rand(1..paritySymbols)
        parityDataHoleCount =
          if (losses - 1) == 0: 0 else: rand(1..(losses - 1))
        dataHoleCount = losses - parityDataHoleCount
        encodeRes = rsCode.encode data

      check: dataHoleCount + parityDataHoleCount == losses

      check: encodeRes.isOk
      if encodeRes.isOk:
        let
          parityData = encodeRes.get

        var
          dataWithHoles = data
          parityDataWithHoles = parityData

        var
          dataHoles: seq[int]

        for i in 1..dataHoleCount:
          while true:
            let
              j = rand(dataSymbols - 1)

            if dataHoles.find(j) == -1:
              dataHoles.add j
              break

        check: dataHoles.len == dataHoleCount

        for i in dataHoles:
          dataWithHoles[i] = @[]

        var
          parityDataHoles: seq[int]

        for i in 1..parityDataHoleCount:
          while true:
            let
              j = rand(paritySymbols - 1)

            if parityDataHoles.find(j) == -1:
              parityDataHoles.add j
              break

        check: parityDataHoles.len == parityDataHoleCount

        for i in parityDataHoles:
          parityDataWithHoles[i] = @[]

        let
          decodeRes = rsCode.decode(dataWithHoles, parityDataWithHoles,
            symbolBytes)

        check: decodeRes.isOk
        if decodeRes.isOk:
          let
            decodedData = decodeRes.get

          check:
            decodedData != dataWithHoles
            decodedData == data

        else:
          echo "decode error message: " & decodeRes.error.msg

      else:
        echo "encode error message: " & encodeRes.error.msg

      inc i
