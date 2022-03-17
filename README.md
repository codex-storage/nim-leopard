# nim-leopard

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)](https://github.com/status-im/nim-leopard#stability)
[![Tests (GitHub Actions)](https://github.com/status-im/nim-leopard/workflows/Tests/badge.svg?branch=main)](https://github.com/status-im/nim-leopard/actions?query=workflow%3ATests+branch%3Amain)

Nim wrapper for [Leopard-RS](https://github.com/catid/leopard): a fast library for [Reed-Solomon](https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction) erasure correction coding.

## Usage

```nim
import leopard

# Initialize Leopard-RS
leoInit()

var
  N: Positive
  data: seq[seq[byte]]

# RS(256,239) :: 239 data symbols, 17 parity symbols

assert RS(256,239).code == 239
assert RS(256,239).parity == 17

# Choose some N
N = 1
# For RS(256,239) fill data such that
assert data.len == 239
for i in data: assert i.len == N * 64

# Encode
let
  parityData = RS(256,239).encode data

assert parityData.isOk
assert parityData.get.len == 17

# Poke up to 17 holes total in data and parityData
var
  daWithHoles = data
  paWithHoles = parityData.get

daWithHoles[9]   = @[]
daWithHoles[53]  = @[]
daWithHoles[208] = @[]
# ...
paWithHoles[1] = @[]
paWithHoles[4] = @[]
# ...

# Decode
let
  recoveredData = RS(256,239).decode(daWithHoles, paWithHoles, (N * 64).uint)

if recoveredData.isOk:
  assert recoveredData.get == data
  assert recoveredData.get != daWithHoles
else:
  # More than 17 holes were poked
  assert recoveredData.error.code == LeopardNeedMoreData
```

## Versioning

nim-leopard generally follows the upstream `master` branch such that changes there will result in a version bump for this package.

## Stability

The API provided by this package is currently marked as experimental. Until it is marked as stable, it may be subject to breaking changes across any version bump.

## License

### Wrapper License

nim-leopard is licensed and distributed under either of:

* Apache License, Version 2.0: [LICENSE-APACHEv2](LICENSE-APACHEv2) or https://opensource.org/licenses/Apache-2.0
* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

at your option. The contents of this repository may not be copied, modified, or distributed except according to those terms.

### Dependency License

Leopard-RS is [licensed](https://github.com/catid/leopard/blob/master/License.md) under the BSD 3-Clause License. See [their licensing page](https://github.com/catid/leopard/blob/master/License.md) for further information.
