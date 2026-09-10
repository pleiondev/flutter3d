/// The geometry a modeller's overlay puts in front of the surface.
///
/// **Everything here is arithmetic, and that is deliberate.** What the overlay
/// draws is decided on the CPU — where a vertex handle's corners are, how wide
/// a ribbon is, how far towards the eye the whole thing sits — and every one of
/// those is a number a test can hold to a value without a GPU anywhere. What a
/// picture is for is the part this cannot reach: that the depth test lets an
/// edge sit on its own face, which is `mesh-overlay` in the golden set.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An overlay looking down −Z from ten units away, with a pixel that is a
/// hundredth of a unit at one unit of distance.
MeshOverlay looking({Vector3? eye, bool perspective = true}) {
  final overlay = MeshOverlay(
    vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
    fragmentShader: const ShaderHandle(backend: 1, name: 'DebugLine'),
  )..biasPixels = 0;
  overlay.lookFrom(
    eye: eye ?? Vector3(0, 0, 10),
    right: Vector3(1, 0, 0),
    up: Vector3(0, 1, 0),
    pixel: 0.01,
    perspective: perspective,
  );
  return overlay;
}

/// The positions a batch holds, three floats at a time.
List<Vector3> positionsOf(OverlayBatch batch) {
  final floats = Float32List.sublistView(
    batch.vertexBytes.buffer.asByteData(
      batch.vertexBytes.offsetInBytes,
      batch.vertexBytes.lengthInBytes,
    ),
  );
  return <Vector3>[
    for (var v = 0; v < batch.vertexCount; v++)
      Vector3(
        floats[v * MeshOverlay.floatsPerVertex],
        floats[v * MeshOverlay.floatsPerVertex + 1],
        floats[v * MeshOverlay.floatsPerVertex + 2],
      ),
  ];
}

/// The alpha of every vertex a batch holds.
List<double> alphasOf(OverlayBatch batch) {
  final floats = Float32List.sublistView(
    batch.vertexBytes.buffer.asByteData(
      batch.vertexBytes.offsetInBytes,
      batch.vertexBytes.lengthInBytes,
    ),
  );
  return <double>[
    for (var v = 0; v < batch.vertexCount; v++)
      floats[v * MeshOverlay.floatsPerVertex + 6],
  ];
}

/// How wide the box round [points] is in x.
double widthOf(List<Vector3> points) {
  var low = double.infinity;
  var high = double.negativeInfinity;
  for (final at in points) {
    if (at.x < low) low = at.x;
    if (at.x > high) high = at.x;
  }
  return high - low;
}

void main() {
  group('the three batches', () {
    test('an empty overlay has nothing to draw', () {
      final overlay = looking();

      expect(overlay.isActive, isFalse);
      expect(overlay.lines.isEmpty, isTrue);
      expect(overlay.handles.isEmpty, isTrue);
      expect(overlay.fill.isEmpty, isTrue);
    });

    test('a thousand edges are one buffer, not a thousand', () {
      final overlay = looking();
      for (var i = 0; i < 1000; i++) {
        overlay.edge(
          Vector3(i.toDouble(), 0, 0),
          Vector3(0, 1, 0),
          Vector4(1, 1, 1, 1),
        );
      }

      // Two vertices apiece in one array. Mutation: give each edge its own
      // batch and this is still a thousand edges and a thousand draw calls —
      // which is the difference between an overlay a modeller can leave on and
      // one it turns off at ten thousand.
      expect(overlay.lines.vertexCount, 2000);
      expect(overlay.handles.isEmpty, isTrue);
      expect(overlay.isActive, isTrue);
    });

    test('clearing keeps the buffer and drops the contents', () {
      final overlay = looking();
      for (var i = 0; i < 500; i++) {
        overlay.edge(Vector3.zero(), Vector3(1, 0, 0), Vector4(1, 0, 0, 1));
      }
      overlay.clear();

      expect(overlay.lines.vertexCount, 0);
      expect(overlay.isActive, isFalse);
      // And it fills again without complaint, which is what a selection
      // changing every frame does to it.
      overlay.edge(Vector3.zero(), Vector3(1, 0, 0), Vector4(1, 0, 0, 1));
      expect(overlay.lines.vertexCount, 2);
    });
  });

  group('a handle keeps its size on screen', () {
    test('a point twice as far away is twice as wide in the world', () {
      final near = looking()..point(Vector3(0, 0, 5), Vector4(1, 1, 1, 1));
      final far = looking()..point(Vector3(0, 0, 0), Vector4(1, 1, 1, 1));

      // Five units away against ten: the far one has to be twice the size in
      // metres to be the same size in pixels. Mutation: size it in world units
      // and both are the same width — which is a vertex handle that vanishes
      // as somebody pulls the camera back, and the one thing a handle may not
      // do is become unhittable.
      expect(widthOf(positionsOf(near.handles)), closeTo(7 * 0.01 * 5, 1e-5));
      expect(widthOf(positionsOf(far.handles)), closeTo(7 * 0.01 * 10, 1e-5));
    });

    test('an orthographic camera sizes it the same everywhere', () {
      final near = looking(perspective: false)
        ..point(Vector3(0, 0, 5), Vector4(1, 1, 1, 1));
      final far = looking(perspective: false)
        ..point(Vector3(0, 0, -50), Vector4(1, 1, 1, 1));

      // Nothing shrinks with distance in an orthographic view, and neither
      // does the handle.
      expect(widthOf(positionsOf(near.handles)), closeTo(7 * 0.01, 1e-5));
      expect(widthOf(positionsOf(far.handles)), closeTo(7 * 0.01, 1e-5));
    });

    test('it is two triangles facing the camera', () {
      final overlay = looking()..point(Vector3.zero(), Vector4(1, 1, 1, 1));
      final corners = positionsOf(overlay.handles);

      expect(corners, hasLength(6));
      // Square to the camera's own axes, so every corner is at the same depth.
      for (final at in corners) {
        expect(at.z, closeTo(0, 1e-6));
      }
    });
  });

  group('a ribbon', () {
    test('is as wide as it was asked for, across the line it follows', () {
      final overlay = looking()
        ..ribbon(
          Vector3(0, -1, 0),
          Vector3(0, 1, 0),
          Vector4(1, 1, 1, 1),
          width: 4,
        );
      final corners = positionsOf(overlay.handles);

      // Running up y and seen down z, so the width is in x.
      expect(corners, hasLength(6));
      expect(widthOf(corners), closeTo(4 * 0.01 * 10, 1e-4));
    });

    test('a band of no length draws nothing rather than dividing by it', () {
      final overlay = looking()
        ..ribbon(Vector3.zero(), Vector3.zero(), Vector4(1, 1, 1, 1));

      // Mutation: normalise the direction without checking, and every
      // degenerate edge in a model puts NaN into the buffer — which draws as
      // nothing on one backend and as the whole screen on another.
      expect(overlay.handles.isEmpty, isTrue);
    });

    test('it turns to face the camera rather than keeping a fixed side', () {
      final fromTheSide = looking(eye: Vector3(10, 0, 0))
        ..ribbon(Vector3(0, -1, 0), Vector3(0, 1, 0), Vector4(1, 1, 1, 1));
      final corners = positionsOf(fromTheSide.handles);

      // Seen down x now, so the width has moved to z and there is none in x.
      expect(widthOf(corners), closeTo(0, 1e-4));
      var lowZ = double.infinity;
      var highZ = double.negativeInfinity;
      for (final at in corners) {
        if (at.z < lowZ) lowZ = at.z;
        if (at.z > highZ) highZ = at.z;
      }
      expect(highZ - lowZ, greaterThan(0.1));
    });
  });

  group('a fill', () {
    test('lets the shading under it through', () {
      final overlay = looking()
        ..wash(
          Vector3.zero(),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          Vector4(0, 0.31, 0.35, 1),
        );

      // Mutation: take the caller's alpha, and a selection drawn with an
      // opaque colour hides the surface it is selecting — which tells a person
      // the face is selected and nothing about its shape.
      expect(alphasOf(overlay.fill), everyElement(closeTo(0.55, 1e-6)));
      expect(MeshOverlay.fillOpacity, 0.55);
      expect(overlay.fill.vertexCount, 3);
    });
  });

  group('sitting on the surface', () {
    test('the nudge towards the eye grows with distance', () {
      final overlay = MeshOverlay(
        vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
        fragmentShader: const ShaderHandle(backend: 1, name: 'DebugLine'),
      )..biasPixels = 10;
      overlay.lookFrom(
        eye: Vector3(0, 0, 10),
        right: Vector3(1, 0, 0),
        up: Vector3(0, 1, 0),
        pixel: 0.01,
      );
      overlay
        ..edge(Vector3(0, 0, 5), Vector3(0, 0, 5), Vector4(1, 1, 1, 1))
        ..edge(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector4(1, 1, 1, 1));

      final at = positionsOf(overlay.lines);
      // Five units away, ten units away: the nudge is a constant in pixels, so
      // it is twice as far in metres at twice the distance. Mutation: nudge by
      // a fixed number of world units, and it disappears under the depth
      // buffer's precision at one end of the scene and detaches the overlay at
      // the other.
      expect(at[0].z - 5, closeTo(10 * 0.01 * 5, 1e-5));
      expect(at[2].z - 0, closeTo(10 * 0.01 * 10, 1e-5));
    });

    test('a point at the eye is left where it is', () {
      final overlay = looking()..biasPixels = 10;
      overlay.edge(Vector3(0, 0, 10), Vector3(0, 0, 10), Vector4(1, 1, 1, 1));

      // Nothing to nudge along: dividing by that distance would be dividing by
      // zero, and a NaN in a vertex buffer is a frame nobody can debug.
      final at = positionsOf(overlay.lines);
      expect(at.first.z, closeTo(10, 1e-6));
      expect(at.first.x.isNaN, isFalse);
    });
  });

  group('the order it draws in', () {
    test('it goes over the scene rather than into it', () {
      final overlay = looking();

      // Everything the renderer contributes is ordered, and an overlay that
      // encoded before the meshes would be painted over by them.
      expect(overlay.order, greaterThan(0));
      expect(overlay.order, greaterThan(const _Ordinary().order));
    });
  });
}

/// A contributor with no opinion about when it runs, for comparison.
final class _Ordinary extends PassContributor {
  const _Ordinary();

  @override
  void encode(ContributorFrame frame) {}
}
