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

  test "Should not allow encoding with invalid data buffer counts":
    var
      leo = LeoEncoder.init(64, 4, 2).tryGet()
      data = newSeq[seq[byte]](3)
      parity = newSeq[seq[byte]](2)

    check:
      leo.encode(data, parity).error == "Number of data buffers should match!"

  test "Should not allow encoding with invalid parity buffer counts":
    var
      leo = LeoEncoder.init(64, 4, 2).tryGet()
      data = newSeq[seq[byte]](4)
      parity = newSeq[seq[byte]](3)

    check:
      leo.encode(data, parity).error == "Number of parity buffers should match!"

  test "Should not allow decoding with invalid data buffer counts":
    var
      leo = LeoDecoder.init(64, 4, 2).tryGet()
      data = newSeq[seq[byte]](3)
      parity = newSeq[seq[byte]](2)
      recovered = newSeq[seq[byte]](3)

    check:
      leo.decode(data, parity, recovered).error == "Number of data buffers should match!"

  test "Should not allow decoding with invalid data buffer counts":
    var
      leo = LeoDecoder.init(64, 4, 2).tryGet()
      data = newSeq[seq[byte]](4)
      parity = newSeq[seq[byte]](1)
      recovered = newSeq[seq[byte]](3)

    check:
      leo.decode(data, parity, recovered).error == "Number of parity buffers should match!"

  test "Should not allow decoding with invalid data buffer counts":
    var
      leo = LeoDecoder.init(64, 4, 2).tryGet()
      data = newSeq[seq[byte]](4)
      parity = newSeq[seq[byte]](2)
      recovered = newSeq[seq[byte]](3)

    check:
      leo.decode(data, parity, recovered).error == "Number of recovered buffers should match buffers!"

suite "Leopard simple Encode/Decode":
  const
    TestString = "Hello World!"
    DataCount = 4
    ParityCount = 2
    BufferSize = 64

  var
    encoder: LeoEncoder
    decoder: LeoDecoder
    data: seq[seq[byte]]
    parity: seq[seq[byte]]
    recovered: seq[seq[byte]]

  setup:
    encoder = LeoEncoder.init(BufferSize, DataCount, ParityCount).tryGet()
    decoder = LeoDecoder.init(BufferSize, DataCount, ParityCount).tryGet()
    data = newSeq[seq[byte]](DataCount)
    parity = newSeq[seq[byte]](ParityCount)
    recovered = newSeq[seq[byte]](DataCount)

  teardown:
    encoder.free()
    decoder.free()

  test "Test 2 data loses out of 4 possible":
    for i in 0..<DataCount:
      data[i] = newSeq[byte](BufferSize)
      recovered[i] = newSeq[byte](BufferSize)
      var
        str = TestString & " " & $i

      copyMem(addr data[i][0], addr str[0], str.len)

    for i in 0..<ParityCount:
      parity[i] = newSeq[byte](BufferSize)

    encoder.encode(data, parity).tryGet()

    var
      data1 = data[0]
      data2 = data[1]

    data[0].setLen(0)
    data[1].setLen(0)

    decoder.decode(data, parity, recovered).tryGet()

    check recovered[0] == data1
    check recovered[1] == data2

  test "Test 1 data and 1 parity loss out of 4 possible":
    for i in 0..<DataCount:
      data[i] = newSeq[byte](BufferSize)
      recovered[i] = newSeq[byte](BufferSize)

      var
        str = TestString & " " & $i

      copyMem(addr data[i][0], addr str[0], str.len)

    for i in 0..<ParityCount:
      parity[i] = newSeq[byte](BufferSize)

    encoder.encode(data, parity).tryGet()

    var
      data1 = data[0]

    data[0].setLen(0)
    parity[0].setLen(0)

    decoder.decode(data, parity, recovered).tryGet()
    check recovered[0] == data1

suite "Leopard Encode/Decode":
  test "bufSize = 4096, K = 800, M = 200 - drop data = 200 data":
    testPackets(800, 200, 4096, 200, 0).tryGet()

  test "bufSize = 4096, K = 800, M = 200 - drop parity = 200":
    testPackets(800, 200, 4096, 0, 200).tryGet()

  test "bufSize = 4096, K = 800, M = 200 - drop data = 100, drop parity = 100":
    testPackets(800, 200, 4096, 0, 200).tryGet()

  test "bufSize = 4096, K = 8000, M = 2000 - drop data = 2000":
    testPackets(8000, 2000, 4096, 2000, 0).tryGet()

  test "bufSize = 4096, K = 8000, M = 2000 - drop parity = 2000":
    testPackets(8000, 2000, 4096, 0, 2000).tryGet()

  test "bufSize = 4096, K = 8000, M = 2000 - drop data = 1000, parity = 1000":
    testPackets(8000, 2000, 4096, 1000, 1000).tryGet()
