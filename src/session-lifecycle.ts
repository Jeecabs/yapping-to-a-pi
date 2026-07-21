export type GuardedResult<T> =
  | { status: "completed"; value: T }
  | { status: "failed"; error: unknown }
  | { status: "stale" };

export class SessionLifecycle {
  private generation = 0;
  private active = false;

  activate(): void {
    this.generation += 1;
    this.active = true;
  }

  deactivate(): void {
    this.generation += 1;
    this.active = false;
  }

  async guard<T>(operation: () => Promise<T>): Promise<GuardedResult<T>> {
    const generation = this.generation;
    let result: GuardedResult<T>;
    try {
      result = { status: "completed", value: await operation() };
    } catch (error) {
      result = { status: "failed", error };
    }

    if (!this.active || generation !== this.generation) return { status: "stale" };
    return result;
  }
}
