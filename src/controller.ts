import type { HelperMessage } from "./protocol.js";

export type DictationPhase = "idle" | "preparing" | "listening" | "stopping" | "failed";

export interface DictationSnapshot {
  phase: DictationPhase;
  locale?: string;
  partialText?: string;
  error?: string;
}

export interface HelperExit {
  code: number | null;
  signal: NodeJS.Signals | null;
  stderr: string;
}

export interface HelperSession {
  requestStop(): void;
  kill(): void;
}

export interface HelperCallbacks {
  onMessage(message: HelperMessage): void;
  onTransportError(error: Error): void;
  onExit(exit: HelperExit): void;
}

export type StartHelper = (
  options: { executable: string; locale: string },
  callbacks: HelperCallbacks,
) => HelperSession;

interface DictationControllerOptions {
  startHelper: StartHelper;
  onStateChange?: (snapshot: DictationSnapshot) => void;
  onTranscript?: (text: string) => void;
  stopTimeoutMs?: number;
}

export class DictationController {
  private readonly startHelper: StartHelper;
  private readonly onStateChange?: (snapshot: DictationSnapshot) => void;
  private readonly onTranscript?: (text: string) => void;
  private readonly stopTimeoutMs: number;
  private current: DictationSnapshot = { phase: "idle" };
  private session?: HelperSession;
  private stopTimer?: NodeJS.Timeout;
  private finalReceived = false;
  private exitWaiters: Array<() => void> = [];

  constructor(options: DictationControllerOptions) {
    this.startHelper = options.startHelper;
    this.onStateChange = options.onStateChange;
    this.onTranscript = options.onTranscript;
    this.stopTimeoutMs = options.stopTimeoutMs ?? 4_000;
  }

  snapshot(): DictationSnapshot {
    return { ...this.current };
  }

  toggle(options: { executable: string; locale: string }): "started" | "stop-requested" {
    if (this.session) {
      this.stop("toggle");
      return "stop-requested";
    }

    this.finalReceived = false;
    this.transition({ phase: "preparing", locale: options.locale });

    try {
      this.session = this.startHelper(options, {
        onMessage: (message) => this.handleMessage(message),
        onTransportError: (error) => this.fail(error.message),
        onExit: (exit) => this.handleExit(exit),
      });
    } catch (error) {
      this.fail(error instanceof Error ? error.message : String(error));
    }

    return "started";
  }

  stop(_reason: "toggle" | "command" | "shutdown"): boolean {
    if (!this.session) return false;
    if (this.current.phase !== "stopping") {
      this.transition({ ...this.current, phase: "stopping", partialText: undefined });
      this.session.requestStop();
      this.armStopTimeout();
    }
    return true;
  }

  async dispose(): Promise<void> {
    if (!this.session) return;
    const exited = new Promise<void>((resolve) => this.exitWaiters.push(resolve));
    this.stop("shutdown");
    await exited;
  }

  private handleMessage(message: HelperMessage): void {
    if (!this.session) return;

    if (message.type === "state") {
      const phase: DictationPhase = message.state === "listening"
        ? "listening"
        : message.state === "finalizing"
          ? "stopping"
          : "preparing";
      this.transition({ phase, locale: message.locale });
      return;
    }

    if (message.type === "partial") {
      if (this.current.phase === "listening") {
        this.transition({ ...this.current, partialText: message.text });
      }
      return;
    }

    if (message.type === "final") {
      if (this.finalReceived) return;
      this.finalReceived = true;
      const text = message.text.trim();
      if (text) this.onTranscript?.(text);
      return;
    }

    this.fail(message.message);
  }

  private handleExit(exit: HelperExit): void {
    this.clearStopTimeout();
    this.session = undefined;

    if (this.current.phase !== "failed") {
      if (exit.code === 0 || this.finalReceived) {
        this.transition({ phase: "idle" });
      } else {
        const detail = exit.stderr.trim();
        this.transition({
          phase: "failed",
          error: detail || `Dictation helper exited${exit.signal ? ` (${exit.signal})` : ` with code ${exit.code ?? "unknown"}`}.`,
        });
      }
    }

    const waiters = this.exitWaiters.splice(0);
    for (const resolve of waiters) resolve();
  }

  private fail(message: string): void {
    this.transition({ phase: "failed", error: message });
    this.session?.kill();
  }

  private transition(next: DictationSnapshot): void {
    this.current = next;
    this.onStateChange?.(this.snapshot());
  }

  private armStopTimeout(): void {
    this.clearStopTimeout();
    this.stopTimer = setTimeout(() => this.session?.kill(), this.stopTimeoutMs);
    this.stopTimer.unref?.();
  }

  private clearStopTimeout(): void {
    if (!this.stopTimer) return;
    clearTimeout(this.stopTimer);
    this.stopTimer = undefined;
  }
}
