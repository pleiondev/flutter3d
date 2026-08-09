import Cocoa
import FlutterMacOS
import XCTest

@testable import mouse_capture

/// The little of the native side that can be checked without a window.
///
/// Capture itself cannot be: it needs a key window and a real cursor, and the
/// meaningful failures — a stranded cursor after losing focus, deltas that stop
/// arriving — only appear against the window server. Those are covered by
/// running the example app. What is left here is the state machine's floor,
/// which is worth pinning because `reset` is called on every launch and must be
/// harmless when there is nothing to reset.
class RunnerTests: XCTestCase {

  func testStartsUncaptured() {
    let plugin = MouseCapturePlugin()
    let call = FlutterMethodCall(methodName: "isCaptured", arguments: nil)

    let done = expectation(description: "result block must be called")
    plugin.handle(call) { result in
      XCTAssertEqual(result as? Bool, false)
      done.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testResetIsHarmlessWhenNothingIsCaptured() {
    let plugin = MouseCapturePlugin()
    let call = FlutterMethodCall(methodName: "reset", arguments: nil)

    let done = expectation(description: "result block must be called")
    plugin.handle(call) { result in
      XCTAssertNil(result)
      done.fulfill()
    }
    waitForExpectations(timeout: 1)

    let check = FlutterMethodCall(methodName: "isCaptured", arguments: nil)
    let checked = expectation(description: "result block must be called")
    plugin.handle(check) { result in
      XCTAssertEqual(result as? Bool, false)
      checked.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testUnknownMethodIsReportedAsNotImplemented() {
    let plugin = MouseCapturePlugin()
    let call = FlutterMethodCall(methodName: "nonsense", arguments: nil)

    let done = expectation(description: "result block must be called")
    plugin.handle(call) { result in
      XCTAssertTrue(result is NSObject && result as? NSObject == FlutterMethodNotImplemented)
      done.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
