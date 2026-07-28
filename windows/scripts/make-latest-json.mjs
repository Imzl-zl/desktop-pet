// Builds the Tauri updater manifest (latest.json) from the signed NSIS bundle.
// Run in CI on a `win-v*` tag after `tauri build --config createUpdaterArtifacts`.
// Env: TAG (the git tag, e.g. win-v0.1.0).
import { readFileSync, writeFileSync, readdirSync } from "fs";
import { join } from "path";

const tag = process.env.TAG;
if (!tag) { console.error("TAG env is required"); process.exit(1); }

const conf = JSON.parse(readFileSync("src-tauri/tauri.conf.json", "utf8"));
const version = conf.version;

const nsisDir = "src-tauri/target/release/bundle/nsis";
const files = readdirSync(nsisDir);
const exe = files.find((f) => f.endsWith("-setup.exe"));
const sig = files.find((f) => f.endsWith("-setup.exe.sig"));
if (!exe || !sig) {
  console.error("missing NSIS updater artifacts in", nsisDir, files);
  process.exit(1);
}

const signature = readFileSync(join(nsisDir, sig), "utf8").trim();
const url = `https://github.com/Imzl-zl/desktop-pet/releases/download/${tag}/${encodeURIComponent(exe)}`;

const latest = {
  version,
  notes: "DesktopPet for Windows , see the release notes.",
  pub_date: new Date().toISOString(),
  platforms: { "windows-x86_64": { signature, url } },
};

writeFileSync("latest.json", JSON.stringify(latest, null, 2));
console.log("wrote latest.json", { version, exe });
