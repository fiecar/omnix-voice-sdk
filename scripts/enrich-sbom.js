#!/usr/bin/env node
/**
 * Enrich syft SPDX-2.3 JSON with vendored components from SOURCE_MANIFEST.json.
 * Scrubs local absolute paths. Ensures Omnix -> baresip -> re relationships.
 */
"use strict";

const fs = require("fs");
const path = require("path");

function argValue(flag) {
  const i = process.argv.indexOf(flag);
  if (i < 0 || i + 1 >= process.argv.length) {
    throw new Error(`Missing ${flag}`);
  }
  return process.argv[i + 1];
}

function fail(msg) {
  console.error(`enrich-sbom: ${msg}`);
  process.exit(1);
}

function scrubString(s) {
  if (typeof s !== "string") return s;
  // Drop absolute Windows / Unix home paths if any leaked
  let out = s;
  out = out.replace(/[A-Za-z]:\\Users\\[^\\/]+\\[^\s"]*/g, ".");
  out = out.replace(/\/Users\/[^/\s"]+/g, "/home/user");
  out = out.replace(/OneDrive[^/\s"\\]*/gi, "OneDrive");
  out = out.replace(/infomedia\.co\.id/gi, "example.com");
  return out;
}

function scrubDeep(value) {
  if (Array.isArray(value)) return value.map(scrubDeep);
  if (value && typeof value === "object") {
    const o = {};
    for (const [k, v] of Object.entries(value)) o[k] = scrubDeep(v);
    return o;
  }
  return scrubString(value);
}

function packageExistsOnDisk(repoRoot, vendoredPath) {
  return fs.existsSync(path.join(repoRoot, vendoredPath));
}

function makePkg({ spdxId, name, version, downloadLocation, license, commit, homepage }) {
  const pkg = {
    SPDXID: spdxId,
    name,
    versionInfo: version.replace(/^v/, ""),
    downloadLocation: downloadLocation || "NOASSERTION",
    filesAnalyzed: false,
    licenseConcluded: license,
    licenseDeclared: license,
    copyrightText: "NOASSERTION",
    supplier: "NOASSERTION",
    externalRefs: [],
  };
  if (homepage) {
    pkg.homepage = homepage;
  }
  if (commit) {
    pkg.externalRefs.push({
      referenceCategory: "PACKAGE-MANAGER",
      referenceType: "purl",
      referenceLocator: `pkg:generic/${name}@${commit}?vcs_url=${encodeURIComponent(homepage || "")}`,
    });
    pkg.comment = `vendored commit ${commit}`;
  }
  return pkg;
}

function main() {
  const inputPath = argValue("--input");
  const outputPath = argValue("--output");
  const manifestPath = argValue("--manifest");
  const repoRoot = argValue("--repo-root");

  const raw = JSON.parse(fs.readFileSync(inputPath, "utf8"));
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  if (!raw.spdxVersion || !String(raw.spdxVersion).startsWith("SPDX-2.")) {
    fail(`Unexpected spdxVersion: ${raw.spdxVersion}`);
  }

  // Drop auto-discovered packages; baseline SBOM is document + Omnix + manifest components only.
  // (syft still provides document creationInfo / tool metadata.)
  const keptDocFields = { ...raw };
  delete keptDocFields.packages;
  delete keptDocFields.files;
  delete keptDocFields.relationships;
  delete keptDocFields.hasExtractedLicensingInfos;

  const omnixId = "SPDXRef-Package-omnix-voice-sdk";
  const packages = [
    makePkg({
      spdxId: omnixId,
      name: "omnix-voice-sdk",
      version: "0.0.0-dev",
      downloadLocation: "git+https://github.com/fiecar/omnix-voice-sdk",
      license: "NOASSERTION",
      homepage: "https://github.com/fiecar/omnix-voice-sdk",
    }),
  ];

  const rels = [
    {
      spdxElementId: "SPDXRef-DOCUMENT",
      relationshipType: "DESCRIBES",
      relatedSpdxElement: omnixId,
    },
  ];

  const byName = {};
  for (const c of manifest.components || []) {
    const name = c.component;
    if (!name || !c.commit || !c.version || !c.license) {
      fail(`Incomplete manifest component: ${JSON.stringify(c)}`);
    }
    if (!packageExistsOnDisk(repoRoot, c.vendoredPath)) {
      fail(`Manifest component missing on disk: ${c.vendoredPath}`);
    }
    // Only include currently vendored components (skip empty future placeholders)
    if (!c.archiveSha256) {
      console.warn(`enrich-sbom: skipping ${name} (no archiveSha256 yet)`);
      continue;
    }
    const spdxId = `SPDXRef-Package-${name}`;
    const version = String(c.version).replace(/^v/, "");
    packages.push(
      makePkg({
        spdxId,
        name,
        version,
        downloadLocation: c.downloadUrl,
        license: c.license,
        commit: c.commit,
        homepage: c.repository,
      })
    );
    byName[name] = spdxId;
  }

  if (!byName.baresip) fail("baresip missing from enriched packages");
  if (!byName.re) fail("re missing from enriched packages");

  // Omnix -> baresip -> re; Omnix -> openssl (when present)
  rels.push({
    spdxElementId: omnixId,
    relationshipType: "DEPENDS_ON",
    relatedSpdxElement: byName.baresip,
  });
  rels.push({
    spdxElementId: byName.baresip,
    relationshipType: "DEPENDS_ON",
    relatedSpdxElement: byName.re,
  });
  if (byName.openssl) {
    rels.push({
      spdxElementId: omnixId,
      relationshipType: "DEPENDS_ON",
      relatedSpdxElement: byName.openssl,
    });
  }
  const runtime = new Set(["baresip", "re", "openssl"]);
  for (const [name, spdxId] of Object.entries(byName)) {
    if (runtime.has(name)) continue;
    rels.push({
      spdxElementId: spdxId,
      relationshipType: "BUILD_TOOL_OF",
      relatedSpdxElement: omnixId,
    });
  }

  // Guard: no false current deps (planned-but-absent only)
  const forbidden = ["libopus", "opus", "react-native", "react_native"];
  for (const p of packages) {
    const n = String(p.name).toLowerCase();
    if (forbidden.some((f) => n === f || n.includes(f))) {
      fail(`Forbidden current component in SBOM: ${p.name}`);
    }
  }

  const doc = scrubDeep({
    ...keptDocFields,
    spdxVersion: raw.spdxVersion || "SPDX-2.3",
    dataLicense: raw.dataLicense || "CC0-1.0",
    SPDXID: raw.SPDXID || "SPDXRef-DOCUMENT",
    name: "omnix-voice-sdk",
    // Stable namespace (syft emits a random UUID per run — not useful in git)
    documentNamespace: "https://github.com/fiecar/omnix-voice-sdk/spdx/omnix-voice-sdk",
    creationInfo: {
      licenseListVersion:
        (raw.creationInfo && raw.creationInfo.licenseListVersion) || undefined,
      creators: [
        "Tool: syft-1.52.0",
        "Tool: omnix-enrich-sbom-1.0.0",
      ],
      // Omit wall-clock created timestamp for more stable git diffs; verify-sbom
      // asserts package identity, not byte-identical timestamps.
      created: "1970-01-01T00:00:00Z",
    },
    packages,
    relationships: rels,
  });

  // Stable-ish key order for packages
  fs.writeFileSync(outputPath, JSON.stringify(doc, null, 2) + "\n", "utf8");

  // Privacy assert on output (allow public github.com/<owner> URLs; block local paths)
  const text = fs.readFileSync(outputPath, "utf8");
  if (
    /C:\\Users\\/i.test(text) ||
    /OneDrive - /i.test(text) ||
    /\/Users\/[^/\s"]+\//i.test(text) ||
    /infomedia\.co\.id/i.test(text)
  ) {
    fail("SBOM still contains local path / internal-domain markers");
  }
  console.log(
    `enrich-sbom: packages=${packages.map((p) => p.name).join(", ")} relationships=${rels.length}`
  );
}

try {
  main();
} catch (e) {
  fail(e.message || String(e));
}
