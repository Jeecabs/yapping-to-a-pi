import assert from "node:assert/strict";
import { it } from "node:test";
import { Container, Input, TuiAltScreen, type Terminal } from "@earendil-works/pi-tui";
import { DictationController, type HelperCallbacks } from "../src/controller.ts";
import { DictationWidget } from "../src/dictation-widget.ts";

it("routes fullscreen mic clicks without stealing editor focus or submitting the draft", async (t) => {
  t.mock.timers.enable({ apis: ["Date"] });
  let input: ((data: string) => void) | undefined;
  const terminal: Terminal = {
    columns: 80, rows: 24, kittyProtocolActive: false,
    start(onInput) { input = onInput; },
    stop() {}, async drainInput() {}, write() {}, moveBy() {}, hideCursor() {},
    showCursor() {}, clearLine() {}, clearFromCursor() {}, clearScreen() {},
    setTitle() {}, setProgress() {},
  };
  const tui = new TuiAltScreen(terminal);
  const editor = new Input();
  editor.setValue("Draft: ");
  editor.handleInput("\x05"); // End of draft.
  let submissions = 0;
  editor.onSubmit = () => { submissions++; };
  let callbacks: HelperCallbacks | undefined;
  let starts = 0;
  let stops = 0;
  const controller = new DictationController({
    startHelper(_options, next) {
      callbacks = next;
      starts++;
      return {
        requestStop() { stops++; },
        kill() { next.onExit({ code: 0, signal: null, stderr: "" }); },
      };
    },
    onStateChange(snapshot) { widget.update(snapshot); },
    onTranscript(text) { editor.handleInput(text); },
  });
  const widget = new DictationWidget(tui, { fg: (_color, text) => text }, controller.snapshot(), "f6", () => {
    controller.toggle({ executable: "/unused", locale: "en-AU" });
  });
  const root = new Container();
  root.addChild(widget);
  root.addChild(editor);
  tui.setLayoutRoot(root);
  tui.setFocus(editor);
  tui.start();
  tui.renderNow();
  t.after(async () => {
    callbacks?.onExit({ code: 0, signal: null, stderr: "" });
    widget.dispose();
    await controller.dispose();
    tui.stop();
  });

  function click(x: number, y = 1): void {
    assert.ok(input);
    input(`\x1b[<0;${x};${y}M`);
    input(`\x1b[<0;${x};${y}m`);
    tui.renderNow();
  }

  click(40); // Hint/blank area must not start capture.
  assert.equal(starts, 0);
  click(3);
  assert.equal(starts, 1);
  assert.equal(controller.snapshot().phase, "preparing");
  assert.ok(callbacks);
  callbacks.onMessage({ type: "state", state: "listening", locale: "en-AU" });
  callbacks.onMessage({ type: "partial", text: "spoken draft" });
  tui.renderNow();
  click(3); // Accidental double-click must not immediately stop.
  assert.equal(stops, 0);
  assert.ok(input);
  input("typed ");
  assert.equal(editor.getValue(), "Draft: typed ");
  assert.equal(editor.focused, true);

  t.mock.timers.tick(1000);
  click(3);
  assert.equal(stops, 1);
  assert.equal(controller.snapshot().phase, "stopping");
  t.mock.timers.tick(1000);
  click(3); // Disabled while finalizing.
  assert.equal(stops, 1);
  callbacks.onMessage({ type: "final", text: "spoken text" });
  callbacks.onExit({ code: 0, signal: null, stderr: "" });
  tui.renderNow();
  assert.equal(editor.getValue(), "Draft: typed spoken text");
  assert.equal(submissions, 0);
  assert.equal(editor.focused, true);

  widget.dispose();
  t.mock.timers.tick(1000);
  click(3); // Stale mouse targets cannot restart a disposed session.
  assert.equal(starts, 1);
});
