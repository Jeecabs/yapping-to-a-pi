import Foundation

final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            waiter.resume(returning: true)
        }
    }

    /// Returns true once stopped, or false if the waiting task is cancelled first.
    func wait() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if stopped {
                    lock.unlock()
                    continuation.resume(returning: true)
                } else if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(returning: false)
                } else {
                    waiters[id] = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            let waiter = waiters.removeValue(forKey: id)
            lock.unlock()
            waiter?.resume(returning: false)
        }
    }

    func isStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func performUnlessStopped<T>(_ operation: () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return nil }
        return try operation()
    }
}
