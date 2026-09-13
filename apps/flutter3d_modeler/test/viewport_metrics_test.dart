/// `deviceStaleForViewport` — the decision `_reopenDeviceIfStale` in
/// `main.dart` acts on, pulled out so it can be checked without a window.
library;

import 'package:flutter3d_modeler/src/viewport_metrics.dart';
import 'package:test/test.dart';

void main() {
  test('the same size and pixel ratio is not stale', () {
    expect(
      deviceStaleForViewport(
        lastWidth: 1600,
        lastHeight: 1000,
        lastDevicePixelRatio: 2,
        width: 1600,
        height: 1000,
        devicePixelRatio: 2,
      ),
      isFalse,
    );
  });

  test('shrinking is not a reason to reopen', () {
    expect(
      deviceStaleForViewport(
        lastWidth: 1600,
        lastHeight: 1000,
        lastDevicePixelRatio: 2,
        width: 800,
        height: 500,
        devicePixelRatio: 2,
      ),
      isFalse,
    );
  });

  test('growing past either dimension is stale', () {
    expect(
      deviceStaleForViewport(
        lastWidth: 1600,
        lastHeight: 1000,
        lastDevicePixelRatio: 2,
        width: 1601,
        height: 1000,
        devicePixelRatio: 2,
      ),
      isTrue,
    );
    expect(
      deviceStaleForViewport(
        lastWidth: 1600,
        lastHeight: 1000,
        lastDevicePixelRatio: 2,
        width: 1600,
        height: 1001,
        devicePixelRatio: 2,
      ),
      isTrue,
    );
  });

  test('a changed pixel ratio is stale even at the same size', () {
    expect(
      deviceStaleForViewport(
        lastWidth: 1600,
        lastHeight: 1000,
        lastDevicePixelRatio: 1,
        width: 1600,
        height: 1000,
        devicePixelRatio: 2,
      ),
      isTrue,
    );
  });
}
