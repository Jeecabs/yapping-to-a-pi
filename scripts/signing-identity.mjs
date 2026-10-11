import { execFileSync } from "node:child_process";

/**
 * macOS ties Accessibility and Microphone grants to the code signature. Ad-hoc signatures change on
 * every build, which silently revokes those grants, so prefer a stable local identity when one exists.
 * YAPPING_TO_A_PI_CODESIGN_IDENTITY overrides; set it to "-" to force ad-hoc signing.
 */
export function signingIdentity() {
  const configured = process.env.YAPPING_TO_A_PI_CODESIGN_IDENTITY?.trim();
  if (configured) return configured;
  try {
    const output = execFileSync("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"], { encoding: "utf8" });
    const names = [...output.matchAll(/^\s*\d+\) [0-9A-F]{40} "(.+)"$/gm)].map((match) => match[1]);
    return names.find((name) => name.startsWith("Developer ID Application:"))
      ?? names.find((name) => name.startsWith("Apple Development:"))
      ?? "-";
  } catch {
    return "-";
  }
}
