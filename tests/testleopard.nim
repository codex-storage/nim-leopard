import std/random
import std/sets

import pkg/unittest2
import pkg/stew/results

import ../leopard
import ./helpers

randomize()

suite "Leopard Parametrization":
  test "Should not allow invalid buffer multiples":
    check:
      LeoEncoder.init(63, 4, 2).error == "bufSize should be multiples of 64 bytes!"
      LeoEncoder.init(65, 4, 2).error == "bufSize should be multiples of 64 bytes!"

  test "Should not allow invalid data/parity buffer counts":
    check:
      LeoEncoder.init(64, 1, 2).error ==
      "number of parity buffers cannot exceed number of data buffers!"

  test "Should not allow data + parity to exceed 65536":
    check:
      LeoEncoder.init(64, 65536 + 1, 0).error ==
      "number of parity and data buffers cannot exceed 65536!"

      LeoEncoder.init(64, 32768 + 1, 32768).error ==
      "number of parity and data buffers cannot exceed 65536!"

  test "Should not allow encoding with invalid data buffer counts":
    var
      dataLen =3
      parityLen = 2
      leo = LeoEncoder.init(64, 4, 2).tryGet()
      data = createDoubleArray(dataLen, 64)
      parity = createDoubleArray(parityLen, 64)
    defer:
      freeDoubleArray(data, dataLen)
      freeDoubleArray(parity, parityLen)
    check:
      leo.encode(data, parity,dataLen,parityLen).error == "Number of data buffers should match!"

  test "Should not allow encoding with invalid parity buffer counts":
    var
      dataLen =4
      parityLen = 3
      leo = LeoEncoder.init(64, 4, 2).tryGet()
      data = createDoubleArray(dataLen, 64)
      parity = createDoubleArray(parityLen, 64)
    
    defer:
      freeDoubleArray(data, dataLen)
      freeDoubleArray(parity, parityLen)

    check:
      leo.encode(data, parity,dataLen,parityLen).error == "Number of parity buffers should match!"

  test "Should not allow decoding with invalid data buffer counts":
    var
      dataLen =3
      parityLen = 2
      leo = LeoDecoder.init(64, 4, 2).tryGet()
      data = createDoubleArray(dataLen, 64)
      parity = createDoubleArray(parityLen, 64)
      recovered = createDoubleArray(dataLen, 64)
    
    defer:
      freeDoubleArray(data, dataLen)
      freeDoubleArray(parity, parityLen)
      freeDoubleArray(recovered, dataLen)

    check:
      leo.decode(data, parity, recovered,dataLen,parityLen,dataLen).error == "Number of data buffers should match!"

  test "Should not allow decoding with invalid data buffer counts":
    var
      dataLen =4
      parityLen = 1
      recoveredLen = 3
      leo = LeoDecoder.init(64, 4, 2).tryGet()
      data = createDoubleArray(dataLen, 64)
      parity = createDoubleArray(parityLen, 64)
      recovered = createDoubleArray(recoveredLen, 64)

    check:
      leo.decode(data, parity, recovered,dataLen,parityLen,recoveredLen).error == "Number of parity buffers should match!"

  test "Should not allow decoding with invalid data buffer counts":
    var
      dataLen =4
      parityLen = 2
      recoveredLen = 3
      leo = LeoDecoder.init(64, 4, 2).tryGet()
      data = createDoubleArray(dataLen, 64)
      parity = createDoubleArray(parityLen, 64)
      recovered = createDoubleArray(recoveredLen, 64)

    check:
      leo.decode(data, parity, recovered,dataLen,parityLen,recoveredLen).error == "Number of recovered buffers should match buffers!"

suite "Leopard simple Encode/Decode":
  const
    TestString = "Hello World!"
    DataCount = 4
    ParityCount = 2
    BufferSize = 64

  var
    encoder: LeoEncoder
    decoder: LeoDecoder
    data: ptr UncheckedArray[ptr UncheckedArray[byte]]
    parity: ptr UncheckedArray[ptr UncheckedArray[byte]]
    recovered: ptr UncheckedArray[ptr UncheckedArray[byte]]

  setup:
    encoder = LeoEncoder.init(BufferSize, DataCount, ParityCount).tryGet()
    decoder = LeoDecoder.init(BufferSize, DataCount, ParityCount).tryGet()
    data = createDoubleArray(DataCount, BufferSize)
    parity = createDoubleArray(ParityCount, BufferSize)
    recovered = createDoubleArray(DataCount, BufferSize)

  teardown:
    freeDoubleArray(data, DataCount)
    freeDoubleArray(parity, ParityCount)
    freeDoubleArray(recovered, DataCount)
    encoder.free()
    decoder.free()

  test "Test 2 data loses out of 4 possible":
    for i in 0..<DataCount:
      var
        str = TestString & " " & $i

      copyMem(data[i], addr str[0], str.len)


    encoder.encode(data, parity,DataCount,ParityCount).tryGet()

    var
      data1 =cast[ptr UncheckedArray[byte]](allocShared0(sizeof(byte) * BufferSize))
      data2 = cast[ptr UncheckedArray[byte]](allocShared0(sizeof(byte) * BufferSize))

    defer: 
      deallocShared(data1)
      deallocShared(data2)
    
    copyMem(data1,data[0], BufferSize)
    copyMem(data2,data[1], BufferSize)
    
    data[0]=nil
    data[1]=nil

    decoder.decode(data, parity, recovered,DataCount,ParityCount,DataCount).tryGet()

    check equalMem(recovered[0], data1, BufferSize)
    check equalMem(recovered[1], data2, BufferSize)

  test "Test 1 data and 1 parity loss out of 4 possible":
    for i in 0..<DataCount:
      var
        str = TestString & " " & $i

      copyMem(addr data[i][0], addr str[0], str.len)

    encoder.encode(data, parity,DataCount,ParityCount).tryGet()

    
    var data1 = cast[ptr UncheckedArray[byte]](allocShared0(sizeof(byte) * BufferSize))

    defer: deallocShared(data1)

    copyMem(data1,data[0], BufferSize)

    data[0]=nil
    parity[0]=nil

    decoder.decode(data, parity, recovered,DataCount,ParityCount,DataCount).tryGet()

    check equalMem(recovered[0], data1, BufferSize)


suite "Leopard Encode/Decode":
  test "bufSize = 4096, K = 800, M = 200 - drop data = 200 data":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 800
      parity = 200
      bufSize = 4096
      dataLoses = 200

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, 0, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 800, M = 200 - drop parity = 200":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 800
      parity = 200
      bufSize = 4096
      parityLoses = 200

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, parityLoses, 0, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 800, M = 200 - drop data = 100, drop parity = 100":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 800
      parity = 200
      bufSize = 4096
      dataLoses = 100
      parityLoses = 100

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 8000, M = 2000 - drop data = 2000":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 8000
      parity = 2000
      bufSize = 4096
      dataLoses = 2000
      parityLoses = 0

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 8000, M = 2000 - drop parity = 2000":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 8000
      parity = 2000
      bufSize = 4096
      dataLoses = 0
      parityLoses = 2000

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 8000, M = 2000 - drop data = 1000, parity = 1000":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 8000
      parity = 2000
      bufSize = 4096
      dataLoses = 1000
      parityLoses = 1000

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 8000, M = 8000 - drop data = 8000":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 8000
      parity = 8000
      bufSize = 4096
      dataLoses = 8000
      parityLoses = 0

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 8000, M = 8000 - drop parity = 8000":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 8000
      parity = 8000
      bufSize = 4096
      dataLoses = 0
      parityLoses = 8000

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

  test "bufSize = 4096, K = 8000, M = 8000 - drop data = 4000, parity = 4000":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder
      buffers = 8000
      parity = 8000
      bufSize = 4096
      dataLoses = 4000
      parityLoses = 4000

    try:
      encoder = LeoEncoder.init(bufSize, buffers, parity).tryGet()
      decoder = LeoDecoder.init(bufSize, buffers, parity).tryGet()
      testPackets(buffers, parity, bufSize, dataLoses, parityLoses, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()

suite "Leopard use same encoder/decoder multiple times":
    var
      encoder: LeoEncoder
      decoder: LeoDecoder

    try:
      encoder = LeoEncoder.init(4096, 800, 800).tryGet()
      decoder = LeoDecoder.init(4096, 800, 800).tryGet()
      for i in 0..10:
        let lost = 40 * i
        test "Encode/Decode using same encoder/decoder - lost data = " & $lost & " lost parity = " & $lost:
          testPackets(800, 800, 4096, 40 * i, 40 * i, encoder, decoder).tryGet()
    finally:
      encoder.free()
      decoder.free()
