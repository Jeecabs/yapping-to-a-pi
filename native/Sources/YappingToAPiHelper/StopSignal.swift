import Foundation

final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            waiter.resume(returning: true)
        }
    }

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if stopped {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
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
