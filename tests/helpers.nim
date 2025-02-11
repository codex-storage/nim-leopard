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

proc checkCRCPacket*(data: ptr UncheckedArray[byte], len: int): bool =
  if len < 16:
    for i in 1..<len:
      if data[i] != data[0]:
        raise (ref Defect)(msg: "Packet don't match")
  else:
    var
      crc = len.uint32
      packCrc: uint32
      packSize: uint32

    copyMem(addr packSize, unsafeAddr data[0], sizeof(packSize))
    if packSize != len.uint:
      raise (ref Defect)(msg: "Packet size don't match!")

    for i in 4..<len:
      let v = data[i]
      crc = (crc shl 3) and (crc shr (32 - 3))
      crc += v

    copyMem(addr packCrc, unsafeAddr data[4], sizeof(packCrc))

    if packCrc == crc:
      return true

proc dropRandomIdx*(bufs: ptr UncheckedArray[ptr UncheckedArray[byte]], bufsLen,dropCount: int) =
  var
    count = 0
    dups: seq[int]
    size = bufsLen

  while count < dropCount:
    let i = rand(0..<size)
    if dups.find(i) == -1:
      dups.add(i)
      bufs[i]=nil
      count.inc

proc createDoubleArray*(
    outerLen, innerLen: int
): ptr UncheckedArray[ptr UncheckedArray[byte]] =
  # Allocate outer array
  result = cast[ptr UncheckedArray[ptr UncheckedArray[byte]]](alloc0(
    sizeof(ptr UncheckedArray[byte]) * outerLen
  ))

  # Allocate each inner array
  for i in 0 ..< outerLen:
    result[i] = cast[ptr UncheckedArray[byte]](alloc0(sizeof(byte) * innerLen))

proc freeDoubleArray*(
    arr: ptr UncheckedArray[ptr UncheckedArray[byte]], outerLen: int
) =
  # Free each inner array
  for i in 0 ..< outerLen:
    if not arr[i].isNil:
      dealloc(arr[i])

  # Free outer array
  if not arr.isNil:
    dealloc(arr)

proc testPackets*(
  buffers,
  parity,
  bufSize,
  dataLosses: int,
  parityLosses: int,
  encoder: var LeoEncoder,
  decoder: var LeoDecoder): Result[void, cstring] =

  var
    dataBuf = createDoubleArray(buffers, bufSize)
    parityBuf = createDoubleArray(parity, bufSize)
    recoveredBuf = createDoubleArray(buffers, bufSize)
  
  defer: 
    freeDoubleArray(dataBuf, buffers)
    freeDoubleArray(parityBuf, parity)
    freeDoubleArray(recoveredBuf, buffers)



  for i in 0..<buffers:
    var
      dataSeq = newSeq[byte](bufSize)

    randomCRCPacket(dataSeq)
    copyMem(dataBuf[i],addr dataSeq[0],bufSize)

  encoder.encode(dataBuf, parityBuf,buffers,parity).tryGet()

  if dataLosses > 0:
    dropRandomIdx(dataBuf,buffers, dataLosses)

  if parityLosses > 0:
    dropRandomIdx(parityBuf,parity,parityLosses)

  decoder.decode(dataBuf, parityBuf, recoveredBuf,buffers,parity,buffers).tryGet()

  for i in 0..<buffers:
    if dataBuf[i].isNil:
      if not checkCRCPacket(recoveredBuf[i],bufSize):
        return err(("Check failed for packet " & $i).cstring)

  ok()
