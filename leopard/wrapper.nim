## Copyright (c) 2017 Christopher A. Taylor.  All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## * Redistributions of source code must retain the above copyright notice,
##   this list of conditions and the following disclaimer.
## * Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
## * Neither the name of Leopard-RS nor the names of its contributors may be
##   used to endorse or promote products derived from this software without
##   specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.


## Leopard-RS
## MDS Reed-Solomon Erasure Correction Codes for Large Data in C
##
## Algorithms are described in LeopardCommon.h
##
##
## Inspired by discussion with:
##
## Sian-Jhen Lin <sjhenglin@gmail.com> : Author of {1} {3}, basis for Leopard
## Bulat Ziganshin <bulat.ziganshin@gmail.com> : Author of FastECC
## Yutaka Sawada <tenfon@outlook.jp> : Author of MultiPar
##
##
## References:
##
## {1} S.-J. Lin, T. Y. Al-Naffouri, Y. S. Han, and W.-H. Chung,
## "Novel Polynomial Basis with Fast Fourier Transform
## and Its Application to Reed-Solomon Erasure Codes"
## IEEE Trans. on Information Theory, pp. 6284-6299, November, 2016.
##
## {2} D. G. Cantor, "On arithmetical algorithms over finite fields",
## Journal of Combinatorial Theory, Series A, vol. 50, no. 2, pp. 285-300, 1989.
##
## {3} Sian-Jheng Lin, Wei-Ho Chung, "An Efficient (n, k) Information
## Dispersal Algorithm for High Code Rate System over Fermat Fields,"
## IEEE Commun. Lett., vol.16, no.12, pp. 2036-2039, Dec. 2012.
##
## {4} Plank, J. S., Greenan, K. M., Miller, E. L., "Screaming fast Galois Field
## arithmetic using Intel SIMD instructions."  In: FAST-2013: 11th Usenix
## Conference on File and Storage Technologies, San Jose, 2013


import upraises
push: {.upraises: [].}


## -----------------------------------------------------------------------------
## Build configuration

import std/compilesettings
import std/os
import std/strutils

const
  LeopardCmakeFlags {.strdefine.} =
    when defined(macosx):
      "-DCMAKE_BUILD_TYPE=Release -DENABLE_OPENMP=off"
    elif defined(windows):
      "-G\"MSYS Makefiles\" -DCMAKE_BUILD_TYPE=Release"
    else:
      "-DCMAKE_BUILD_TYPE=Release"

  LeopardDir {.strdefine.} =
    joinPath(currentSourcePath.parentDir.parentDir, "vendor", "leopard")

  buildDir = joinPath(querySetting(nimcacheDir), "vendor_leopard")

  LeopardHeader {.strdefine.} = "leopard.h"

  LeopardLib {.strdefine.} = joinPath(buildDir, "liblibleopard.a")

  LeopardCompilerFlags {.strdefine.} =
    when defined(macosx):
      "-I" & LeopardDir
    else:
      "-I" & LeopardDir & " -fopenmp"

  LeopardLinkerFlags {.strdefine.} =
    when defined(macosx):
      LeopardLib
    else:
      LeopardLib & " -fopenmp"

  LeopardExtraCompilerFlags {.strdefine.} = ""

  LeopardExtraLinkerFlags {.strdefine.} = ""

static:
  if defined(windows):
    func pathUnix2Win(path: string): string =
      gorge("cygpath -w " & path.strip).strip

    func pathWin2Unix(path: string): string =
      gorge("cygpath " & path.strip).strip

    proc bash(cmd: varargs[string]): string =
      gorge(gorge("which bash").pathUnix2Win & " -c '" & cmd.join(" ") & "'")

    proc bashEx(cmd: varargs[string]): tuple[output: string, exitCode: int] =
      gorgeEx(gorge("which bash").pathUnix2Win & " -c '" & cmd.join(" ") & "'")

    let
      buildDirUnix = buildDir.pathWin2Unix
      leopardDirUnix = LeopardDir.pathWin2Unix
    if defined(LeopardRebuild): discard bash("rm -rf", buildDirUnix)
    if (bashEx("ls", LeopardLib.pathWin2Unix)).exitCode != 0:
      discard bash("mkdir -p", buildDirUnix)
      let cmd =
        @["cd", buildDirUnix, "&& cmake", leopardDirUnix, LeopardCmakeFlags,
          "&& make"]
      echo "\nBuilding Leopard-RS: " & cmd.join(" ")
      let (output, exitCode) = bashEx cmd
      echo output
      if exitCode != 0:
        discard bash("rm -rf", buildDirUnix)
        raise (ref Defect)(msg: "Failed to build Leopard-RS")
  else:
    if defined(LeopardRebuild): discard gorge "rm -rf " & buildDir
    if gorgeEx("ls " & LeopardLib).exitCode != 0:
      discard gorge "mkdir -p " & buildDir
      let cmd =
        "cd " & buildDir & " && cmake " & LeopardDir & " " & LeopardCmakeFlags &
        " && make"
      echo "\nBuilding Leopard-RS: " & cmd
      let (output, exitCode) = gorgeEx cmd
      echo output
      if exitCode != 0:
        discard gorge "rm -rf " & buildDir
        raise (ref Defect)(msg: "Failed to build Leopard-RS")

{.passC: LeopardCompilerFlags & " " & LeopardExtraCompilerFlags.}
{.passL: LeopardLinkerFlags & " " & LeopardExtraLinkerFlags.}

{.pragma: leo, cdecl, header: LeopardHeader.}


## -----------------------------------------------------------------------------
## Library version

var LEO_VERSION* {.header: LeopardHeader, importc.}: int


## -----------------------------------------------------------------------------
## Platform/Architecture

# maybe should detect AVX2 and set to 32 if detected, 16 otherwise:
# https://github.com/catid/leopard/blob/master/LeopardCommon.h#L247-L253
# https://github.com/mratsim/Arraymancer/blob/master/src/arraymancer/laser/cpuinfo_x86.nim#L220
const LEO_ALIGN_BYTES* = 16


## -----------------------------------------------------------------------------
## Initialization API

## leoInit()
##
## Perform static initialization for the library, verifying that the platform
## is supported.
##
## Returns 0 on success and other values on failure.

proc leoInit*(): cint {.leo, importcpp: "leo_init".}


## -----------------------------------------------------------------------------
## Shared Constants / Datatypes

## Results
type
  LeopardResult* = enum
    LeopardCallInitialize = -7.cint ## Call leoInit() first
    LeopardPlatform       = -6.cint ## Platform is unsupported
    LeopardInvalidInput   = -5.cint ## A function parameter was invalid
    LeopardInvalidCounts  = -4.cint ## Invalid counts provided
    LeopardInvalidSize    = -3.cint ## Buffer size must be multiple of 64 bytes
    LeopardTooMuchData    = -2.cint ## Buffer counts are too high
    LeopardNeedMoreData   = -1.cint ## Not enough recovery data received
    LeopardSuccess        =  0.cint ## Operation succeeded

## Convert Leopard result to string
func leoResultString*(res: LeopardResult): cstring
  {.leo, importc: "leo_result_string".}


## -----------------------------------------------------------------------------
## Encoder API

## leoEncodeWorkCount()
##
## Calculate the number of work data buffers to provide to leoEncode().
##
## The sum of originalCount + recoveryCount must not exceed 65536.
##
## Returns the workCount value to pass into leoEncode().
## Returns 0 on invalid input.

func leoEncodeWorkCount*(originalCount, recoveryCount: cuint): cuint
  {.leo, importc: "leo_encode_work_count".}

## leoEncode()
##
## Generate recovery data.
##
## bufferBytes:   Number of bytes in each data buffer.
## originalCount: Number of original data buffers provided.
## recoveryCount: Number of desired recovery data buffers.
## workCount:     Number of work data buffers, from leoEncodeWorkCount().
## originalData:  Array of pointers to original data buffers.
## workData:      Array of pointers to work data buffers.
##
## The sum of originalCount + recoveryCount must not exceed 65536.
## The recoveryCount <= originalCount.
##
## The value of bufferBytes must be a multiple of 64.
## Each buffer should have the same number of bytes.
## Even the last piece must be rounded up to the block size.
##
## Returns LeopardSuccess on success.
## The first set of recoveryCount buffers in workData will be the result.
## Returns other values on errors.

proc leoEncode*(
  bufferBytes: uint64,       ## Number of bytes in each data buffer
  originalCount: cuint,      ## Number of originalData[] buffer pointers
  recoveryCount: cuint,      ## Number of recovery data buffer pointers
                             ## (readable post-call from start of workData[])
  workCount: cuint,          ## Number of workData[] buffer pointers
  originalData: ptr pointer, ## Array of pointers to original data buffers
  workData: ptr pointer,     ## Array of pointers to work data buffers
): LeopardResult {.leo, importc: "leo_encode".}


## -----------------------------------------------------------------------------
## Decoder API

## leoDecodeWorkCount()
##
## Calculate the number of work data buffers to provide to leoDecode().
##
## The sum of originalCount + recoveryCount must not exceed 65536.
##
## Returns the workCount value to pass into leoDecode().
## Returns 0 on invalid input.

func leoDecodeWorkCount*(originalCount, recoveryCount: cuint): cuint
  {.leo, importc: "leo_decode_work_count".}

## leoDecode()
##
## Decode original data from recovery data.
##
## bufferBytes:   Number of bytes in each data buffer.
## originalCount: Number of original data buffers provided.
## recoveryCount: Number of recovery data buffers provided.
## workCount:     Number of work data buffers, from leoDecodeWorkCount().
## originalData:  Array of pointers to original data buffers.
## recoveryData:  Array of pointers to recovery data buffers.
## workData:      Array of pointers to work data buffers.
##
## Lost original/recovery data should be set to NULL.
##
## The sum of recoveryCount + the number of non-NULL original data must be at
## least originalCount in order to perform recovery.
##
## Returns LeopardSuccess on success.
## Returns other values on errors.

proc leoDecode*(
  bufferBytes: uint64,       ## Number of bytes in each data buffer
  originalCount: cuint,      ## Number of originalData[] buffer pointers
  recoveryCount: cuint,      ## Number of recoveryData[] buffer pointers
  workCount: cuint,          ## Number of workData[] buffer pointers
  originalData: ptr pointer, ## Array of pointers to original data buffers
  recoveryData: ptr pointer, ## Array of pointers to recovery data buffers
  workData: ptr pointer,     ## Array of pointers to work data buffers
): LeopardResult {.leo, importc: "leo_decode".}
