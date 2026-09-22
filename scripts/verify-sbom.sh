#!/usr/bin/env bash
# Verify SBOM.json baseline — semantics match verify-sbom.ps1.
set -euo pipefail

fail() { echo "verify-sbom: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBOM="${1:-$ROOT/SBOM.json}"
MANIFEST="$ROOT/third_party/SOURCE_MANIFEST.json"

[[ -f "$SBOM" ]] || fail "Missing SBOM: $SBOM"
[[ -f "$MANIFEST" ]] || fail "Missing manifest"
command -v node >/dev/null || fail "node is required"

node - "$SBOM" "$MANIFEST" <<'PY'
const fs = require("fs");
const sbomPath = process.argv[2];
const manifestPath = process.argv[3];
const text = fs.readFileSync(sbomPath, "utf8");
let sbom;
try { sbom = JSON.parse(text); } catch (e) { console.error("verify-sbom: invalid JSON"); process.exit(1); }
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (!sbom.spdxVersion || !String(sbom.spdxVersion).startsWith("SPDX-2.")) {
  console.error("verify-sbom: bad spdxVersion", sbom.spdxVersion); process.exit(1);
}
const packages = sbom.packages || [];
const find = (n) => packages.find((p) => p.name === n);
const omnix = find("omnix-voice-sdk");
const baresip = find("baresip");
const re = find("re");
if (!omnix || !baresip || !re) { console.error("verify-sbom: missing required package"); process.exit(1); }
const mb = manifest.components.find((c) => c.component === "baresip");
const mr = manifest.components.find((c) => c.component === "re");
const strip = (v) => String(v || "").replace(/^v/, "");
if (strip(baresip.versionInfo) !== "4.11.0" || strip(baresip.versionInfo) !== strip(mb.version)) {
  console.error("verify-sbom: baresip version mismatch"); process.exit(1);
}
if (strip(re.versionInfo) !== "4.11.0" || strip(re.versionInfo) !== strip(mr.version)) {
  console.error("verify-sbom: re version mismatch"); process.exit(1);
}
if (baresip.licenseConcluded !== "BSD-3-Clause" || baresip.licenseDeclared !== "BSD-3-Clause") {
  console.error("verify-sbom: baresip license"); process.exit(1);
}
if (re.licenseConcluded !== "BSD-3-Clause" || re.licenseDeclared !== "BSD-3-Clause") {
  console.error("verify-sbom: re license"); process.exit(1);
}
if (!String(baresip.comment || "").includes(mb.commit)) { console.error("verify-sbom: baresip commit"); process.exit(1); }
if (!String(re.comment || "").includes(mr.commit)) { console.error("verify-sbom: re commit"); process.exit(1); }
const rels = sbom.relationships || [];
const has = (a, t, b) => rels.some((r) => r.spdxElementId === a && r.relationshipType === t && r.relatedSpdxElement === b);
if (!has("SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-Package-omnix-voice-sdk")) process.exit(1);
if (!has("SPDXRef-Package-omnix-voice-sdk", "DEPENDS_ON", "SPDXRef-Package-baresip")) process.exit(1);
if (!has("SPDXRef-Package-baresip", "DEPENDS_ON", "SPDXRef-Package-re")) process.exit(1);
for (const p of packages) {
  const n = String(p.name).toLowerCase();
  for (const bad of ["openssl", "libopus", "opus", "react-native", "react_native"]) {
    if (n === bad || n.includes(bad)) { console.error("verify-sbom: false dep", p.name); process.exit(1); }
  }
}
if (/C:\\Users\\|OneDrive - |\/Users\/[^/\s"]+\/|infomedia\.co\.id|BEGIN (RSA |OPENSSH )?PRIVATE KEY/i.test(text)) {
  console.error("verify-sbom: privacy leak"); process.exit(1);
}
console.log(`verify-sbom: OK (spdx=${sbom.spdxVersion} packages=${packages.length})`);
PY
