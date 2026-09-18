/// Where a box in the world lands on the glass — `gfx-79n`.
///
///     dart test test/engine/screen_bounds_test.dart
///
/// The projection the accessibility layer puts a focus ring around, and the one
/// three other callers had been writing by hand. What it has to get right is
/// small and each part is a separate way to be wrong: the Y flip, the divide by
/// w, and what to do about a box the eye is inside.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _width = 400;
const double _height = 300;

/// A camera at the origin looking down −Z, the engine's own forward.
Matrix4 _camera({Vector3? at, Vector3? lookAt}) {
  final node = CameraNode()
    ..setPosition(at?.x ?? 0.0, at?.y ?? 0.0, at?.z ?? 0.0);
  if (lookAt != null) node.lookAt(lookAt);
  return node.viewProjection(_width / _height);
}

void main() {
  test('a point straight ahead lands in the middle', () {
    final at = projectPoint(
      _camera(),
      Vector3(0.0, 0.0, -5.0),
      width: _width,
      height: _height,
    );
    expect(at, isNotNull);
    expect(at!.x, closeTo(_width / 2, 1e-6));
    expect(at.y, closeTo(_height / 2, 1e-6));
  });

  test('up in the world is up on the glass', () {
    // The one flip this function owes its callers, and the one that is
    // invisible in a symmetric scene: +Y is up in clip space and down in a
    // window, so a point above the axis has to come back with a *smaller* y.
    final above = projectPoint(
      _camera(),
      Vector3(0.0, 1.0, -5.0),
      width: _width,
      height: _height,
    )!;
    final below = projectPoint(
      _camera(),
      Vector3(0.0, -1.0, -5.0),
      width: _width,
      height: _height,
    )!;
    expect(above.y, lessThan(_height / 2));
    expect(below.y, greaterThan(_height / 2));
    // Symmetric about the middle, which says the flip is a flip and not an
    // offset that happens to point the right way.
    expect(above.y + below.y, closeTo(_height, 1e-6));
  });

  test('twice as far is half as far from the middle', () {
    // The divide by w. Without it the answer is linear in the world position
    // and a distant object is drawn the size of a near one.
    final near = projectPoint(
      _camera(),
      Vector3(1.0, 0.0, -5.0),
      width: _width,
      height: _height,
    )!;
    final far = projectPoint(
      _camera(),
      Vector3(1.0, 0.0, -10.0),
      width: _width,
      height: _height,
    )!;
    expect(near.x - _width / 2, closeTo((far.x - _width / 2) * 2, 1e-6));
  });

  test('a point behind the eye has no place on the glass', () {
    expect(
      projectPoint(
        _camera(),
        Vector3(0.0, 0.0, 5.0),
        width: _width,
        height: _height,
      ),
      isNull,
      reason: 'a point behind the camera was projected anyway',
    );
  });

  test('a box in front becomes the rectangle over its corners', () {
    final bounds = screenBoundsOfBox(
      _camera(),
      Aabb3.minMax(Vector3(-1.0, -1.0, -6.0), Vector3(1.0, 1.0, -4.0)),
      width: _width,
      height: _height,
    );
    expect(bounds, isNotNull);
    // Centred, because the box is; and the near face is wider on the glass
    // than the far one, so the rectangle is the near face's.
    expect(bounds!.left + bounds.right, closeTo(_width, 1e-6));
    expect(bounds.top + bounds.bottom, closeTo(_height, 1e-6));
    expect(bounds.right - bounds.left, greaterThan(0.0));
  });

  test('a box entirely behind the eye has no rectangle at all', () {
    expect(
      screenBoundsOfBox(
        _camera(),
        Aabb3.minMax(Vector3(-1.0, -1.0, 4.0), Vector3(1.0, 1.0, 6.0)),
        width: _width,
        height: _height,
      ),
      isNull,
    );
  });

  test('a box the eye is inside gives back the whole viewport', () {
    // **The case with no honest rectangle, and the reason it is not the
    // corners that happened to be in front.** Those corners are a strict
    // subset of what is visible — the object runs off every edge — so their
    // box is too small, and a focus ring drawn to it sits *inside* the thing
    // it is supposed to surround. The viewport is the smallest rectangle that
    // is certainly not too small.
    final bounds = screenBoundsOfBox(
      _camera(),
      Aabb3.minMax(Vector3(-2.0, -2.0, -2.0), Vector3(2.0, 2.0, 2.0)),
      width: _width,
      height: _height,
    );
    expect(bounds, isNotNull);
    expect(bounds!.left, 0.0);
    expect(bounds.top, 0.0);
    expect(bounds.right, _width);
    expect(bounds.bottom, _height);
  });

  test('a box off to one side is not clamped to the viewport', () {
    // A caller that wants the on-screen part can intersect; one that wants to
    // know the object is off to the left cannot get that back from a clamped
    // answer. So the rectangle is allowed to sit outside.
    final bounds = screenBoundsOfBox(
      _camera(),
      Aabb3.minMax(Vector3(-40.0, -1.0, -6.0), Vector3(-30.0, 1.0, -4.0)),
      width: _width,
      height: _height,
    )!;
    expect(bounds.right, lessThan(0.0));
  });
}
