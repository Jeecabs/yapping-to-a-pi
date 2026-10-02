import type { HelperMessage } from "./protocol.ts";

export type DictationPhase = "idle" | "preparing" | "listening" | "stopping" | "failed";

export interface DictationSnapshot {
  phase: DictationPhase;
  locale?: string;
  inputDevice?: string;
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
  kill(signal?: NodeJS.Signals): void;
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
  killTimeoutMs?: number;
  disposeTimeoutMs?: number;
}

interface ExitWaiter {
  generation: number;
  resolve(): void;
}

type Termination = "none" | "timed-out" | "cancelled";

export class DictationController {
  private readonly startHelper: StartHelper;
  private readonly onStateChange?: (snapshot: DictationSnapshot) => void;
  private readonly onTranscript?: (text: string) => void;
  private readonly stopTimeoutMs: number;
  private readonly killTimeoutMs: number;
  private readonly disposeTimeoutMs: number;
  private current: DictationSnapshot = { phase: "idle" };
  private session?: HelperSession;
  private generation = 0;
  private activeGeneration?: number;
  private stopTimer?: NodeJS.Timeout;
  private killTimer?: NodeJS.Timeout;
  private settleTimer?: NodeJS.Timeout;
  private finalReceived = false;
  private termination: Termination = "none";
  private hardKillSent = false;
  private stoppedWhileListening = false;
  private latestPartial?: string;
  private exitWaiters: ExitWaiter[] = [];

  constructor(options: DictationControllerOptions) {
    this.startHelper = options.startHelper;
    this.onStateChange = options.onStateChange;
    this.onTranscript = options.onTranscript;
    this.stopTimeoutMs = options.stopTimeoutMs ?? 4_000;
    this.killTimeoutMs = options.killTimeoutMs ?? 1_000;
    this.disposeTimeoutMs = options.disposeTimeoutMs ?? this.killTimeoutMs * 2 + 1_000;
  }

  snapshot(): DictationSnapshot {
    return { ...this.current };
  }

  toggle(options: { executable: string; locale: string }): "started" | "stop-requested" {
    if (this.session) {
      this.stop("toggle");
      return "stop-requested";
    }

    const generation = ++this.generation;
    this.activeGeneration = generation;
    this.finalReceived = false;
    this.termination = "none";
    this.hardKillSent = false;
    this.stoppedWhileListening = false;
    this.latestPartial = undefined;
    this.transition({ phase: "preparing", locale: options.locale });

    try {
      const session = this.startHelper(options, {
        onMessage: (message) => this.handleMessage(generation, message),
        onTransportError: (error) => this.fail(generation, error.message),
        onExit: (exit) => this.handleExit(generation, exit),
      });
      if (this.activeGeneration === generation) {
        this.session = session;
      } else {
        session.kill("SIGKILL");
      }
    } catch (error) {
      this.fail(generation, error instanceof Error ? error.message : String(error));
    }

    return "started";
  }

  stop(_reason: "toggle" | "command"): boolean {
    const generation = this.activeGeneration;
    if (!this.session || generation === undefined) return false;
    if (this.current.phase !== "stopping") {
      this.stoppedWhileListening = this.current.phase === "listening";
      this.transition({ ...this.current, phase: "stopping", partialText: undefined });
      this.armStopTimeout(generation);
      this.session.requestStop();
    }
    return true;
  }

  async dispose(): Promise<void> {
    const generation = this.activeGeneration;
    if (!this.session || generation === undefined) return;

    const exited = new Promise<void>((resolve) => this.exitWaiters.push({ generation, resolve }));
    // Shutdown discards the transcript, so finalizing would only delay Pi's exit.
    this.termination = "cancelled";
    if (this.current.phase !== "stopping" && this.current.phase !== "failed") {
      this.transition({ ...this.current, phase: "stopping", partialText: undefined });
    }
    this.terminate(generation);

    let disposeTimer: NodeJS.Timeout | undefined;
    const deadline = new Promise<void>((resolve) => {
      disposeTimer = setTimeout(() => {
        if (this.activeGeneration === generation) {
          if (!this.hardKillSent) this.session?.kill("SIGKILL");
          this.detach(generation, { phase: "idle" });
        }
        resolve();
      }, this.disposeTimeoutMs);
    });

    await Promise.race([exited, deadline]);
    if (disposeTimer) clearTimeout(disposeTimer);
  }

  private handleMessage(generation: number, message: HelperMessage): void {
    if (!this.isActive(generation)) return;

    if (message.type === "state") {
      if (this.current.phase === "stopping" || this.current.phase === "failed") return;
      const phase: DictationPhase = message.state === "listening"
        ? "listening"
        : message.state === "finalizing"
          ? "stopping"
          : "preparing";
      // A listening update after an input-device change keeps the visible preview.
      const partialText = phase === "listening" ? this.current.partialText : undefined;
      this.transition({ phase, locale: message.locale, inputDevice: message.inputDevice, partialText });
      return;
    }

    if (message.type === "partial") {
      // Finalization can still refine the preview after it stops being shown.
      this.latestPartial = message.text;
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

    this.fail(generation, message.message);
  }

  private handleExit(generation: number, exit: HelperExit): void {
    if (!this.isActive(generation)) return;

    if (this.current.phase === "failed") {
      this.detach(generation);
      return;
    }

    if (exit.code === 0 || this.finalReceived) {
      this.detach(generation, { phase: "idle" });
      return;
    }

    if (this.termination !== "none") {
      this.detachTerminated(generation);
      return;
    }

    const detail = exit.stderr.trim();
    this.detach(generation, {
      phase: "failed",
      error: detail || `Dictation helper exited${exit.signal ? ` (${exit.signal})` : ` with code ${exit.code ?? "unknown"}`}.`,
    });
  }

  private detachTerminated(generation: number): void {
    if (this.termination !== "timed-out" || !this.stoppedWhileListening || this.finalReceived) {
      this.detach(generation, { phase: "idle" });
      return;
    }

    // Losing a long recording is worse than inserting the less polished live preview.
    const preview = this.latestPartial?.trim();
    if (preview) {
      this.finalReceived = true;
      this.onTranscript?.(preview);
    }
    this.detach(generation, {
      phase: "failed",
      error: preview
        ? "Dictation took too long to finish, so the live preview was inserted. Check it before sending."
        : "Dictation took too long to finish. Nothing was inserted.",
    });
  }

  private fail(generation: number, message: string): void {
    if (!this.isActive(generation)) return;
    this.transition({ phase: "failed", error: message });
    this.session?.kill("SIGTERM");
  }

  private isActive(generation: number): boolean {
    return this.activeGeneration === generation;
  }

  private detach(generation: number, next?: DictationSnapshot): void {
    if (!this.isActive(generation)) return;
    this.clearTerminationTimers();
    this.session = undefined;
    this.activeGeneration = undefined;
    if (next) this.transition(next);

    const waiting = this.exitWaiters.filter((waiter) => waiter.generation === generation);
    this.exitWaiters = this.exitWaiters.filter((waiter) => waiter.generation !== generation);
    for (const waiter of waiting) waiter.resolve();
  }

  private transition(next: DictationSnapshot): void {
    this.current = next;
    this.onStateChange?.(this.snapshot());
  }

  private armStopTimeout(generation: number): void {
    this.clearTerminationTimers();
    this.stopTimer = setTimeout(() => {
      if (!this.isActive(generation)) return;
      this.termination = "timed-out";
      this.terminate(generation);
    }, this.stopTimeoutMs);
    this.stopTimer.unref?.();
  }

  private terminate(generation: number): void {
    this.clearTerminationTimers();
    // Arm escalation first so a synchronous exit during SIGTERM clears it.
    this.killTimer = setTimeout(() => {
      if (!this.isActive(generation)) return;
      this.hardKillSent = true;
      this.session?.kill("SIGKILL");
      this.settleTimer = setTimeout(() => {
        if (this.isActive(generation)) this.detachTerminated(generation);
      }, this.killTimeoutMs);
      this.settleTimer.unref?.();
    }, this.killTimeoutMs);
    this.killTimer.unref?.();
    this.session?.kill("SIGTERM");
  }

  private clearTerminationTimers(): void {
    if (this.stopTimer) clearTimeout(this.stopTimer);
    if (this.killTimer) clearTimeout(this.killTimer);
    if (this.settleTimer) clearTimeout(this.settleTimer);
    this.stopTimer = undefined;
    this.killTimer = undefined;
    this.settleTimer = undefined;
  }
}
