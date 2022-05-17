# nim-leopard

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)](https://github.com/status-im/nim-leopard#stability)
[![Tests (GitHub Actions)](https://github.com/status-im/nim-leopard/workflows/Tests/badge.svg?branch=main)](https://github.com/status-im/nim-leopard/actions?query=workflow%3ATests+branch%3Amain)

Nim wrapper for [Leopard-RS](https://github.com/catid/leopard): a fast library for [Reed-Solomon](https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction) erasure correction coding.

## Requirements

* Same as Leopard-RS' requirements, e.g. CMake 3.7 or newer.
* Nim 1.2 or newer.


## Installation

With [Nimble](https://github.com/nim-lang/nimble)
```text
$ nimble install leopard
```
In a project's `.nimble` file
```nim
requires "leopard >= 0.0.1 & < 0.0.2"
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

If the nim-leopard repo is cloned directly, then before running `nimble develop` or `nimble install` in the root of the clone, it's necessary to init the submodule
```text
$ git submodule update --init --recursive
```

#### Build

The submodule is automatically built (in the `nimcache` dir) and statically linked during compilation of any Nim module that has `import leopard` or `import leopard/wrapper`.

If the `nimcache` dir is set to a custom value, it must be an absolute path.

For the build to work on Windows, `nimble` or `nim c` must be run from a Bash shell, e.g. Git Bash or an MSYS2 shell, and all needed tools (e.g. `cmake` and `make`) must be available in and suitable for that environment.

##### OpenMP

Leopard-RS' `CMakeLists.txt` checks for [OpenMP](https://en.wikipedia.org/wiki/OpenMP) support. If it is available then it is enabled in the build of `libleopard.a`.

Build toolchains commonly installed on Linux and Windows come with support for OpenMP.

The clang/++ compiler in Apple's Xcode does not support OpenMP, but the one installed with `brew install llvm` does support it, though it's also necessary to `brew install libomp`.

So, on macOS, when running `nimble test` of nim-leopard or compiling a project that imports nim-leopard:
* If libomp is not installed and Apple's clang is used, no extra flags need to be passed to the Nim compiler. OpenMP support will not be enabled in `libleopard.a`.
* If libomp is installed and Apple's clang is used, this flag should be passed to `nim c`
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
  -d:LeopardCmakeFlags="-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$(brew --prefix)/opt/llvm/bin/clang -DCMAKE_CXX_COMPILER=$(brew --prefix)/opt/llvm/bin/clang++" -d:LeopardExtraCompilerlags="-fopenmp" -d:LeopardExtraLinkerFlags="-fopenmp -L$(brew --prefix)/opt/libomp/lib"
  ```

## Usage

TODO

### OpenMP

When OpenMP is enabled, whether or not parallel processing kicks in depends on the symbol and byte counts. On a local machine with an Intel processor `RS(256,239)` with `symbolBytes == 64` seems to be the lower bound for triggering parallel processing.

## Versioning

nim-leopard generally follows the upstream `master` branch such that changes there will result in a version bump for this package.

## Stability

This package is currently marked as experimental. Until it is marked as stable, it may be subject to breaking changes across any version bump.

## License

### Wrapper License

nim-leopard is licensed and distributed under either of:

* Apache License, Version 2.0: [LICENSE-APACHEv2](LICENSE-APACHEv2) or https://opensource.org/licenses/Apache-2.0
* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

at your option. The contents of this repository may not be copied, modified, or distributed except according to those terms.

### Dependency License

Leopard-RS is [licensed](https://github.com/catid/leopard/blob/master/License.md) under the BSD 3-Clause License. See [their licensing page](https://github.com/catid/leopard/blob/master/License.md) for further information.
