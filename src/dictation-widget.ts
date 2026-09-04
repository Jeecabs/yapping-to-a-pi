import type { Theme } from "@earendil-works/pi-coding-agent";
import {
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
  type TUI,
  type TuiMouseEvent,
  type TuiMouseEventResult,
} from "@earendil-works/pi-tui";
import type { DictationSnapshot } from "./controller.ts";

export class DictationWidget {
  private disposed = false;
  private buttonWidth = 0;

  private readonly tui: TUI;
  private readonly theme: Pick<Theme, "fg">;
  private snapshot: DictationSnapshot;
  private readonly shortcut: string;
  private readonly onToggle: () => void;

  constructor(tui: TUI, theme: Pick<Theme, "fg">, snapshot: DictationSnapshot, shortcut: string, onToggle: () => void) {
    this.tui = tui;
    this.theme = theme;
    this.snapshot = snapshot;
    this.shortcut = shortcut;
    this.onToggle = onToggle;
  }

  update(snapshot: DictationSnapshot): void {
    this.snapshot = snapshot;
    this.tui.requestRender();
  }

  render(width: number): string[] {
    this.buttonWidth = 0;
    if (this.disposed) return [];
    const { phase } = this.snapshot;
    const inactive = phase === "idle" || phase === "failed";
    const clickable = this.tui.mode === "fullscreen";
    if (inactive && !clickable) return [];

    const label = phase === "listening" ? "■ Stop mic"
      : phase === "preparing" ? "Cancel mic"
      : phase === "stopping" ? "Finalizing…"
      : "● Dictate";
    const color = phase === "listening" ? "success" : phase === "stopping" ? "dim" : "accent";
    const shortLabel = phase === "listening" ? "Stop" : phase === "preparing" ? "Cancel"
      : phase === "stopping" ? "Wait" : "Mic";
    const fullControl = clickable ? `[ ${label} ]` : label;
    const compactControl = clickable ? `[${shortLabel}]` : shortLabel;
    const button = visibleWidth(fullControl) + 1 <= width ? fullControl : compactControl;
    // A clipped label is not an actionable target.
    if (clickable && width >= visibleWidth(button) + 1) this.buttonWidth = visibleWidth(button);
    const control = this.theme.fg(color, button);
    const hint = phase === "stopping" ? "text stays editable"
      : phase === "preparing" ? `${this.shortcut} · preparing microphone`
      : phase === "listening" ? `${this.shortcut} · stop and insert`
      : `${this.shortcut}`;
    const availableHintWidth = width - visibleWidth(button) - 3;
    const shortHint = phase === "stopping" ? "" : this.shortcut;
    const fittedHint = visibleWidth(hint) <= availableHintWidth ? hint
      : visibleWidth(shortHint) <= availableHintWidth ? shortHint : "";
    const status = truncateToWidth(` ${control}${fittedHint ? `  ${this.theme.fg("dim", fittedHint)}` : ""}`, width, "");
    const partial = this.snapshot.partialText?.trim().replace(/\s+/g, " ");
    if (phase !== "listening" || !partial) return [status];
    const transcript = wrapTextWithAnsi(this.theme.fg("text", partial), Math.max(1, width - 1))
      .slice(-2)
      .map((line) => truncateToWidth(` ${line}`, width, ""));
    return [status, ...transcript];
  }

  handleMouse(event: TuiMouseEvent): TuiMouseEventResult | undefined {
    if (this.disposed || this.tui.mode !== "fullscreen" || event.button !== "left"
      || event.y !== 0 || event.x < 1 || event.x >= 1 + this.buttonWidth
      || event.shift || event.alt || event.ctrl) return undefined;
    if (event.type !== "press" && event.type !== "release" && event.type !== "click") return undefined;
    if (event.type === "click" && (event.clickCount ?? 1) === 1 && this.snapshot.phase !== "stopping") {
      this.onToggle();
    }
    // Keep editor focus and suppress selection on the button itself.
    return { handled: true };
  }

  invalidate(): void {
    this.buttonWidth = 0;
  }

  dispose(): void {
    this.disposed = true;
    this.buttonWidth = 0;
  }
}
