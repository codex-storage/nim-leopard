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

import pkg/stew/results
import pkg/stew/byteutils

import ./wrapper
import ./utils

export wrapper, results

const
  BuffMultiples* = 64

type
  LeoBufferPtr = ptr UncheckedArray[byte]
  Leo = object of RootObj
    bufSize*: int                       # size of the buffer in multiples of 64
    buffers*: int                       # total number of data buffers (K)
    parity*: int                        # total number of parity buffers (M)
    dataBufferPtr: seq[LeoBufferPtr]    # buffer where data is copied before encoding
    parityWorkCount: int                # number of parity work buffers
    parityBufferPtr: seq[LeoBufferPtr]  # buffer where parity is copied before encoding

  LeoEncoder* = object of Leo
  LeoDecoder* = object of Leo
    decodeWorkCount: int                # number of decoding work buffers
    decodeBufferPtr: seq[LeoBufferPtr]  # work buffer used for decoding

proc encode*(
  self: var LeoEncoder,
  data,
  parity: var openArray[seq[byte]]): Result[void, cstring] =

  # zero encode work buffer to avoid corrupting with previous run
  for i in 0..<self.parityWorkCount:
    zeroMem(self.parityBufferPtr[i], self.bufSize)

  # copy data into aligned buffer
  for i in 0..<data.len:
    copyMem(self.dataBufferPtr[i], addr data[i][0], self.bufSize)

  let
    res = leoEncode(
      self.bufSize.cuint,
      self.buffers.cuint,
      self.parity.cuint,
      self.parityWorkCount.cuint,
      cast[ptr pointer](addr self.dataBufferPtr[0]),
      cast[ptr pointer](addr self.parityBufferPtr[0]))

  if ord(res) != ord(LeopardSuccess):
    return err(leoResultString(res.LeopardResult))

  for i in 0..<parity.len:
    copyMem(addr parity[i][0], self.parityBufferPtr[i], self.bufSize)

  return ok()

proc decode*(
  self: var LeoDecoder,
  data,
  parity,
  recovered: var openArray[seq[byte]]): Result[void, cstring] =
  doAssert(data.len == self.buffers, "Number of data buffers should match!")
  doAssert(parity.len == self.parity, "Number of parity buffers should match!")
  doAssert(recovered.len == self.buffers, "Number of recovered buffers should match buffers!")

  # zero both work buffers before decoding
  for i in 0..<self.parityWorkCount:
    zeroMem(self.parityBufferPtr[i], self.bufSize)

  for i in 0..<self.decodeWorkCount:
    zeroMem(self.decodeBufferPtr[i], self.bufSize)

  var
    dataPtr = newSeq[LeoBufferPtr](data.len)
    parityPtr = newSeq[LeoBufferPtr](self.parityWorkCount)

  # copy data into aligned buffer
  for i in 0..<data.len:
    if data[i].len > 0:
      dataPtr[i] = self.dataBufferPtr[i]
      copyMem(self.dataBufferPtr[i], addr data[i][0], self.bufSize)
    else:
      dataPtr[i] = nil

  # copy parity into aligned buffer
  for i in 0..<self.parityWorkCount:
    if i < parity.len and parity[i].len > 0:
      parityPtr[i] = self.parityBufferPtr[i]
      copyMem(self.parityBufferPtr[i], addr parity[i][0], self.bufSize)
    else:
      parityPtr[i] = nil

  let
    res = leo_decode(
      self.bufSize.cuint,
      self.buffers.cuint,
      self.parity.cuint,
      self.decodeWorkCount.cuint,
      cast[ptr pointer](addr dataPtr[0]),
      cast[ptr pointer](addr self.parityBufferPtr[0]),
      cast[ptr pointer](addr self.decodeBufferPtr[0]))

  if ord(res) != ord(LeopardSuccess):
    return err(leoResultString(res.LeopardResult))

  for i in 0..<self.buffers:
    if data[i].len <= 0:
      echo string.fromBytes(self.decodeBufferPtr[i].toOpenArray(0, self.bufSize - 1))
      copyMem(addr recovered[i][0], self.decodeBufferPtr[i], self.bufSize)

  ok()

proc free*(self: var Leo) = discard
#   for i in 0..<self.encodeWorkCount:
#     leoFree(self.encodeBufferPtr[i])
#     self.encodeBufferPtr[i] = nil

#   for i in 0..<self.decodeWorkCount:
#     leoFree(self.decodeBufferPtr[i])
#     self.decodeBufferPtr[i] = nil

proc setup*(self: var Leo, bufSize, buffers, parity: int): Result[void, cstring] =
  if bufSize mod BuffMultiples != 0:
    return err("bufSize should be multiples of 64 bytes!")

  once:
    # First attempt to init the library
    # This happens only once for all threads...
    if (let res = leoinit(); res.ord != LeopardSuccess.ord):
      return err(leoResultString(res.LeopardResult))

  self.bufSize = bufSize
  self.buffers = buffers
  self.parity = parity

  return ok()

proc init*(T: type LeoEncoder, bufSize, buffers, parity: int): Result[T, cstring] =
  var
    self = LeoEncoder()

  ? Leo(self).setup(bufSize, buffers, parity)

  self.parityWorkCount = leoEncodeWorkCount(
    buffers.cuint,
    parity.cuint).int

  # initialize encode work buffers
  for _ in 0..<self.parityWorkCount:
    self.parityBufferPtr.add(cast[LeoBufferPtr](leoAlloc(self.bufSize)))

  # initialize data buffers
  for _ in 0..<self.buffers:
    self.dataBufferPtr.add(cast[LeoBufferPtr](leoAlloc(self.bufSize)))

  ok(self)

proc init*(T: type LeoDecoder, bufSize, buffers, parity: int): Result[T, cstring] =
  var
    self = LeoDecoder()

  ? Leo(self).setup(bufSize, buffers, parity)

  self.parityWorkCount = leoEncodeWorkCount(
    buffers.cuint,
    parity.cuint).int

  self.decodeWorkCount = leoDecodeWorkCount(
    buffers.cuint,
    parity.cuint).int

  # initialize decode work buffers
  for _ in 0..<self.decodeWorkCount:
    self.decodeBufferPtr.add(cast[LeoBufferPtr](leoAlloc(self.bufSize)))

  # initialize data buffers
  for _ in 0..<self.buffers:
    self.dataBufferPtr.add(cast[LeoBufferPtr](leoAlloc(self.bufSize)))

  # initialize data buffers
  for _ in 0..<self.parityWorkCount:
    self.parityBufferPtr.add(cast[LeoBufferPtr](leoAlloc(self.bufSize)))

  ok(self)
