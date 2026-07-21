import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it } from "node:test";

import {
  isValidLocale,
  isValidShortcut,
  loadDictationConfig,
  saveDictationConfig,
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
    assert.equal(isValidShortcut("ctrl+ctrl+d"), false);
    assert.equal(isValidShortcut("cmd+d"), false);
    assert.equal(isValidShortcut("ctrl++d"), false);
  });

  it("warns about important Pi collisions", () => {
    assert.match(shortcutWarning("ctrl+d") ?? "", /exits Pi/);
    assert.equal(shortcutWarning("ctrl+alt+d"), undefined);
  });

  it("persists user settings and gives environment variables precedence", async () => {
    const home = await makeHome();
    await saveDictationConfig({ shortcut: "f6", locale: "en-US" }, { home });

    const stored = await loadDictationConfig({ env: {}, home, defaultHelperPath: "/helper" });
    assert.equal(stored.shortcut, "f6");
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
  it("accepts BCP-47 locale identifiers", () => {
    assert.equal(isValidLocale("en-AU"), true);
    assert.equal(isValidLocale("zh-Hant-TW"), true);
    assert.equal(isValidLocale("english"), false);
  });
});

async function makeHome(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "yapping-to-a-pi-test-"));
  temporaryHomes.push(path);
  return path;
}
