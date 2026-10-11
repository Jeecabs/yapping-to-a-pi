import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { signingIdentity } from "./signing-identity.mjs";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const native = join(root, "native");
if (process.platform !== "darwin") throw new Error("The desktop app requires macOS 26 or newer.");

execFileSync(process.execPath, [join(root, "scripts/build-native.mjs")], { cwd: root, stdio: "inherit" });
execFileSync("xcrun", ["swift", "build", "--package-path", native, "-c", "release", "--product", "yapping-to-a-pi"], { stdio: "inherit" });

const app = join(native, ".build", "computer, listen.app");
const staging = `${app}.staging-${process.pid}`;
const backup = `${app}.backup-${process.pid}`;
const resources = join(staging, "Contents", "Resources");
const iconset = join(native, ".build", "AppIcon.iconset");
const identity = signingIdentity();

try {
  mkdirSync(join(staging, "Contents", "MacOS"), { recursive: true });
  mkdirSync(resources, { recursive: true });
  mkdirSync(iconset, { recursive: true });
  cpSync(join(native, ".build", "release", "yapping-to-a-pi"), join(staging, "Contents", "MacOS", "yapping-to-a-pi"));
  chmodSync(join(staging, "Contents", "MacOS", "yapping-to-a-pi"), 0o755);
  cpSync(join(native, "App-Info.plist"), join(staging, "Contents", "Info.plist"));
  cpSync(join(native, ".build", "YappingToAPiHelper.app"), join(resources, "YappingToAPiHelper.app"), { recursive: true });
  cpSync(join(root, "assets", "AppIcon.png"), join(resources, "AppIcon.png"));
  for (const size of [16, 32, 128, 256, 512]) {
    for (const scale of [1, 2]) {
      const pixels = String(size * scale);
      const output = join(iconset, `icon_${size}x${size}${scale === 2 ? "@2x" : ""}.png`);
      execFileSync("/usr/bin/sips", ["-z", pixels, pixels, join(root, "assets", "AppIcon.png"), "--out", output], { stdio: "ignore" });
    }
  }
  execFileSync("/usr/bin/iconutil", ["-c", "icns", iconset, "-o", join(resources, "AppIcon.icns")]);
  execFileSync("/usr/bin/plutil", ["-lint", join(staging, "Contents", "Info.plist")], { stdio: "inherit" });
  execFileSync("/usr/bin/codesign", ["--force", "--deep", "--sign", identity, staging], { stdio: "inherit" });
  execFileSync("/usr/bin/codesign", ["--verify", "--deep", "--strict", staging], { stdio: "inherit" });
  if (existsSync(app)) renameSync(app, backup);
  try { renameSync(staging, app); }
  catch (error) { if (existsSync(backup) && !existsSync(app)) renameSync(backup, app); throw error; }
  rmSync(backup, { recursive: true, force: true });
} catch (error) {
  rmSync(staging, { recursive: true, force: true });
  throw error;
}
console.log(`computer, listen: built ${app} (${identity === "-" ? "ad-hoc" : identity})`);
