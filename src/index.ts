import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  Theme,
} from "@earendil-works/pi-coding-agent";
import {
  isKeyRelease,
  isKeyRepeat,
  matchesKey,
  parseKey,
  truncateToWidth,
  type TUI,
} from "@earendil-works/pi-tui";
import { fileURLToPath } from "node:url";

import {
  canonicalizeLocale,
  canonicalizeShortcut,
  loadDictationConfig,
  saveDictationConfig,
  shortcutVariants,
  shortcutWarning,
  isValidShortcut,
  isValidLocale,
} from "./config.ts";
import { DictationController, type DictationSnapshot } from "./controller.ts";
import { assertHelperExists, runHelperDoctor, startNativeHelper } from "./helper-process.ts";
import { SessionLifecycle } from "./session-lifecycle.ts";
import { DictationWidget } from "./dictation-widget.ts";

const STATUS_ID = "yapping-to-a-pi";
const FEEDBACK_WIDGET_ID = "yapping-to-a-pi-feedback";
const DEFAULT_HELPER_PATH = fileURLToPath(
  new URL("../native/.build/YappingToAPiHelper.app/Contents/MacOS/yapping-to-a-pi-helper", import.meta.url),
);

export default async function daDictation(pi: ExtensionAPI) {
  let config = await loadDictationConfig({ defaultHelperPath: DEFAULT_HELPER_PATH });
  let activeContext: ExtensionContext | undefined;
  let acceptTranscript = false;
  let notifiedError: string | undefined;
  let configWarningsShown = false;
  let startPending = false;
  let feedbackWidget: DictationWidget | undefined;
  const lifecycle = new SessionLifecycle();

  const controller = new DictationController({
    startHelper: startNativeHelper,
    onStateChange(snapshot) {
      const ctx = activeContext;
      if (!ctx?.hasUI) return;
      feedbackWidget = renderStatus(ctx, snapshot, feedbackWidget, config.shortcut, () => {
        void toggle(ctx).catch((error: unknown) => ctx.ui.notify(String(error), "error"));
      });
      if (snapshot.phase === "failed" && snapshot.error && snapshot.error !== notifiedError) {
        notifiedError = snapshot.error;
        ctx.ui.notify(snapshot.error, "error");
      }
      if (snapshot.phase !== "failed") notifiedError = undefined;
    },
    onTranscript(text) {
      if (!acceptTranscript) return;
      activeContext?.ui.pasteToEditor(text);
    },
  });

  const toggle = async (ctx: ExtensionContext): Promise<void> => {
    activeContext = ctx;
    acceptTranscript = true;
    const phase = controller.snapshot().phase;
    if (phase !== "idle" && phase !== "failed") {
      controller.toggle({ executable: config.helperPath, locale: config.locale });
      return;
    }
    if (startPending) return;

    startPending = true;
    const preflight = await lifecycle.guard(() => assertHelperExists(config.helperPath));
    startPending = false;
    if (preflight.status === "stale") return;
    if (preflight.status === "failed") {
      const message = preflight.error instanceof Error ? preflight.error.message : String(preflight.error);
      ctx.ui.notify(message, "error");
      return;
    }
    if (controller.snapshot().phase === "idle" || controller.snapshot().phase === "failed") {
      controller.toggle({ executable: config.helperPath, locale: config.locale });
    }
  };

  pi.on("session_start", (_event, ctx) => {
    lifecycle.activate();
    activeContext = ctx;
    acceptTranscript = true;
    feedbackWidget = renderStatus(ctx, controller.snapshot(), feedbackWidget, config.shortcut, () => {
      void toggle(ctx).catch((error: unknown) => ctx.ui.notify(String(error), "error"));
    });
    if (!configWarningsShown) {
      for (const warning of config.warnings) ctx.ui.notify(warning, "warning");
      configWarningsShown = true;
    }
  });

  pi.on("session_shutdown", async () => {
    lifecycle.deactivate();
    acceptTranscript = false;
    feedbackWidget?.dispose();
    feedbackWidget = undefined;
    const ctx = activeContext;
    activeContext = undefined;
    if (ctx?.hasUI) {
      ctx.ui.setWidget(FEEDBACK_WIDGET_ID, undefined);
      ctx.ui.setStatus(STATUS_ID, undefined);
    }
    await controller.dispose();
  });

  for (const shortcut of shortcutVariants(config.shortcut)) {
    pi.registerShortcut(shortcut, {
      description: "Toggle on-device dictation",
      handler: toggle,
    });
  }

  pi.registerCommand("dictation", {
    description: "Toggle or configure on-device dictation",
    handler: async (args, ctx) => {
      const [subcommand = "", ...rest] = args.trim().split(/\s+/).filter(Boolean);

      if (!subcommand) {
        await toggle(ctx);
        return;
      }

      if (subcommand === "stop") {
        controller.stop("command");
        return;
      }

      if (subcommand === "status") {
        ctx.ui.notify(formatStatus(controller.snapshot(), config), "info");
        return;
      }

      if (subcommand === "doctor") {
        await showDoctor(ctx);
        return;
      }

      if (subcommand === "settings" || subcommand === "config") {
        await showSettings(ctx);
        return;
      }

      if (subcommand === "shortcut") {
        const shortcut = rest.join("");
        await updateShortcut(shortcut, ctx);
        return;
      }

      if (subcommand === "locale") {
        if (rest.length > 1) {
          ctx.ui.notify("Use one locale, such as en-AU.", "warning");
          return;
        }
        const [locale = ""] = rest;
        await updateLocale(locale, ctx);
        return;
      }

      ctx.ui.notify("/dictation [stop | status | settings | doctor]", "info");
    },
  });

  async function showDoctor(ctx: ExtensionContext): Promise<void> {
    try {
      const result = await runHelperDoctor({ executable: config.helperPath, locale: config.locale });
      const model = result.supported ? (result.installed ? "ready" : "download needed") : "unsupported";
      const level = result.microphone === "denied" || result.microphone === "restricted"
        ? "error"
        : result.supported && result.installed && result.microphone === "authorized"
          ? "info"
          : "warning";
      ctx.ui.notify(`${result.locale} — ${result.inputDevice} — model ${model} — mic ${result.microphone}`, level);
    } catch (error) {
      ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
    }
  }

  async function showSettings(ctx: ExtensionCommandContext): Promise<void> {
    if (ctx.mode !== "tui") {
      ctx.ui.notify("/dictation settings requires the TUI", "error");
      return;
    }

    let reloadNeeded = false;
    while (true) {
      const shortcutSource = config.shortcutSource === "environment" ? " (env)" : "";
      const localeSource = config.localeSource === "environment" ? " (env)" : "";
      const shortcutRow = `shortcut  ${config.shortcut}${shortcutSource}`;
      const localeRow = `locale    ${config.locale}${localeSource}`;
      const choice = await ctx.ui.select("dictation", [shortcutRow, localeRow, "diagnostics", "close"]);

      if (!choice || choice === "close") break;
      if (choice === "diagnostics") {
        await showDoctor(ctx);
        continue;
      }
      if (choice === shortcutRow) {
        if (config.shortcutSource === "environment") {
          ctx.ui.notify("Unset PI_DICTATION_SHORTCUT before saving a shortcut here.", "warning");
          continue;
        }
        const value = await captureShortcut(ctx, config.shortcut);
        if (!value) continue;
        await saveDictationConfig({ shortcut: value });
        config = { ...config, shortcut: canonicalizeShortcut(value)!, shortcutSource: "file" };
        reloadNeeded = true;
        continue;
      }
      if (choice === localeRow) {
        const value = await ctx.ui.input("locale", config.locale);
        if (!value) continue;
        if (config.localeSource === "environment") {
          ctx.ui.notify("Unset PI_DICTATION_LOCALE before saving a locale here.", "warning");
          continue;
        }
        if (!isValidLocale(value)) {
          ctx.ui.notify("Use a BCP-47 locale such as en-AU.", "warning");
          continue;
        }
        await saveDictationConfig({ locale: value });
        config = { ...config, locale: canonicalizeLocale(value) ?? value, localeSource: "file" };
        reloadNeeded = true;
      }
    }

    if (reloadNeeded) {
      await ctx.reload();
      return;
    }
  }

  async function updateShortcut(shortcut: string, ctx: ExtensionCommandContext): Promise<void> {
    if (!shortcut) {
      ctx.ui.notify(`shortcut ${config.shortcut}`, "info");
      return;
    }
    if (config.shortcutSource === "environment") {
      ctx.ui.notify("PI_DICTATION_SHORTCUT currently overrides saved settings.", "warning");
      return;
    }
    const warning = shortcutWarning(shortcut);
    if (!isValidShortcut(shortcut) || warning) {
      ctx.ui.notify(warning ?? "Use a key such as ctrl+alt+d or f6.", "warning");
      return;
    }
    await saveDictationConfig({ shortcut });
    await ctx.reload();
    return;
  }

  async function updateLocale(locale: string, ctx: ExtensionCommandContext): Promise<void> {
    if (!locale) {
      ctx.ui.notify(`locale ${config.locale}`, "info");
      return;
    }
    if (config.localeSource === "environment") {
      ctx.ui.notify("PI_DICTATION_LOCALE currently overrides saved settings.", "warning");
      return;
    }
    if (!isValidLocale(locale)) {
      ctx.ui.notify("Use a BCP-47 locale such as en-AU.", "warning");
      return;
    }
    await saveDictationConfig({ locale });
    await ctx.reload();
    return;
  }
}

export async function captureShortcut(
  ctx: ExtensionCommandContext,
  currentShortcut: string,
): Promise<string | undefined> {
  if (ctx.mode !== "tui") return undefined;
  return ctx.ui.custom<string | undefined>((tui, theme, _keybindings, done) =>
    new ShortcutRecorder(tui, theme, currentShortcut, done),
  );
}

class ShortcutRecorder {
  private problem: string | undefined;
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly currentShortcut: string;
  private readonly done: (shortcut: string | undefined) => void;

  constructor(
    tui: TUI,
    theme: Theme,
    currentShortcut: string,
    done: (shortcut: string | undefined) => void,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.currentShortcut = currentShortcut;
    this.done = done;
  }

  handleInput(data: string): void {
    if (isKeyRelease(data) || isKeyRepeat(data)) return;
    if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
      this.done(undefined);
      return;
    }

    const parsed = parseKey(data);
    const shortcut = parsed ? canonicalizeShortcut(parsed) : undefined;
    if (!shortcut || !isValidShortcut(shortcut)) {
      this.problem = "That key could not be identified. Try another combination.";
      this.tui.requestRender();
      return;
    }

    const warning = shortcutWarning(shortcut);
    if (warning) {
      this.problem = warning;
      this.tui.requestRender();
      return;
    }

    this.done(shortcut);
  }

  render(width: number): string[] {
    const lines = [
      this.theme.fg("accent", this.theme.bold("Set dictation shortcut")),
      `Press the shortcut now. Current: ${currentShortcutLabel(this.currentShortcut)}`,
      this.problem
        ? this.theme.fg("warning", this.problem)
        : this.theme.fg("dim", "Esc or Ctrl+C cancels"),
    ];
    return lines.map((line) => truncateToWidth(line, width, ""));
  }

  invalidate(): void {}
}

function currentShortcutLabel(shortcut: string): string {
  return canonicalizeShortcut(shortcut) ?? shortcut;
}

function renderStatus(
  ctx: ExtensionContext,
  snapshot: DictationSnapshot,
  widget: DictationWidget | undefined,
  shortcut: string,
  onToggle: () => void,
): DictationWidget | undefined {
  if (snapshot.phase === "idle" || snapshot.phase === "failed") {
    ctx.ui.setStatus(STATUS_ID, undefined);
  } else if (snapshot.phase === "listening") {
    const theme = ctx.ui.theme;
    ctx.ui.setStatus(STATUS_ID, `${theme.fg("success", "●")} ${theme.fg("muted", "mic")}`);
  } else {
    const theme = ctx.ui.theme;
    const glyph = snapshot.phase === "stopping" ? "◌" : "◐";
    ctx.ui.setStatus(STATUS_ID, `${theme.fg("dim", glyph)} ${theme.fg("dim", "mic")}`);
  }

  if (ctx.mode !== "tui") return widget;
  if (widget) {
    widget.update(snapshot);
    return widget;
  }

  let created!: DictationWidget;
  ctx.ui.setWidget(FEEDBACK_WIDGET_ID, (tui, widgetTheme) => {
    created = new DictationWidget(tui, widgetTheme, snapshot, shortcut, onToggle);
    return created;
  });
  return created;
}

function formatStatus(snapshot: DictationSnapshot, config: Awaited<ReturnType<typeof loadDictationConfig>>): string {
  const inputDevice = snapshot.inputDevice ? ` — ${snapshot.inputDevice}` : "";
  const detail = snapshot.error ? ` — ${snapshot.error}` : "";
  return `${snapshot.phase}${inputDevice} — ${config.shortcut} — ${config.locale}${detail}`;
}
