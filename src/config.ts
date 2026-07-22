import { getKeybindings, type KeyId } from "@earendil-works/pi-tui";
import { chmod, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export interface DictationConfig {
  shortcut: KeyId;
  locale: string;
  helperPath: string;
  configPath: string;
  shortcutSource: "environment" | "file" | "default";
  localeSource: "environment" | "file" | "default";
  warnings: string[];
}

interface StoredConfig {
  shortcut?: string;
  locale?: string;
}

interface StoredConfigRead {
  stored: StoredConfig;
  warning?: string;
}

const DEFAULT_SHORTCUT: KeyId = "ctrl+alt+d";
const DEFAULT_LOCALE = "en-AU";
const NAMED_KEYS = new Set([
  "escape",
  "esc",
  "enter",
  "return",
  "tab",
  "space",
  "backspace",
  "delete",
  "insert",
  "clear",
  "home",
  "end",
  "pageup",
  "pagedown",
  "up",
  "down",
  "left",
  "right",
]);
const SYMBOL_KEYS = new Set("`-=[]\\;',./!@#$%^&*()_+|~{}:<>?".split(""));
const MODIFIER_ORDER = ["ctrl", "shift", "alt", "super"] as const;
const MODIFIERS: ReadonlySet<string> = new Set(MODIFIER_ORDER);
const STATIC_SHORTCUT_COLLISIONS: Record<string, string> = {
  enter: "submits the editor",
  escape: "interrupts Pi",
  esc: "interrupts Pi",
  "ctrl+c": "clears or copies in Pi",
  "ctrl+d": "exits Pi when the editor is empty",
  "ctrl+z": "suspends Pi",
  "shift+tab": "cycles thinking level",
  "ctrl+p": "cycles models",
  "shift+ctrl+p": "cycles models backward",
  "ctrl+l": "opens the model selector",
  "ctrl+o": "toggles tool output",
  "ctrl+t": "toggles thinking",
  "ctrl+g": "opens the external editor",
  "ctrl+x": "copies a message",
  "alt+enter": "queues a follow-up",
  "ctrl+k": "deletes to the end of the line",
};

export function defaultConfigPath(home = homedir()): string {
  return join(home, ".pi", "agent", "yapping-to-a-pi.json");
}

export async function loadDictationConfig(options: {
  env?: NodeJS.ProcessEnv;
  home?: string;
  defaultHelperPath: string;
}): Promise<DictationConfig> {
  const env = options.env ?? process.env;
  const configPath = defaultConfigPath(options.home);
  const read = await readStoredConfigRecovering(configPath);
  const warnings = read.warning ? [read.warning] : [];

  let shortcut = DEFAULT_SHORTCUT;
  let shortcutSource: DictationConfig["shortcutSource"] = "default";
  const storedShortcut = cleanOptionalString(read.stored.shortcut);
  if (storedShortcut) {
    const warning = shortcutProblem(storedShortcut);
    if (warning) warnings.push(`Ignored saved shortcut '${storedShortcut}': ${warning}`);
    else if (isValidShortcut(storedShortcut)) {
      shortcut = storedShortcut;
      shortcutSource = "file";
    }
  }
  const envShortcut = cleanOptionalString(env.PI_DICTATION_SHORTCUT);
  if (envShortcut) {
    const warning = shortcutProblem(envShortcut);
    if (warning) warnings.push(`Ignored PI_DICTATION_SHORTCUT='${envShortcut}': ${warning}`);
    else if (isValidShortcut(envShortcut)) {
      shortcut = envShortcut;
      shortcutSource = "environment";
    }
  }

  let locale = DEFAULT_LOCALE;
  let localeSource: DictationConfig["localeSource"] = "default";
  const storedLocale = cleanOptionalString(read.stored.locale);
  if (storedLocale) {
    const canonical = canonicalizeLocale(storedLocale);
    if (canonical) {
      locale = canonical;
      localeSource = "file";
    } else {
      warnings.push(`Ignored saved locale '${storedLocale}': expected a valid BCP-47 locale.`);
    }
  }
  const envLocale = cleanOptionalString(env.PI_DICTATION_LOCALE);
  if (envLocale) {
    const canonical = canonicalizeLocale(envLocale);
    if (canonical) {
      locale = canonical;
      localeSource = "environment";
    } else {
      warnings.push(`Ignored PI_DICTATION_LOCALE='${envLocale}': expected a valid BCP-47 locale.`);
    }
  }

  return {
    shortcut,
    locale,
    helperPath: cleanOptionalString(env.PI_DICTATION_HELPER) ?? options.defaultHelperPath,
    configPath,
    shortcutSource,
    localeSource,
    warnings,
  };
}

export async function saveDictationConfig(
  patch: StoredConfig,
  options: { home?: string } = {},
): Promise<string> {
  const configPath = defaultConfigPath(options.home);
  const { stored } = await readStoredConfigRecovering(configPath);
  const next: StoredConfig = {};

  const existingShortcut = cleanOptionalString(stored.shortcut);
  if (existingShortcut && !shortcutProblem(existingShortcut)) next.shortcut = existingShortcut;
  const existingLocale = cleanOptionalString(stored.locale);
  const canonicalExistingLocale = existingLocale ? canonicalizeLocale(existingLocale) : undefined;
  if (canonicalExistingLocale) next.locale = canonicalExistingLocale;

  if (patch.shortcut !== undefined) {
    const warning = shortcutProblem(patch.shortcut);
    if (warning) throw new Error(`Invalid dictation shortcut '${patch.shortcut}': ${warning}`);
    next.shortcut = patch.shortcut.trim();
  }
  if (patch.locale !== undefined) {
    const canonical = canonicalizeLocale(patch.locale);
    if (!canonical) {
      throw new Error(`Invalid dictation locale '${patch.locale}'. Expected a BCP-47 locale such as en-AU.`);
    }
    next.locale = canonical;
  }

  await mkdir(dirname(configPath), { recursive: true, mode: 0o700 });
  const temporaryPath = `${configPath}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(next, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  await chmod(temporaryPath, 0o600);
  await rename(temporaryPath, configPath);
  return configPath;
}

export function isValidShortcut(value: string): value is KeyId {
  return parseShortcut(value) !== undefined;
}

export function shortcutVariants(shortcut: string): KeyId[] {
  const parsed = parseShortcut(shortcut);
  if (!parsed) return [];

  const canonical = formatShortcut(parsed);
  const variant = caseVariant(parsed);
  return variant ? [canonical, variant] : [canonical];
}

export function shortcutWarning(shortcut: string): string | undefined {
  const parsed = parseShortcut(shortcut);
  if (!parsed) return undefined;
  const variants = shortcutVariants(shortcut);
  const staticCollision = findStaticShortcutCollision(variants);
  if (staticCollision) return staticCollision;

  if (parsed.modifiers.length === 0 && isPrintableKey(parsed.key)) {
    return `${shortcut} would trigger while typing. Choose a modified or function key.`;
  }

  return findResolvedShortcutCollision(variants);
}

export function isValidLocale(value: string): boolean {
  return canonicalizeLocale(value) !== undefined;
}

export function canonicalizeLocale(value: string): string | undefined {
  const candidate = value.trim();
  if (!candidate) return undefined;
  try {
    return Intl.getCanonicalLocales(candidate)[0];
  } catch {
    return undefined;
  }
}

async function readStoredConfigRecovering(configPath: string): Promise<StoredConfigRead> {
  try {
    return { stored: await readStoredConfig(configPath) };
  } catch (error) {
    const quarantinePath = `${configPath}.invalid-${Date.now()}`;
    try {
      await rename(configPath, quarantinePath);
      return {
        stored: {},
        warning: `Recovered invalid configuration by moving it to ${quarantinePath}.`,
      };
    } catch {
      return {
        stored: {},
        warning: `Ignored invalid configuration at ${configPath}: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }
}

async function readStoredConfig(configPath: string): Promise<StoredConfig> {
  let raw: string;
  try {
    raw = await readFile(configPath, "utf8");
  } catch (error) {
    if (isMissingFile(error)) return {};
    throw error;
  }

  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error(`Invalid JSON in ${configPath}`);
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Dictation config must be a JSON object: ${configPath}`);
  }

  const record = value as Record<string, unknown>;
  const result: StoredConfig = {};
  if (record.shortcut !== undefined) {
    if (typeof record.shortcut !== "string") throw new Error(`'shortcut' must be a string in ${configPath}`);
    result.shortcut = record.shortcut;
  }
  if (record.locale !== undefined) {
    if (typeof record.locale !== "string") throw new Error(`'locale' must be a string in ${configPath}`);
    result.locale = record.locale;
  }
  return result;
}

function shortcutProblem(value: string): string | undefined {
  if (!isValidShortcut(value)) return "use a Pi key such as ctrl+alt+d, ctrl+?, or f6.";
  return shortcutWarning(value);
}

function parseShortcut(value: string): { modifiers: string[]; key: string } | undefined {
  const normalized = value.trim().toLowerCase();
  if (!normalized || /\s/.test(normalized)) return undefined;

  let modifiers: string[];
  let key: string;
  if (normalized === "+") {
    modifiers = [];
    key = "+";
  } else if (normalized.endsWith("++")) {
    modifiers = normalized.slice(0, -2).split("+");
    key = "+";
  } else {
    const parts = normalized.split("+");
    if (parts.some((part) => part.length === 0)) return undefined;
    key = parts.at(-1) ?? "";
    modifiers = parts.slice(0, -1);
  }

  if (!isKey(key)) return undefined;
  if (modifiers.length > 4 || new Set(modifiers).size !== modifiers.length) return undefined;
  if (!modifiers.every((modifier) => MODIFIERS.has(modifier))) return undefined;
  return { modifiers, key };
}

function caseVariant(parsed: { modifiers: string[]; key: string }): KeyId | undefined {
  if (!/^[a-z]$/.test(parsed.key)) return undefined;
  const modifiers = toggleShift(parsed.modifiers);
  if (modifiers.length === 0) return undefined;
  return formatShortcut({ modifiers, key: parsed.key });
}

function formatShortcut(parsed: { modifiers: string[]; key: string }): KeyId {
  const modifiers = MODIFIER_ORDER.filter((modifier) => parsed.modifiers.includes(modifier));
  return `${modifiers.length > 0 ? `${modifiers.join("+")}+` : ""}${parsed.key}` as KeyId;
}

function toggleShift(modifiers: string[]): string[] {
  if (modifiers.includes("shift")) return modifiers.filter((modifier) => modifier !== "shift");
  return [...modifiers, "shift"];
}

function findStaticShortcutCollision(variants: KeyId[]): string | undefined {
  for (const variant of variants) {
    const meaning = STATIC_SHORTCUT_COLLISIONS[variant.toLowerCase()];
    if (meaning) return `${variant} already ${meaning}. Choose a different shortcut.`;
  }
  return undefined;
}

function findResolvedShortcutCollision(variants: KeyId[]): string | undefined {
  try {
    const resolved = getKeybindings().getResolvedBindings();
    for (const [action, keys] of Object.entries(resolved)) {
      const collision = findEquivalentShortcut(variants, toShortcutArray(keys));
      if (collision) return `${collision} is already assigned to ${action}. Choose a different shortcut.`;
    }
  } catch {
    // Static collision protection remains available outside an initialized Pi TUI.
  }
  return undefined;
}

function toShortcutArray(value: string | string[] | undefined): string[] {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function findEquivalentShortcut(variants: KeyId[], assigned: string[]): KeyId | undefined {
  const assignedIdentities = new Set(assigned.map(shortcutIdentity));
  return variants.find((variant) => assignedIdentities.has(shortcutIdentity(variant)));
}

function shortcutIdentity(value: string): string | undefined {
  const parsed = parseShortcut(value);
  if (!parsed) return undefined;
  const modifiers = MODIFIER_ORDER.filter((modifier) => parsed.modifiers.includes(modifier));
  return [...modifiers, parsed.key].join("+");
}

function isKey(value: string): boolean {
  if (/^[a-z0-9]$/.test(value)) return true;
  if (/^f(?:[1-9]|1[0-2])$/.test(value)) return true;
  return NAMED_KEYS.has(value) || SYMBOL_KEYS.has(value);
}

function isPrintableKey(value: string): boolean {
  return /^[a-z0-9]$/.test(value) || SYMBOL_KEYS.has(value) || value === "space";
}

function cleanOptionalString(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function isMissingFile(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ENOENT";
}
