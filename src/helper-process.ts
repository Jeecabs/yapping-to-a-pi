import { spawn } from "node:child_process";
import { access } from "node:fs/promises";
import { createInterface } from "node:readline";

import type { HelperCallbacks, HelperSession, StartHelper } from "./controller.js";
import { parseDoctorMessage, parseHelperMessage, type DoctorMessage } from "./protocol.js";

const MAX_STDERR_LENGTH = 8_192;

export const startNativeHelper: StartHelper = (options, callbacks) => {
  const child = spawn(options.executable, ["--locale", options.locale], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderr = "";
  let closed = false;

  const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
  lines.on("line", (line) => {
    if (!line.trim()) return;
    try {
      callbacks.onMessage(parseHelperMessage(line));
    } catch (error) {
      callbacks.onTransportError(asError(error));
    }
  });

  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => {
    stderr = `${stderr}${chunk}`.slice(-MAX_STDERR_LENGTH);
  });

  child.on("error", (error) => callbacks.onTransportError(error));
  child.on("close", (code, signal) => {
    if (closed) return;
    closed = true;
    lines.close();
    callbacks.onExit({ code, signal, stderr });
  });

  return {
    requestStop(): void {
      if (!child.stdin.destroyed && child.stdin.writable) child.stdin.end("\n");
    },
    kill(): void {
      if (!child.killed) child.kill("SIGTERM");
    },
  } satisfies HelperSession;
};

export async function assertHelperExists(executable: string): Promise<void> {
  try {
    await access(executable);
  } catch {
    throw new Error(`Dictation helper not found at ${executable}. Run pnpm build:native.`);
  }
}

export async function runHelperDoctor(options: {
  executable: string;
  locale: string;
  timeoutMs?: number;
}): Promise<DoctorMessage> {
  await assertHelperExists(options.executable);

  return new Promise<DoctorMessage>((resolve, reject) => {
    const child = spawn(options.executable, ["--doctor", "--locale", options.locale], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      settleReject(new Error("Dictation diagnostics timed out."));
    }, options.timeoutMs ?? 10_000);
    timeout.unref?.();

    const settleReject = (error: Error): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    };

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdout = `${stdout}${chunk}`.slice(-MAX_STDERR_LENGTH);
    });
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderr = `${stderr}${chunk}`.slice(-MAX_STDERR_LENGTH);
    });
    child.on("error", (error) => settleReject(error));
    child.on("close", (code) => {
      if (settled) return;
      if (code !== 0) {
        settleReject(new Error(stderr.trim() || `Dictation diagnostics exited with code ${code ?? "unknown"}.`));
        return;
      }

      const line = stdout.split("\n").find((candidate) => candidate.trim());
      if (!line) {
        settleReject(new Error("Dictation diagnostics returned no result."));
        return;
      }

      try {
        const message = parseDoctorMessage(line);
        settled = true;
        clearTimeout(timeout);
        resolve(message);
      } catch (error) {
        settleReject(asError(error));
      }
    });
  });
}

function asError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}
