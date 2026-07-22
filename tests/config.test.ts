import assert from "node:assert/strict";
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it } from "node:test";

import {
  isValidLocale,
  isValidShortcut,
  loadDictationConfig,
  saveDictationConfig,
  shortcutVariants,
  shortcutWarning,
} from "../src/config.ts";

const temporaryHomes: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryHomes.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

describe("shortcut configuration", () => {
  it("accepts Pi key formats and rejects malformed combinations", () => {
    assert.equal(isValidShortcut("ctrl+alt+d"), true);
    assert.equal(isValidShortcut("f6"), true);
    assert.equal(isValidShortcut("shift+pageUp"), true);
    assert.equal(isValidShortcut("ctrl+?"), true);
    assert.equal(isValidShortcut("ctrl++"), true);
    assert.equal(isValidShortcut("super+k"), true);
    assert.equal(isValidShortcut("ctrl+ctrl+d"), false);
    assert.equal(isValidShortcut("cmd+d"), false);
    assert.equal(isValidShortcut("ctrl++d"), false);
  });

  it("canonicalizes modified letters to one case-insensitive logical shortcut", () => {
    assert.deepEqual(shortcutVariants("ctrl+alt+d"), ["ctrl+alt+d", "ctrl+shift+alt+d"]);
    assert.deepEqual(shortcutVariants("Ctrl+Alt+D"), ["ctrl+alt+d", "ctrl+shift+alt+d"]);
    assert.deepEqual(shortcutVariants("ctrl+alt+shift+d"), ["ctrl+alt+d", "ctrl+shift+alt+d"]);
    assert.deepEqual(shortcutVariants("shift+d"), ["shift+d"]);
    assert.deepEqual(shortcutVariants("f6"), ["f6"]);
  });

  it("warns about reserved Pi bindings and unmodified text keys", () => {
    assert.match(shortcutWarning("ctrl+d") ?? "", /exits Pi/);
    assert.match(shortcutWarning("ctrl+shift+d") ?? "", /exits Pi/);
    assert.match(shortcutWarning("shift+tab") ?? "", /already/);
    assert.match(shortcutWarning("ctrl+p") ?? "", /already/);
    assert.match(shortcutWarning("d") ?? "", /typing/);
    assert.match(shortcutWarning("shift+d") ?? "", /case-insensitive/);
    assert.equal(shortcutWarning("ctrl+alt+d"), undefined);
  });

  it("persists user settings and gives environment variables precedence", async () => {
    const home = await makeHome();
    await saveDictationConfig({ shortcut: "ctrl+shift+alt+d", locale: "en-US" }, { home });

    const stored = await loadDictationConfig({ env: {}, home, defaultHelperPath: "/helper" });
    assert.equal(stored.shortcut, "ctrl+alt+d");
    assert.equal(stored.locale, "en-US");
    assert.equal(stored.shortcutSource, "file");
    assert.equal(stored.localeSource, "file");

    const overridden = await loadDictationConfig({
      env: { PI_DICTATION_SHORTCUT: "ctrl+alt+x", PI_DICTATION_LOCALE: "en-AU" },
      home,
      defaultHelperPath: "/helper",
    });
    assert.equal(overridden.shortcut, "ctrl+alt+x");
    assert.equal(overridden.locale, "en-AU");
    assert.equal(overridden.shortcutSource, "environment");
    assert.equal(overridden.localeSource, "environment");
  });
});

describe("locale configuration", () => {
  it("accepts structurally valid BCP-47 locale identifiers", () => {
    assert.equal(isValidLocale("en"), true);
    assert.equal(isValidLocale("en-AU"), true);
    assert.equal(isValidLocale("zh-Hant-TW"), true);
    assert.equal(isValidLocale("en-12"), false);
    assert.equal(isValidLocale("en-a1"), false);
    assert.equal(isValidLocale("not_a_locale"), false);
  });

  it("recovers malformed persisted configuration with safe defaults", async () => {
    const home = await makeHome();
    const configPath = join(home, ".pi", "agent", "yapping-to-a-pi.json");
    await saveDictationConfig({}, { home });
    await writeFile(configPath, "{ definitely not json\n");

    const config = await loadDictationConfig({ env: {}, home, defaultHelperPath: "/helper" });

    assert.equal(config.shortcut, "ctrl+alt+d");
    assert.equal(config.locale, "en-AU");
    assert.match(config.warnings.join("\n"), /invalid configuration/i);
    const files = await readdir(join(home, ".pi", "agent"));
    assert.equal(files.some((file) => file.startsWith("yapping-to-a-pi.json.invalid-")), true);
  });

  it("ignores invalid environment overrides instead of disabling the extension", async () => {
    const home = await makeHome();
    const config = await loadDictationConfig({
      env: { PI_DICTATION_SHORTCUT: "ctrl+p", PI_DICTATION_LOCALE: "en-12" },
      home,
      defaultHelperPath: "/helper",
    });

    assert.equal(config.shortcut, "ctrl+alt+d");
    assert.equal(config.locale, "en-AU");
    assert.equal(config.warnings.length, 2);
  });
});

async function makeHome(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "yapping-to-a-pi-test-"));
  temporaryHomes.push(path);
  return path;
}
