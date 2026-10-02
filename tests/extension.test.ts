import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type {
  ExtensionAPI,
  ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";
import { matchesKey, setKittyProtocolActive, type KeyId } from "@earendil-works/pi-tui";

import yappingToAPi, { captureShortcut } from "../src/index.ts";

type CommandHandler = (args: string, ctx: ExtensionCommandContext) => Promise<void>;

interface RegisteredShortcut {
  key: KeyId;
  handler: (ctx: ExtensionCommandContext) => Promise<void>;
}

async function loadExtension() {
  let commandHandler: CommandHandler | undefined;
  const shortcuts: RegisteredShortcut[] = [];

  const pi = {
    on() {},
    registerShortcut(key: KeyId, options: RegisteredShortcut) {
      shortcuts.push({ key, handler: options.handler });
    },
    registerCommand(_name: string, options: { handler: CommandHandler }) {
      commandHandler = options.handler;
    },
  } as unknown as ExtensionAPI;

  await yappingToAPi(pi);
  assert.ok(commandHandler);
  return { commandHandler, shortcuts };
}

describe("dictation shortcut UX", () => {
  it("captures a shortcut keypress instead of asking users to type Pi key syntax", async () => {
    const { commandHandler } = await loadExtension();
    let selectCount = 0;
    let inputCount = 0;
    let customCount = 0;

    const ctx = {
      mode: "tui",
      ui: {
        select: async (_title: string, choices: string[]) => {
          if (selectCount++ !== 0) return "close";
          const shortcutRows = choices.filter((choice) => choice.startsWith("shortcut  "));
          assert.equal(shortcutRows.length, 1);
          const [shortcutRow] = shortcutRows;
          return shortcutRow;
        },
        input: async () => {
          inputCount++;
          return undefined;
        },
        custom: async () => {
          customCount++;
          return undefined;
        },
        notify() {},
      },
    } as unknown as ExtensionCommandContext;

    await commandHandler("settings", ctx);

    assert.equal(customCount, 1, "the settings UI should open a one-key shortcut recorder");
    assert.equal(inputCount, 0, "users should not need to type strings such as ctrl+alt+d");
  });

  it("explains a locale environment override before asking for a locale", async (t) => {
    const previousLocale = process.env.PI_DICTATION_LOCALE;
    process.env.PI_DICTATION_LOCALE = "en-GB";
    t.after(() => {
      if (previousLocale === undefined) delete process.env.PI_DICTATION_LOCALE;
      else process.env.PI_DICTATION_LOCALE = previousLocale;
    });
    const { commandHandler } = await loadExtension();
    let selectCount = 0;
    let inputCount = 0;
    const warnings: string[] = [];

    const ctx = {
      mode: "tui",
      ui: {
        select: async (_title: string, choices: string[]) => {
          if (selectCount++ !== 0) return "close";
          return choices.find((choice) => choice.startsWith("locale    "));
        },
        input: async () => {
          inputCount++;
          return "en-AU";
        },
        notify(message: string, level: string) {
          if (level === "warning") warnings.push(message);
        },
      },
    } as unknown as ExtensionCommandContext;

    await commandHandler("settings", ctx);

    assert.equal(inputCount, 0);
    assert.deepEqual(warnings, ["Unset PI_DICTATION_LOCALE before saving a locale here."]);
  });

  it("records the pressed combination and removes Shift from a modified letter's identity", async () => {
    setKittyProtocolActive(true);
    try {
      let renders = 0;
      const ctx = {
        mode: "tui",
        ui: {
          custom: async (factory: (
            tui: { requestRender(): void },
            theme: { bold(text: string): string; fg(color: string, text: string): string },
            keybindings: object,
            done: (value: string | undefined) => void,
          ) => { handleInput(data: string): void }) => new Promise<string | undefined>((resolve) => {
            const tui = { requestRender: () => renders++ };
            const theme = {
              bold: (text: string) => text,
              fg: (_color: string, text: string) => text,
            };
            const component = factory(tui, theme, {}, resolve);
            component.handleInput("\x1b[68:68:100;8u");
          }),
        },
      } as unknown as ExtensionCommandContext;

      assert.equal(await captureShortcut(ctx, "ctrl+alt+d"), "ctrl+alt+d");
      assert.equal(renders, 0);
    } finally {
      setKittyProtocolActive(false);
    }
  });

  it("registers one logical letter shortcut for lower-case, Shift, and Caps Lock input", async (t) => {
    const previousShortcut = process.env.PI_DICTATION_SHORTCUT;
    process.env.PI_DICTATION_SHORTCUT = "ctrl+alt+d";
    t.after(() => {
      if (previousShortcut === undefined) delete process.env.PI_DICTATION_SHORTCUT;
      else process.env.PI_DICTATION_SHORTCUT = previousShortcut;
    });
    const { shortcuts } = await loadExtension();
    const keys = shortcuts.map(({ key }) => key);
    assert.deepEqual(keys, ["ctrl+alt+d", "ctrl+shift+alt+d"]);

    setKittyProtocolActive(true);
    try {
      const inputs = [
        "\x1b[100;7u", // Ctrl+Alt+d
        "\x1b[68:68:100;8u", // Ctrl+Alt+Shift+D
        "\x1b[68:68:100;71u", // Ctrl+Alt+D with Caps Lock
      ];
      for (const input of inputs) {
        assert.equal(
          keys.some((key) => matchesKey(input, key)),
          true,
          `expected ${JSON.stringify(input)} to match the registered logical shortcut`,
        );
      }
    } finally {
      setKittyProtocolActive(false);
    }
  });
});
