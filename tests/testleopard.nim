import pkg/unittest2
import pkg/stew/results
import pkg/stew/byteutils

import ../leopard

suite "Leopard":
  const
    testString = "Hello World!"

  var
    leoEncoder: LeoEncoder
    leoDecoder: LeoDecoder
    data: seq[seq[byte]]
    parity: seq[seq[byte]]
    recovered: seq[seq[byte]]

  test "Test Encode/Decode":
    leoEncoder = LeoEncoder.init(64, 16, 10).tryGet()
    leoDecoder = LeoDecoder.init(64, 16, 10).tryGet()
    data = newSeq[seq[byte]](16)
    parity = newSeq[seq[byte]](10)
    recovered = newSeq[seq[byte]](16)

    for i in 0..<16:
      data[i] = newSeq[byte](64)
      recovered[i] = newSeq[byte](64)
      var
        str = testString & " " & $i

      copyMem(addr data[i][0], addr str[0], str.len)

    for i in 0..<10:
      parity[i] = newSeq[byte](64)

    leoEncoder.encode(data, parity).tryGet()

    let
      data1 = data[0]
      data2 = data[1]

    data[0].setLen(0)
    data[1].setLen(0)

    leoDecoder.decode(data, parity, recovered).tryGet()

    check recovered[0] == data1
    check recovered[1] == data2
