import Foundation

protocol Clock: AnyObject {
    func now() -> Date
    /// Schedule `work` after `seconds`. Returns a token; calling `cancel()` stops it.
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> ClockToken
}

protocol ClockToken: AnyObject { func cancel() }

final class SystemClock: Clock {
    func now() -> Date { Date() }
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> ClockToken {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in work() }
        return TimerToken(timer: timer)
    }
    private final class TimerToken: ClockToken {
        let timer: Timer
        init(timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}

/// Deterministic clock for tests. `advance(by:)` fires due work.
final class ManualClock: Clock {
    private var current = Date(timeIntervalSince1970: 0)
    private final class Scheduled: ClockToken {
        let fireAt: TimeInterval
        let work: () -> Void
        var cancelled = false
        init(fireAt: TimeInterval, work: @escaping () -> Void) { self.fireAt = fireAt; self.work = work }
        func cancel() { cancelled = true }
    }
    private var scheduled: [Scheduled] = []

    func now() -> Date { current }
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> ClockToken {
        let item = Scheduled(fireAt: current.timeIntervalSince1970 + seconds, work: work)
        scheduled.append(item)
        return item
    }
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let due = scheduled.filter { !$0.cancelled && $0.fireAt <= current.timeIntervalSince1970 }
        scheduled.removeAll { item in due.contains { $0 === item } }
        due.forEach { $0.work() }
    }
}
