// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AeroFlowIPC
import Foundation

struct IPCEventStreamRegistration: Sendable {
    let channel: IPCSubscriptionChannel
    let id: UUID
    let stream: AsyncStream<IPCEventEnvelope>
}

final class IPCEventDemandTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [IPCSubscriptionChannel: Int] = [:]

    func increment(_ channel: IPCSubscriptionChannel) {
        lock.lock()
        counts[channel, default: 0] += 1
        lock.unlock()
    }

    func decrement(_ channel: IPCSubscriptionChannel) {
        lock.lock()
        let nextValue = max(0, (counts[channel] ?? 0) - 1)
        if nextValue == 0 {
            counts.removeValue(forKey: channel)
        } else {
            counts[channel] = nextValue
        }
        lock.unlock()
    }

    func hasSubscribers(for channel: IPCSubscriptionChannel) -> Bool {
        lock.lock()
        let result = (counts[channel] ?? 0) > 0
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        counts.removeAll()
        lock.unlock()
    }
}

final class IPCEventContinuationTable: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [IPCSubscriptionChannel: [UUID: AsyncStream<IPCEventEnvelope>.Continuation]] = [:]

    func insert(id: UUID, channel: IPCSubscriptionChannel, continuation: AsyncStream<IPCEventEnvelope>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        continuations[channel, default: [:]][id] = continuation
    }

    @discardableResult
    func remove(id: UUID, from channel: IPCSubscriptionChannel) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard continuations[channel]?.removeValue(forKey: id) != nil else { return false }
        if continuations[channel]?.isEmpty == true {
            continuations.removeValue(forKey: channel)
        }
        return true
    }

    nonisolated func snapshot(for channel: IPCSubscriptionChannel) -> [AsyncStream<IPCEventEnvelope>.Continuation] {
        lock.lock()
        defer { lock.unlock() }
        return continuations[channel]?.values.map { $0 } ?? []
    }

    func finishAll() -> [AsyncStream<IPCEventEnvelope>.Continuation] {
        lock.lock()
        defer { lock.unlock() }
        let all = continuations.values.flatMap(\.values)
        continuations.removeAll()
        return all
    }
}

actor IPCEventBroker {
    nonisolated private let continuationTable = IPCEventContinuationTable()
    nonisolated private let demandTracker: IPCEventDemandTracker

    init(demandTracker: IPCEventDemandTracker = IPCEventDemandTracker()) {
        self.demandTracker = demandTracker
    }

    func registerStream(for channel: IPCSubscriptionChannel) -> IPCEventStreamRegistration {
        let id = UUID()
        var capturedContinuation: AsyncStream<IPCEventEnvelope>.Continuation?
        let stream = AsyncStream<IPCEventEnvelope>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            capturedContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id, from: channel)
                }
            }
        }

        if let capturedContinuation {
            continuationTable.insert(id: id, channel: channel, continuation: capturedContinuation)
            demandTracker.increment(channel)
        }
        return IPCEventStreamRegistration(channel: channel, id: id, stream: stream)
    }

    func stream(for channel: IPCSubscriptionChannel) -> AsyncStream<IPCEventEnvelope> {
        registerStream(for: channel).stream
    }

    func publish(_ event: IPCEventEnvelope) {
        publishNow(event)
    }

    /// Yields the event to current subscribers without an actor hop.
    /// AsyncStream continuations are thread-safe, so callers on the main
    /// thread can publish synchronously instead of queueing behind an
    /// in-flight relayout.
    nonisolated func publishNow(_ event: IPCEventEnvelope) {
        for continuation in continuationTable.snapshot(for: event.channel) {
            continuation.yield(event)
        }
    }

    func removeStream(id: UUID, from channel: IPCSubscriptionChannel) {
        removeContinuation(id: id, from: channel)
    }

    func finishAll() {
        let currentContinuations = continuationTable.finishAll()
        demandTracker.reset()
        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    nonisolated func hasSubscribers(for channel: IPCSubscriptionChannel) -> Bool {
        demandTracker.hasSubscribers(for: channel)
    }

    private func removeContinuation(id: UUID, from channel: IPCSubscriptionChannel) {
        guard continuationTable.remove(id: id, from: channel) else { return }
        demandTracker.decrement(channel)
    }
}
