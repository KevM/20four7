import Foundation

protocol Clock: AnyObject {
    func now() -> Date
    /// Schedule `work` after `seconds`. Returns a token; calling `cancel()` stops it.
    func schedule(after seconds: TimeInterval, _ work: @escaping @Sendable @MainActor () -> Void) -> ClockToken
}

protocol ClockToken: AnyObject, Sendable { func cancel() }

final class SystemClock: Clock {
    func now() -> Date { Date() }
    func schedule(after seconds: TimeInterval, _ work: @escaping @Sendable @MainActor () -> Void) -> ClockToken {
        let token = TimerToken()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak token] _ in
            guard let token = token, !token.isCancelled else { return }
            Task { @MainActor in
                guard !token.isCancelled else { return }
                work()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        token.timer = timer
        return token
    }
    
    private final class TimerToken: ClockToken, @unchecked Sendable {
        private let lock = NSLock()
        private var _isCancelled = false
        private var _timer: Timer?
        
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }
        
        var timer: Timer? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _timer
            }
            set {
                lock.lock()
                let alreadyCancelled = _isCancelled
                _timer = newValue
                lock.unlock()
                if alreadyCancelled {
                    if let timer = newValue {
                        invalidate(timer)
                    }
                }
            }
        }
        
        func cancel() {
            lock.lock()
            _isCancelled = true
            let t = _timer
            _timer = nil
            lock.unlock()
            if let timer = t {
                invalidate(timer)
            }
        }
        
        private func invalidate(_ timer: Timer) {
            if Thread.isMainThread {
                timer.invalidate()
            } else {
                let wrapper = SendableTimer(timer)
                DispatchQueue.main.async {
                    wrapper.invalidate()
                }
            }
        }
        
        deinit { cancel() }
    }
}

private final class SendableTimer: @unchecked Sendable {
    private let timer: Timer
    init(_ timer: Timer) { self.timer = timer }
    func invalidate() { timer.invalidate() }
}

/// Deterministic clock for tests. `advance(by:)` fires due work.
final class ManualClock: Clock {
    private var current = Date(timeIntervalSince1970: 0)
    private final class Scheduled: ClockToken, @unchecked Sendable {
        let fireAt: TimeInterval
        let work: @MainActor () -> Void
        var cancelled = false
        init(fireAt: TimeInterval, work: @escaping @Sendable @MainActor () -> Void) { self.fireAt = fireAt; self.work = work }
        func cancel() { cancelled = true }
    }
    private var scheduled: [Scheduled] = []

    func now() -> Date { current }
    func schedule(after seconds: TimeInterval, _ work: @escaping @Sendable @MainActor () -> Void) -> ClockToken {
        let item = Scheduled(fireAt: current.timeIntervalSince1970 + seconds, work: work)
        scheduled.append(item)
        return item
    }
    @MainActor
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let due = scheduled.filter { !$0.cancelled && $0.fireAt <= current.timeIntervalSince1970 }
        scheduled.removeAll { item in due.contains { $0 === item } }
        due.forEach { $0.work() }
    }
}
