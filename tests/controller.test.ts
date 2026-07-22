import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  DictationController,
  type DictationSnapshot,
  type HelperCallbacks,
  type HelperSession,
  type StartHelper,
} from "../src/controller.ts";

class FakeHelper implements HelperSession {
  readonly callbacks: HelperCallbacks;
  stopRequests = 0;
  killSignals: NodeJS.Signals[] = [];

  constructor(callbacks: HelperCallbacks) {
    this.callbacks = callbacks;
  }

  requestStop(): void {
    this.stopRequests += 1;
  }

  kill(signal: NodeJS.Signals = "SIGTERM"): void {
    this.killSignals.push(signal);
  }

  exit(code = 0): void {
    this.callbacks.onExit({ code, signal: null, stderr: "" });
  }
}

describe("DictationController", () => {
  it("owns the recording state machine and emits one final transcript", () => {
    const states: DictationSnapshot[] = [];
    const transcripts: string[] = [];
    let helper: FakeHelper | undefined;
    const startHelper: StartHelper = (_options, callbacks) => {
      helper = new FakeHelper(callbacks);
      return helper;
    };
    const controller = new DictationController({
      startHelper,
      onStateChange: (state) => states.push(state),
      onTranscript: (text) => transcripts.push(text),
    });

    assert.equal(controller.toggle({ executable: "/helper", locale: "en-AU" }), "started");
    helper?.callbacks.onMessage({
      type: "state",
      state: "listening",
      locale: "en-AU",
      inputDevice: "MacBook Pro Microphone",
    });
    helper?.callbacks.onMessage({ type: "partial", text: "hello" });
    helper?.callbacks.onMessage({ type: "final", text: " Hello world. " });
    helper?.callbacks.onMessage({ type: "final", text: "duplicate" });
    helper?.exit();

    assert.deepEqual(transcripts, ["Hello world."]);
    assert.equal(states[1]?.inputDevice, "MacBook Pro Microphone");
    assert.equal(states[2]?.partialText, "hello");
    assert.equal(controller.snapshot().phase, "idle");
    assert.deepEqual(states.map((state) => state.phase), ["preparing", "listening", "listening", "idle"]);
  });

  it("uses a second toggle as a graceful stop request", () => {
    let helper: FakeHelper | undefined;
    const controller = new DictationController({
      startHelper: (_options, callbacks) => {
        helper = new FakeHelper(callbacks);
        return helper;
      },
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    assert.equal(controller.toggle({ executable: "/helper", locale: "en-AU" }), "stop-requested");
    assert.equal(helper?.stopRequests, 1);
    assert.equal(controller.snapshot().phase, "stopping");
    helper?.exit();
  });

  it("surfaces helper errors and can start again", () => {
    const helpers: FakeHelper[] = [];
    const controller = new DictationController({
      startHelper: (_options, callbacks) => {
        const helper = new FakeHelper(callbacks);
        helpers.push(helper);
        return helper;
      },
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    helpers[0]?.callbacks.onMessage({ type: "error", code: "microphone-denied", message: "No microphone." });
    assert.equal(controller.snapshot().phase, "failed");
    assert.deepEqual(helpers[0]?.killSignals, ["SIGTERM"]);
    helpers[0]?.exit(1);

    assert.equal(controller.toggle({ executable: "/helper", locale: "en-AU" }), "started");
    assert.equal(helpers.length, 2);
    helpers[1]?.exit();
  });

  it("stops and waits for the helper during disposal", async () => {
    let helper: FakeHelper | undefined;
    const controller = new DictationController({
      startHelper: (_options, callbacks) => {
        helper = new FakeHelper(callbacks);
        return helper;
      },
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    const disposal = controller.dispose();
    assert.equal(helper?.stopRequests, 1);
    helper?.exit();
    await disposal;
    assert.equal(controller.snapshot().phase, "idle");
  });

  it("handles a helper that exits synchronously when stopped", async () => {
    const controller = new DictationController({
      startHelper: (_options, callbacks) => ({
        requestStop: () => callbacks.onExit({ code: 0, signal: null, stderr: "" }),
        kill: () => {},
      }),
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    await controller.dispose();
    assert.equal(controller.snapshot().phase, "idle");
  });

  it("does not regress from stopping when late helper states arrive", () => {
    let helper: FakeHelper | undefined;
    const controller = new DictationController({
      startHelper: (_options, callbacks) => {
        helper = new FakeHelper(callbacks);
        return helper;
      },
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    controller.stop("command");
    helper?.callbacks.onMessage({ type: "state", state: "listening", locale: "en-AU" });
    helper?.callbacks.onMessage({ type: "partial", text: "too late" });

    assert.equal(controller.snapshot().phase, "stopping");
    assert.equal(controller.snapshot().partialText, undefined);
    helper?.exit();
  });

  it("escalates shutdown and resolves even when a helper never exits", async () => {
    let helper: FakeHelper | undefined;
    const controller = new DictationController({
      startHelper: (_options, callbacks) => {
        helper = new FakeHelper(callbacks);
        return helper;
      },
      stopTimeoutMs: 5,
      killTimeoutMs: 5,
      disposeTimeoutMs: 20,
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    await controller.dispose();

    assert.deepEqual(helper?.killSignals, ["SIGTERM", "SIGKILL"]);
    assert.equal(controller.snapshot().phase, "idle");
  });

  it("treats forced cancellation as idle rather than failed", async () => {
    let helper: FakeHelper | undefined;
    const controller = new DictationController({
      startHelper: (_options, callbacks) => {
        helper = new FakeHelper(callbacks);
        return helper;
      },
      stopTimeoutMs: 1,
      killTimeoutMs: 50,
    });

    controller.toggle({ executable: "/helper", locale: "en-AU" });
    controller.stop("command");
    await new Promise((resolve) => setTimeout(resolve, 5));
    helper?.callbacks.onExit({ code: null, signal: "SIGTERM", stderr: "" });

    assert.equal(controller.snapshot().phase, "idle");
  });
});
