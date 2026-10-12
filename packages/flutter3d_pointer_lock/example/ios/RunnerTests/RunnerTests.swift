import Flutter
import UIKit
import XCTest

import flutter3d_pointer_lock

/// The parts of the iOS side a simulator can reach without a mouse.
class RunnerTests: XCTestCase {

  func testTheChannelsAreTheOnesEveryOtherPlatformAnswersOn() {
    XCTAssertEqual(
      Flutter3dPointerLockPlugin.methodChannelName, "dev.flutter3d/flutter3d_pointer_lock")
    XCTAssertEqual(
      Flutter3dPointerLockPlugin.eventChannelName,
      Flutter3dPointerLockPlugin.methodChannelName + "/events")
    XCTAssertEqual(Flutter3dPointerLockPlugin.stateReleased, 0)
    XCTAssertEqual(Flutter3dPointerLockPlugin.stateCaptured, 1)
  }

  func testSupportedOnAnIPadWithAMouseOnly() {
    XCTAssertFalse(Flutter3dPointerLockPlugin.supports(isPad: false, mice: 1))
    XCTAssertFalse(Flutter3dPointerLockPlugin.supports(isPad: true, mice: 0))
    XCTAssertTrue(Flutter3dPointerLockPlugin.supports(isPad: true, mice: 1))
  }

  func testUpOnTheMouseIsUpOnTheScreen() {
    // GameController counts y upwards; a camera that pitched the other way
    // would be the first thing a player noticed.
    XCTAssertEqual(Flutter3dPointerLockPlugin.screenDelta(x: 3, y: 2), [3, -2])
  }

  func testTheMethodChannelAnswersEveryCallDartMakes() {
    let plugin = Flutter3dPointerLockPlugin()
    for method in ["capture", "release", "reset"] {
      let answered = expectation(description: method)
      plugin.handle(FlutterMethodCall(methodName: method, arguments: nil)) { result in
        XCTAssertNil(result, method)
        answered.fulfill()
      }
    }
    let captured = expectation(description: "isCaptured")
    plugin.handle(FlutterMethodCall(methodName: "isCaptured", arguments: nil)) { result in
      // A simulator has no mouse, so the capture above had nothing to lock.
      XCTAssertEqual(result as? Bool, false)
      captured.fulfill()
    }
    let unknown = expectation(description: "unknown")
    plugin.handle(FlutterMethodCall(methodName: "getPlatformVersion", arguments: nil)) { result in
      XCTAssertTrue((result as AnyObject) === FlutterMethodNotImplemented)
      unknown.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
