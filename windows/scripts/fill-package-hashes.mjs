// Fills version + SHA256 into the Scoop and winget manifests from a published
// GitHub release. Run after the `win-v*` release exists:
//
//   node scripts/fill-package-hashes.mjs win-v0.1.0
//
// No dependencies (Node 18+: global fetch + node:crypto).
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const tag = process.argv[2];
if (!tag || !tag.startsWith("win-v")) {
  console.error("usage: node scripts/fill-package-hashes.mjs win-v<version>");
  process.exit(1);
}
const version = tag.slice("win-v".length);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const base = `https://github.com/Imzl-zl/desktop-pet/releases/download/${tag}`;
const portable = `DesktopPet-portable-x64.zip`;
const setup = `DesktopPet_${version}_x64-setup.exe`;

async function sha256(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url}: ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  return createHash("sha256").update(buf).digest("hex");
}

const portableHash = await sha256(`${base}/${portable}`);
const setupHash = await sha256(`${base}/${setup}`);
console.log("portable:", portableHash);
console.log("setup:", setupHash);

// Scoop
const scoopPath = resolve(root, "packaging/scoop/desktoppet.json");
const scoop = JSON.parse(readFileSync(scoopPath, "utf8"));
scoop.version = version;
scoop.architecture["64bit"].url = `${base}/${portable}`;
scoop.architecture["64bit"].hash = portableHash;
writeFileSync(scoopPath, JSON.stringify(scoop, null, 2) + "\n");

// winget (string replace to keep YAML formatting/comments intact)
const sub = (rel, fn) => {
  const p = resolve(root, rel);
  writeFileSync(p, fn(readFileSync(p, "utf8")));
};
const wingetDir = "packaging/winget";
const setVersion = (s) => s.replace(/^PackageVersion: .*/m, `PackageVersion: ${version}`);
sub(`${wingetDir}/Imzl-zl.DesktopPet.yaml`, setVersion);
sub(`${wingetDir}/Imzl-zl.DesktopPet.locale.en-US.yaml`, setVersion);
sub(`${wingetDir}/Imzl-zl.DesktopPet.installer.yaml`, (s) =>
  setVersion(s)
    .replace(/InstallerUrl: .*/, `InstallerUrl: ${base}/${setup}`)
    .replace(/InstallerSha256: .*/, `InstallerSha256: ${setupHash.toUpperCase()}`)
);

console.log("Updated Scoop + winget manifests for", version);
