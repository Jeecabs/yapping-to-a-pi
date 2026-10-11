import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { nativeHostProblem, swiftToolchainProblem } from "../src/native-requirements.ts";
import { signingIdentity as resolveSigningIdentity } from "./signing-identity.mjs";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const native = join(root, "native");

if (process.platform !== "darwin") {
  console.log("yapping-to-a-pi: skipping native build outside macOS");
  process.exit(0);
}

const macOSVersion = execFileSync("/usr/bin/sw_vers", ["-productVersion"], { encoding: "utf8" }).trim();
const hostProblem = nativeHostProblem(process.platform, macOSVersion);
if (hostProblem) handleRequirement(hostProblem);

let swiftVersion;
try {
  swiftVersion = execFileSync("xcrun", ["swift", "--version"], { encoding: "utf8" });
} catch {
  handleRequirement(
    "Native helper build requires Xcode with Apple Swift 6.2 or newer. Install Xcode, then reinstall yapping to a pi.",
  );
}
const toolchainProblem = swiftToolchainProblem(swiftVersion);
if (toolchainProblem) handleRequirement(toolchainProblem);

execFileSync("xcrun", ["swift", "build", "--package-path", native, "-c", "release", "--product", "yapping-to-a-pi-helper"], {
  cwd: root,
  stdio: "inherit",
});

const sourceBinary = join(native, ".build", "release", "yapping-to-a-pi-helper");
if (!existsSync(sourceBinary)) {
  throw new Error(`Swift build completed without ${sourceBinary}`);
}

const app = join(native, ".build", "YappingToAPiHelper.app");
const stagingApp = `${app}.staging-${process.pid}`;
const backupApp = `${app}.backup-${process.pid}`;
const macos = join(stagingApp, "Contents", "MacOS");
const resources = join(stagingApp, "Contents", "Resources");
const targetBinary = join(macos, "yapping-to-a-pi-helper");
const signingIdentity = resolveSigningIdentity();

rmSync(stagingApp, { recursive: true, force: true });
rmSync(backupApp, { recursive: true, force: true });

try {
  mkdirSync(macos, { recursive: true });
  mkdirSync(resources, { recursive: true });
  cpSync(sourceBinary, targetBinary);
  cpSync(join(native, "Info.plist"), join(stagingApp, "Contents", "Info.plist"));
  chmodSync(targetBinary, 0o755);

  execFileSync("/usr/bin/codesign", ["--force", "--deep", "--sign", signingIdentity, stagingApp], {
    stdio: "ignore",
  });
  execFileSync("/usr/bin/codesign", ["--verify", "--deep", "--strict", stagingApp], {
    stdio: "ignore",
  });

  if (existsSync(app)) renameSync(app, backupApp);
  try {
    renameSync(stagingApp, app);
  } catch (error) {
    if (existsSync(backupApp) && !existsSync(app)) renameSync(backupApp, app);
    throw error;
  }
  rmSync(backupApp, { recursive: true, force: true });
} catch (error) {
  rmSync(stagingApp, { recursive: true, force: true });
  if (existsSync(backupApp) && !existsSync(app)) renameSync(backupApp, app);
  throw error;
}

const identityLabel = signingIdentity === "-" ? "ad-hoc" : signingIdentity;
console.log(`yapping-to-a-pi: built ${app} (${identityLabel})`);

function handleRequirement(message) {
  if (process.env.npm_lifecycle_event === "postinstall") {
    console.warn(`yapping-to-a-pi: native helper not built. ${message}`);
    process.exit(0);
  }
  console.error(`yapping-to-a-pi: ${message}`);
  process.exit(1);
}
