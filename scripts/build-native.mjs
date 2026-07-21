import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const native = join(root, "native");

if (process.platform !== "darwin") {
  console.log("yapping-to-a-pi: skipping native build outside macOS");
  process.exit(0);
}

execFileSync("xcrun", ["swift", "build", "--package-path", native, "-c", "release"], {
  cwd: root,
  stdio: "inherit",
});

const sourceBinary = join(native, ".build", "release", "yapping-to-a-pi-helper");
if (!existsSync(sourceBinary)) {
  throw new Error(`Swift build completed without ${sourceBinary}`);
}

const app = join(native, ".build", "YappingToAPiHelper.app");
const macos = join(app, "Contents", "MacOS");
const resources = join(app, "Contents", "Resources");
const targetBinary = join(macos, "yapping-to-a-pi-helper");

rmSync(app, { recursive: true, force: true });
mkdirSync(macos, { recursive: true });
mkdirSync(resources, { recursive: true });
cpSync(sourceBinary, targetBinary);
cpSync(join(native, "Info.plist"), join(app, "Contents", "Info.plist"));
chmodSync(targetBinary, 0o755);

execFileSync("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app], {
  stdio: "ignore",
});

console.log(`yapping-to-a-pi: built ${app}`);
