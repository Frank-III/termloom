import Testing

@testable import Ratatui

@Suite struct TerminalSessionTests {
  private enum ProbeError: Error, Equatable {
    case operation
    case cleanup
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
}
