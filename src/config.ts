import type { KeyId } from "@earendil-works/pi-tui";
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
}

interface StoredConfig {
  shortcut?: string;
  locale?: string;
}

const DEFAULT_SHORTCUT = "ctrl+alt+d";
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
const MODIFIERS = new Set(["ctrl", "shift", "alt"]);

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
  const stored = await readStoredConfig(configPath);
  const envShortcut = cleanOptionalString(env.PI_DICTATION_SHORTCUT);
  const storedShortcut = cleanOptionalString(stored.shortcut);
  const shortcut = envShortcut ?? storedShortcut ?? DEFAULT_SHORTCUT;

  if (!isValidShortcut(shortcut)) {
    throw new Error(`Invalid dictation shortcut '${shortcut}'. Example: ctrl+alt+d`);
  }

  const envLocale = cleanOptionalString(env.PI_DICTATION_LOCALE);
  const storedLocale = cleanOptionalString(stored.locale);
  const locale = envLocale ?? storedLocale ?? DEFAULT_LOCALE;
  if (!isValidLocale(locale)) {
    throw new Error(`Invalid dictation locale '${locale}'. Expected a BCP-47 locale such as en-AU.`);
  }

  return {
    shortcut,
    locale,
    helperPath: cleanOptionalString(env.PI_DICTATION_HELPER) ?? options.defaultHelperPath,
    configPath,
    shortcutSource: envShortcut ? "environment" : storedShortcut ? "file" : "default",
    localeSource: envLocale ? "environment" : storedLocale ? "file" : "default",
  };
}

export async function saveDictationConfig(
  patch: StoredConfig,
  options: { home?: string } = {},
): Promise<string> {
  const configPath = defaultConfigPath(options.home);
  const existing = await readStoredConfig(configPath);
  const next: StoredConfig = { ...existing, ...patch };

  if (next.shortcut !== undefined && !isValidShortcut(next.shortcut)) {
    throw new Error(`Invalid dictation shortcut '${next.shortcut}'. Example: ctrl+alt+d`);
  }
  if (next.locale !== undefined && !isValidLocale(next.locale)) {
    throw new Error(`Invalid dictation locale '${next.locale}'. Expected a BCP-47 locale such as en-AU.`);
  }

  await mkdir(dirname(configPath), { recursive: true, mode: 0o700 });
  const temporaryPath = `${configPath}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(next, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  await chmod(temporaryPath, 0o600);
  await rename(temporaryPath, configPath);
  return configPath;
}

export function isValidShortcut(value: string): value is KeyId {
  const normalized = value.trim().toLowerCase();
  if (!normalized || /\s/.test(normalized)) return false;

  const parts = normalized.split("+");
  if (parts.some((part) => part.length === 0)) return false;
  const key = parts.at(-1);
  if (!key || !isKey(key)) return false;

  const modifiers = parts.slice(0, -1);
  return modifiers.length <= 3 && new Set(modifiers).size === modifiers.length && modifiers.every((part) => MODIFIERS.has(part));
}

export function shortcutWarning(shortcut: string): string | undefined {
  const normalized = shortcut.trim().toLowerCase();
  const collisions: Record<string, string> = {
    enter: "submits the editor",
    escape: "interrupts Pi",
    esc: "interrupts Pi",
    "ctrl+c": "clears/copies in Pi",
    "ctrl+d": "exits Pi when the editor is empty",
    "ctrl+t": "toggles thinking",
    "alt+d": "deletes the next word",
  };
  const meaning = collisions[normalized];
  return meaning ? `${shortcut} already ${meaning}. Choose a different shortcut.` : undefined;
}

export function isValidLocale(value: string): boolean {
  return /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})+$/.test(value.trim());
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

function isKey(value: string): boolean {
  if (/^[a-z0-9]$/.test(value)) return true;
  if (/^f(?:[1-9]|1[0-2])$/.test(value)) return true;
  if (NAMED_KEYS.has(value)) return true;
  return /^[-=`[\]\\;',./]$/.test(value);
}

function cleanOptionalString(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function isMissingFile(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ENOENT";
}
