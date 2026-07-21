import assert from "node:assert/strict";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it } from "node:test";

import type { HelperSession } from "../src/controller.ts";
import { startNativeHelper } from "../src/helper-process.ts";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

describe("native helper process adapter", () => {
  it("treats EPIPE while requesting stop as an expected close race", async () => {
    const directory = await mkdtemp(join(tmpdir(), "yapping-helper-test-"));
    temporaryDirectories.push(directory);
    const executable = join(directory, "close-stdin-helper");
    await writeFile(
      executable,
      `#!/bin/sh\nexec 0<&-\nprintf '%s\\n' '{"type":"state","state":"listening","locale":"en-AU"}'\nsleep 0.05\n`,
    );
    await chmod(executable, 0o755);

    const transportErrors: Error[] = [];
    let session: HelperSession | undefined;
    const exited = new Promise<void>((resolve) => {
      session = startNativeHelper(
        { executable, locale: "en-AU" },
        {
          onMessage: () => session?.requestStop(),
          onTransportError: (error) => transportErrors.push(error),
          onExit: () => resolve(),
        },
      );
    });

    await exited;
    assert.deepEqual(transportErrors, []);
  });
});
