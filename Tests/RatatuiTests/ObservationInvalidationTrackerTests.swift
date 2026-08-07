import Foundation
import Observation
import Testing

@testable import Ratatui

@Observable
private final class ObservedValue {
  var value = 0
  var unrelated = 0
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  var value: Int { lock.withLock { storage } }
  func increment() { lock.withLock { storage += 1 } }
}

@Suite struct ObservationInvalidationTrackerTests {
  @Test func tracksOnlyReadDependenciesAndRearmsAfterRendering() {
    let model = ObservedValue()
    let callbacks = LockedCounter()
    let tracker = ObservationInvalidationTracker { callbacks.increment() }

    #expect(tracker.track { model.value } == 0)
    model.unrelated = 1
    #expect(callbacks.value == 0)

    model.value = 1
    #expect(callbacks.value == 1)
    model.value = 2
    #expect(callbacks.value == 1)

    #expect(tracker.track { model.value } == 2)
    model.value = 3
    #expect(callbacks.value == 2)
  }

  @Test func ignoresCallbacksFromObsoleteDependencyGenerations() {
    let first = ObservedValue()
    let second = ObservedValue()
    let callbacks = LockedCounter()
    let tracker = ObservationInvalidationTracker { callbacks.increment() }

    #expect(tracker.track { first.value } == 0)
    #expect(tracker.track(refresh: true) { second.value } == 0)

    first.value = 1
    #expect(callbacks.value == 0)

    second.value = 1
    #expect(callbacks.value == 1)
  }
}
