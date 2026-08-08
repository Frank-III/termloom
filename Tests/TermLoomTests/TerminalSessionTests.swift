import Foundation
import Testing

@testable import TermLoom

@Suite struct TerminalSessionTests {
  private enum ProbeError: Error, Equatable {
    case operation
    case cleanup
    case commit
    case recovery
  }

  private final class TransactionSink: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var storage: [Data] = []
    var failingCalls: [Int: ProbeError]

    init(failingCalls: [Int: ProbeError]) {
      self.failingCalls = failingCalls
    }

    func write(_ data: Data) throws {
      try lock.withLock {
        callCount += 1
        if let error = failingCalls[callCount] {
          storage.append(Data(data.prefix(min(3, data.count))))
          throw error
        }
        storage.append(data)
      }
    }

    var writes: [Data] { lock.withLock { storage } }
  }

  @Test func successfulOperationAndCleanupReturnTheValue() throws {
    var cleanupCount = 0
    let value = try withTerminalCleanup {
      42
    } cleanup: {
      cleanupCount += 1
    }

    #expect(value == 42)
    #expect(cleanupCount == 1)
  }

  @Test func failedCleanupReplacesASuccessfulOperation() {
    #expect(throws: ProbeError.cleanup) {
      try withTerminalCleanup {
        42
      } cleanup: {
        throw ProbeError.cleanup
      }
    }
  }

  @Test func failedOperationSurvivesSuccessfulCleanup() {
    var cleanupCount = 0
    #expect(throws: ProbeError.operation) {
      try withTerminalCleanup {
        throw ProbeError.operation
      } cleanup: {
        cleanupCount += 1
      }
    }
    #expect(cleanupCount == 1)
  }

  @Test func dualFailurePreservesBothErrors() throws {
    do {
      _ = try withTerminalCleanup {
        throw ProbeError.operation
      } cleanup: {
        throw ProbeError.cleanup
      }
      Issue.record("Expected both terminal scope failures")
    } catch let error as TerminalScopeError {
      #expect(error.operationError as? ProbeError == .operation)
      #expect(error.cleanupError as? ProbeError == .cleanup)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @MainActor
  @Test func asynchronousScopesUseTheSameCleanupPolicy() async throws {
    do {
      _ = try await withTerminalCleanup {
        try await Task.sleep(for: .milliseconds(1))
        throw ProbeError.operation
      } cleanup: {
        throw ProbeError.cleanup
      }
      Issue.record("Expected both terminal scope failures")
    } catch let error as TerminalScopeError {
      #expect(error.operationError as? ProbeError == .operation)
      #expect(error.cleanupError as? ProbeError == .cleanup)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func failedCommitWritesAnUnbufferedRecoveryEpilogueAndCanRetry() throws {
    let sink = TransactionSink(failingCalls: [1: .commit])
    let output = TransactionalTerminalOutput(directWrite: sink.write)

    #expect(throws: ProbeError.commit) {
      try output.withTransaction {
        try output.write(Data("frame".utf8))
      }
    }
    #expect(
      sink.writes == [Data("fra".utf8), TransactionalTerminalOutput.emergencyRecoverySequence])

    try output.withTransaction {
      try output.write(Data("retry".utf8))
    }
    #expect(sink.writes.last == Data("retry".utf8))
  }

  @Test func failedCommitAndRecoveryPreserveBothErrors() throws {
    let sink = TransactionSink(failingCalls: [1: .commit, 2: .recovery])
    let output = TransactionalTerminalOutput(directWrite: sink.write)

    do {
      try output.withTransaction {
        try output.write(Data("frame".utf8))
      }
      Issue.record("Expected commit and recovery failures")
    } catch let error as TerminalScopeError {
      #expect(error.operationError as? ProbeError == .commit)
      #expect(error.cleanupError as? ProbeError == .recovery)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
