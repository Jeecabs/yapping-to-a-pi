const MINIMUM_MACOS_MAJOR = 26;
const MINIMUM_SWIFT_VERSION = { major: 6, minor: 2 } as const;

export function nativeHostProblem(platform: NodeJS.Platform, macOSVersion?: string): string | undefined {
  if (platform !== "darwin") {
    return `Dictation unavailable: macOS ${MINIMUM_MACOS_MAJOR} or newer is required; this host is ${platform}.`;
  }

  const major = macOSMajorVersion(macOSVersion);
  if (major === undefined) return undefined;
  if (major < MINIMUM_MACOS_MAJOR) {
    return `Dictation unavailable: macOS ${MINIMUM_MACOS_MAJOR} or newer is required; this Mac runs macOS ${macOSVersion}. Upgrade macOS and Xcode, then reinstall yapping to a pi.`;
  }
  return undefined;
}

export function swiftToolchainProblem(swiftVersionOutput: string): string | undefined {
  const match = swiftVersionOutput.match(/Apple Swift version\s+(\d+)\.(\d+)/i);
  if (!match) return undefined;

  const installed = { major: Number(match[1]), minor: Number(match[2]) };
  const minimum = MINIMUM_SWIFT_VERSION;
  if (isVersionAtLeast(installed, minimum)) return undefined;

  return `Native helper build requires Apple Swift ${minimum.major}.${minimum.minor} or newer; found ${installed.major}.${installed.minor}. Upgrade Xcode, then reinstall yapping to a pi.`;
}

function macOSMajorVersion(version: string | undefined): number | undefined {
  return versionComponents(version)?.[0];
}

function isVersionAtLeast(
  installed: { major: number; minor: number },
  minimum: { major: number; minor: number },
): boolean {
  if (installed.major !== minimum.major) return installed.major > minimum.major;
  return installed.minor >= minimum.minor;
}

function versionComponents(version: string | undefined): number[] | undefined {
  if (!version) return undefined;
  const components = version.split(".").map(Number);
  return components.length > 0 && components.every(Number.isFinite) ? components : undefined;
}
