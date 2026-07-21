import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { SessionLifecycle } from "../src/session-lifecycle.ts";

describe("SessionLifecycle", () => {
  it("rejects async work that completes after session shutdown", async () => {
    const lifecycle = new SessionLifecycle();
    lifecycle.activate();
    let finish: (() => void) | undefined;
    const preflight = new Promise<void>((resolve) => {
      finish = resolve;
    });

    const guarded = lifecycle.guard(() => preflight);
    lifecycle.deactivate();
    finish?.();

    assert.deepEqual(await guarded, { status: "stale" });
  });

  it("returns current failures while suppressing stale failures", async () => {
    const lifecycle = new SessionLifecycle();
    lifecycle.activate();
    const current = await lifecycle.guard(async () => {
      throw new Error("missing helper");
    });
    assert.equal(current.status, "failed");

    lifecycle.deactivate();
    assert.deepEqual(await lifecycle.guard(async () => undefined), { status: "stale" });
  });
});
