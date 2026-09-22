# Third-Party Notices

This file provides attribution for third-party software included in or used by
the Omnix Voice SDK.

**This file MUST accompany every binary distribution** of the Omnix Voice SDK
(including Android AAR, iOS XCFramework, and React Native package artifacts),
together with the verbatim license texts under `LICENSES/`.

No GPL, LGPL, or AGPL code is permitted in shipped Omnix Voice artifacts.

---

## Baresip

| Field | Value |
|-------|-------|
| Component | baresip |
| Repository | https://github.com/baresip/baresip |
| Version | v4.11.0 |
| Commit | `3d30821f099925d24167f8a99e93ba4d1be98599` |
| License | BSD-3-Clause |
| License file | `LICENSES/baresip-LICENSE.txt` |
| Vendored path | `third_party/baresip/` |

### Copyright notice and license (verbatim)

```
Copyright (C) 2020 - 2026, Baresip Foundation (https://github.com/baresip)
Copyright (c) 2010 - 2024, Alfred E. Heggestad
Copyright (c) 2010 - 2021, Richard Aas
Copyright (c) 2010 - 2021, Creytiv.com
All rights reserved.


Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

---

## re

| Field | Value |
|-------|-------|
| Component | re |
| Repository | https://github.com/baresip/re |
| Version | v4.11.0 |
| Commit | `ceefe9ff499aa1bcfb6255aff1737434dd385322` |
| License | BSD-3-Clause |
| License file | `LICENSES/re-LICENSE.txt` |
| Vendored path | `third_party/re/` |

### Copyright notice and license (verbatim)

```
Copyright (C) 2020 - 2026, Baresip Foundation (https://github.com/baresip)
Copyright (c) 2010 - 2024, Alfred E. Heggestad
Copyright (c) 2010 - 2020, Richard Aas
Copyright (c) 2010 - 2020, Creytiv.com
All rights reserved.


Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

---

## OpenSSL (placeholder — SDK-066)

| Field | Value |
|-------|-------|
| Component | OpenSSL |
| Planned version | 3.5.x LTS (exact patch pinned at import) |
| Planned license | Apache-2.0 |
| Status | **Not yet imported.** Attribution and `LICENSES/openssl-LICENSE.txt` will be filled by SDK-066. |

---

## libopus (placeholder — SDK-067, MVP SHOULD)

| Field | Value |
|-------|-------|
| Component | libopus |
| Planned license | BSD-3-Clause (exact text confirmed at import) |
| Status | **Not included unless SDK-067 completes.** Missing Opus does not block MVP. Attribution will be filled only if Opus is vendored. |

---

## React Native (placeholder)

| Field | Value |
|-------|-------|
| Component | React Native |
| Planned license | MIT |
| Status | **Version pinned at human gate H-1 / SDK-046.** Full copyright notice and license text will be recorded when the React Native package track lands. Until then this entry is a placeholder so binary-distribution packaging knows RN attribution is required. |

---

## Endorsement

Per the BSD-3-Clause terms above: neither the name of any copyright holder nor
the names of contributors may be used to endorse or promote Omnix products
derived from this software without specific prior written permission.
