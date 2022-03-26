import pkg/unittest2
import pkg/stew/results
import pkg/stew/byteutils

import ../leopard

suite "Leopard":
  const
    testString = "Hello World!"

  test "Test simple Encode/Decode":
    var
      encoder = Leo.init(64, 16, 10, LeoCoderKind.Encoder).tryGet()
      decoder = Leo.init(64, 16, 10, LeoCoderKind.Decoder).tryGet()
      data = newSeq[seq[byte]](16)
      parity = newSeq[seq[byte]](10)
      recovered = newSeq[seq[byte]](16)

    try:
      for i in 0..<16:
        data[i] = newSeq[byte](64)
        recovered[i] = newSeq[byte](64)
        var
          str = testString & " " & $i

        copyMem(addr data[i][0], addr str[0], str.len)

      for i in 0..<10:
        parity[i] = newSeq[byte](64)

      encoder.encode(data, parity).tryGet()

      var
        data1 = data[0]
        data2 = data[1]

      data[0].setLen(0)
      data[1].setLen(0)

      decoder.decode(data, parity, recovered).tryGet()

      check recovered[0] == data1
      check recovered[1] == data2
    finally:
      encoder.free()
      decoder.free()