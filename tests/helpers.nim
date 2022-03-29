import std/random

import pkg/stew/results
import ../leopard

proc randomCRCPacket*(data: var openArray[byte]) =
  if data.len < 16:
    data[0] = rand(data.len).byte
    for i in 1..<data.len:
      data[i] = data[0]
  else:
    let
      len: uint32 = data.len.uint32

    copyMem(addr data[0], unsafeAddr len, sizeof(len))
    var
      crc = data.len.uint32

    for i in 8..<data.len:
      let v = rand(data.len).byte
      data[i] = v
      crc = (crc shl 3) and (crc shr (32 - 3))
      crc += v

    copyMem(addr data[4], unsafeAddr crc, sizeof(crc))

proc checkCRCPacket*(data: openArray[byte]): bool =
  if data.len < 16:
    for d in data[1..data.high]:
      if d != data[0]:
        raise (ref Defect)(msg: "Packet don't match")
  else:
    var
      crc = data.len.uint32
      packCrc: uint32
      packSize: uint32

    copyMem(addr packSize, unsafeAddr data[0], sizeof(packSize))
    if packSize != data.len.uint:
      raise (ref Defect)(msg: "Packet size don't match!")

    for i in 4..<data.len:
      let v = data[i]
      crc = (crc shl 3) and (crc shr (32 - 3))
      crc += v

    copyMem(addr packCrc, unsafeAddr data[4], sizeof(packCrc))

    if packCrc == crc:
      return true

proc dropRandomIdx*(bufs: var openArray[seq[byte]], dropCount: int) =
  var
    count = 0
    dups: seq[int]
    size = bufs.len

  while count < dropCount:
    let i = rand(0..<size)
    if dups.find(i) == -1:
      dups.add(i)
      bufs[i].setLen(0)
      count.inc

proc testPackets*(
  buffers,
  parity,
  bufSize,
  dataLosses: int,
  parityLosses: int,
  encoder: var LeoEncoder,
  decoder: var LeoDecoder): Result[void, cstring] =

  var
    dataBuf = newSeqOfCap[seq[byte]](buffers)
    parityBuf = newSeqOfCap[seq[byte]](parity)
    recoveredBuf = newSeqOfCap[seq[byte]](buffers)

  for _ in 0..<buffers:
    var
      dataSeq = newSeq[byte](bufSize)

    randomCRCPacket(dataSeq)
    dataBuf.add(dataSeq)

    recoveredBuf.add(newSeq[byte](bufSize))

  for _ in 0..<parity:
    parityBuf.add(newSeq[byte](bufSize))

  encoder.encode(dataBuf, parityBuf).tryGet()

  if dataLosses > 0:
    dropRandomIdx(dataBuf, dataLosses)

  if parityLosses > 0:
    dropRandomIdx(parityBuf, parityLosses)

  decoder.decode(dataBuf, parityBuf, recoveredBuf).tryGet()

  for i, d in dataBuf:
    if d.len <= 0:
      if not checkCRCPacket(recoveredBuf[i]):
        return err(("Check failed for packet " & $i).cstring)

  ok()
