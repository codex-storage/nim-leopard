# nim-leopard

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)](#stability)
[![Tests (GitHub Actions)](https://github.com/status-im/nim-leopard/workflows/Tests/badge.svg?branch=main)](https://github.com/status-im/nim-leopard/actions?query=workflow%3ATests+branch%3Amain)

Nim wrapper for [Leopard-RS](https://github.com/catid/leopard): a fast library for [Reed-Solomon](https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction) erasure correction coding.

## Requirements

* Same as Leopard-RS' requirements, e.g. CMake 3.7 or newer.
* Nim 1.6 or newer.

## Installation

With [Nimble](https://github.com/nim-lang/nimble)
```text
$ nimble install leopard
```
In a project's `.nimble` file
```nim
requires "leopard >= 0.1.0 & < 0.2.0"
```
In a [nimbus-build-system](https://github.com/status-im/nimbus-build-system) project
```text
$ git submodule add https://github.com/status-im/nim-leopard.git vendor/nim-leopard
$ make update
```

### Submodule

#### Init

[status-im/leopard](https://github.com/status-im/leopard), a fork of [catid/leopard](https://github.com/catid/leopard) (Leopard-RS), is a submodule of nim-leopard.

When nim-leopard is installed with `nimble install leopard`, or as a dependency in a Nimble project, or vendored in a nimbus-build-system project, submodule init is handled automatically.

In a standalone `git clone` of nim-leopard, it's necessary to init the submodule before running `nimble develop` or `nimble install` in the root of the clone
```text
$ git submodule update --init --recursive
```

#### Build

The submodule is automatically built (in the `nimcache` dir) and statically linked during compilation of any Nim module that has `import leopard`.

If the `nimcache` dir is set to a custom value, it must be an absolute path.

For the build to work on Windows, `nimble` or `nim c` must be run from a Bash shell, e.g. Git Bash or an MSYS2 shell, and all needed tools (`cmake`, `make`, compiler, etc.) must be available in and suitable for that environment.

##### OpenMP

Leopard-RS' `CMakeLists.txt` checks for [OpenMP](https://en.wikipedia.org/wiki/OpenMP) support. If it is available then it is enabled in the build of `libleopard.a`.

Build toolchains commonly installed on Linux and Windows come with support for OpenMP.

The clang compiler that ships with Apple's Xcode does not support OpenMP, but the one installed with `brew install llvm` does support it, though it's also necessary to `brew install libomp`.

So, on macOS, when running `nimble test` of nim-leopard or compiling a project that imports nim-leopard:
* If libomp is not installed and Xcode clang is used, no extra flags need to be passed to the Nim compiler. OpenMP support will not be enabled in `libleopard.a`.
* If libomp is installed and Xcode clang is used, this flag should be passed to `nim c`
  ```text
  -d:LeopardCmakeFlags="-DCMAKE_BUILD_TYPE=Release -DENABLE_OPENMP=off"
  ```
* If the intent is to use brew-installed clang + libomp, the shell environment should be modified
  ```text
  $ export PATH="$(brew --prefix)/opt/llvm/bin:${PATH}"
  $ export LDFLAGS="-L$(brew --prefix)/opt/libomp/lib -L$(brew --prefix)/opt/llvm/lib -Wl,-rpath,$(brew --prefix)/opt/llvm/lib"
  ```
  and these flags should be passed to `nim c`
  ```text
  -d:LeopardCmakeFlags="-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$(brew --prefix)/opt/llvm/bin/clang -DCMAKE_CXX_COMPILER=$(brew --prefix)/opt/llvm/bin/clang++" -d:LeopardExtraCompilerFlags="-fopenmp" -d:LeopardExtraLinkerFlags="-fopenmp -L$(brew --prefix)/opt/libomp/lib"
  ```

## Usage

``` nim
import pkg/leopard

# Choose some byte and symbol counts
let
  bufSize = 64  # byte count per buffer, must be a multiple of 64
  buffers = 239 # number of data symbols
  parity = 17   # number of parity symbols

# Initialize an encoder and decoder
var
  encoderRes = LeoEncoder.init(bufSize, buffers, parity)
  decoderRes = LeoDecoder.init(bufSize, buffers, parity)

assert encoderRes.isOk
assert decoderRes.isOk

var
  encoder = encoderRes.get
  decoder = decoderRes.get

import std/random
randomize()

# Helper to generate random data
proc genData(outerLen, innerLen: int): seq[seq[byte]] =
  newSeq(result, outerLen)
  for i in 0..<outerLen:
    newSeq(result[i], innerLen)
    for j in 0..<innerLen:
      result[i][j] = rand(255).byte

var
  data = genData(buffers, bufSize) # some random data
  parityData: seq[seq[byte]]       # container for generated parity data

newSeq(parityData, parity)
for i in 0..<parity:
  newSeq(parityData[i], bufSize)

# Encode
assert encoder.encode(data, parityData).isOk

var
  holeyData = data
  holeyParityData = parityData

# Introduce up to a total of parity-count erasures in data and parityData
holeyData[9]   = @[]
holeyData[53]  = @[]
holeyData[208] = @[]
# ...
holeyParityData[1]  = @[]
holeyParityData[14] = @[]
# ...

var
  recoveredData: seq[seq[byte]] # container for recovered data

newSeq(recoveredData, buffers)
for i in 0..<buffers:
  newSeq(recoveredData[i], bufSize)

# Decode
let
  decodeRes = decoder.decode(holeyData, holeyParityData, recoveredData)

if decodeRes.isOk:
  assert holeyData != data

  # recovered data is in indices matching the erasures
  holeyData[9] = recoveredData[9]
  holeyData[53] = recoveredData[53]
  holeyData[208] = recoveredData[208]

  assert holeyData == data

else:
  # there were more than parity-count erasures
  assert $decodeRes.error == "Not enough recovery data received"
```

### OpenMP

When OpenMP is enabled, whether or not parallel processing kicks in depends on the byte and symbol counts:
```nim
LeoEncoder.init(bufSize = 64, buffers = 239, parity = 17, ...)
```
Those values seem to be a lower bound for triggering parallel processing on a local machine with a 64-bit Intel processor.

## Versioning

nim-leopard generally follows the `master` branch of [status-im/leopard](https://github.com/status-im/leopard) such that changes there will result in a version bump for this project.

## Stability

nim-leopard is currently marked as experimental and may be subject to breaking changes across any version bump until it is marked as stable.

## License

### Wrapper License

nim-leopard is licensed and distributed under either of:

* Apache License, Version 2.0: [LICENSE-APACHEv2](LICENSE-APACHEv2) or https://opensource.org/licenses/Apache-2.0
* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

at your option. The contents of this repository may not be copied, modified, or distributed except according to those terms.

### Dependency License

Leopard-RS is [licensed](https://github.com/catid/leopard/blob/master/License.md) under the BSD 3-Clause License. See [their licensing page](https://github.com/catid/leopard/blob/master/License.md) for further information.
