// Builds the distributable computer-listen.dmg: Developer ID signed with hardened runtime, notarized, stapled.
//
// One-time setup (see README "Releasing"):
//   1. A "Developer ID Application" certificate in your login keychain (Xcode → Settings → Accounts → Manage Certificates).
//   2. Notary credentials saved as a keychain profile:
//        xcrun notarytool store-credentials computer-listen --apple-id <you@example.com> --team-id <TEAMID>
//
// Env: YAPPING_TO_A_PI_CODESIGN_IDENTITY (default: first Developer ID Application identity),
//      YAPPING_TO_A_PI_NOTARY_PROFILE (default: computer-listen),
//      YAPPING_TO_A_PI_SKIP_NOTARIZE=1 to stop after signing (for checking the pipeline without credentials).
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const native = join(root, "native");
const build = join(native, ".build");
const app = join(build, "computer, listen.app");
const helper = join(app, "Contents", "Resources", "YappingToAPiHelper.app");
const entitlements = join(native, "Release.entitlements");
const dmg = join(build, "computer-listen.dmg");
const profile = process.env.YAPPING_TO_A_PI_NOTARY_PROFILE?.trim() || "computer-listen";
const skipNotarize = process.env.YAPPING_TO_A_PI_SKIP_NOTARIZE === "1";

const run = (command, args, options = {}) => execFileSync(command, args, { stdio: "inherit", ...options });
const read = (command, args) => execFileSync(command, args, { encoding: "utf8" });
const fail = (message) => { console.error(`\nrelease: ${message}\n`); process.exit(1); };

function developerIdentity() {
  const configured = process.env.YAPPING_TO_A_PI_CODESIGN_IDENTITY?.trim();
  const identities = [...read("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
    .matchAll(/^\s*\d+\) [0-9A-F]{40} "(.+)"$/gm)].map((match) => match[1]);
  const identity = configured || identities.find((name) => name.startsWith("Developer ID Application:"))
    || (skipNotarize ? identities[0] : undefined);
  if (skipNotarize && identity) return identity;
  if (!identity?.startsWith("Developer ID Application:")) {
    fail("No \"Developer ID Application\" certificate found. Apple Development certificates can't be notarized for public download.\n" +
      "Create one in Xcode → Settings → Accounts → (your team) → Manage Certificates → + → Developer ID Application.");
  }
  return identity;
}

function checkNotaryProfile() {
  try { read("/usr/bin/xcrun", ["notarytool", "history", "--keychain-profile", profile]); }
  catch {
    fail(`No notary credentials saved as "${profile}". Run once:\n` +
      `  xcrun notarytool store-credentials ${profile} --apple-id <you@example.com> --team-id <TEAMID>\n` +
      "and paste an app-specific password from account.apple.com when asked.");
  }
}

function sign(path, identity) {
  run("/usr/bin/codesign", ["--force", "--options", "runtime", "--timestamp", "--entitlements", entitlements, "--sign", identity, path]);
}

function notarize(path) {
  run("/usr/bin/xcrun", ["notarytool", "submit", path, "--keychain-profile", profile, "--wait"]);
}

const identity = developerIdentity();
if (!skipNotarize) checkNotaryProfile();

// Build with the release identity so every nested binary starts from the same signer.
process.env.YAPPING_TO_A_PI_CODESIGN_IDENTITY = identity;
run(process.execPath, [join(root, "scripts", "build-app.mjs")]);

// Re-sign inside out with hardened runtime and a secure timestamp; --deep would hide nested problems.
sign(helper, identity);
sign(app, identity);
run("/usr/bin/codesign", ["--verify", "--strict", "--deep", "--verbose=2", app]);

if (!skipNotarize) {
  const zip = join(build, "computer-listen-notarize.zip");
  rmSync(zip, { force: true });
  run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, zip]);
  notarize(zip);
  rmSync(zip, { force: true });
  run("/usr/bin/xcrun", ["stapler", "staple", app]);
}

const staging = join(build, "dmg-staging");
rmSync(staging, { recursive: true, force: true });
mkdirSync(staging, { recursive: true });
cpSync(app, join(staging, "computer, listen.app"), { recursive: true, verbatimSymlinks: true });
symlinkSync("/Applications", join(staging, "Applications"));
rmSync(dmg, { force: true });
run("/usr/bin/hdiutil", ["create", "-volname", "computer, listen", "-srcfolder", staging, "-ov", "-format", "UDZO", dmg]);
rmSync(staging, { recursive: true, force: true });
run("/usr/bin/codesign", ["--force", "--timestamp", "--sign", identity, dmg]);

if (!skipNotarize) {
  notarize(dmg);
  run("/usr/bin/xcrun", ["stapler", "staple", dmg]);
  run("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg]);
}

if (!existsSync(dmg)) fail("DMG was not created.");
console.log(`\ncomputer, listen: ${skipNotarize ? "signed (not notarized)" : "notarized and stapled"} ${dmg}`);
