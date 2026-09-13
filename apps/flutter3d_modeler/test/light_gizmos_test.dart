/// `mat-25`'s own acceptance: the light gizmos `view-05` already built
/// (`DebugDrawGizmos.addLightGizmo` — arrow, marker sphere, spot cone) drawn
/// correctly once `LightingSync.apply` turns the switch on.
///
///     flutter test test/light_gizmos_test.dart
///
/// **Geometry, not a golden.** `frame_test.dart`'s own doc comment already
/// argues this for the same reason: a golden of "does the cone look right"
/// fails the day somebody nudges the light five degrees and teaches nothing.
/// What this row's acceptance actually claims — a cone's own pixels land at
/// the position its own angle and direction predict — is a fact about the
/// gizmo's own vertex data, checked against the closed-form geometry of a
/// cone, independently of whatever the rasteriser then does with it (which is
/// `view-05`'s own already-tested job, not this row's to redo).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/lighting_sync.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The line whose own start vertex sits at [origin] — the direction arrow for
/// a light with no cone, or one candidate among several for a spot light
/// (the direction line and its four cone ribs all start at the light's own
/// position; [addLightGizmo] draws the direction line immediately after the
/// marker sphere and before any cone rib, so it is always the first such line
/// found).
Vector3 _firstLineFrom(DebugDraw draw, Vector3 origin) {
  final floats = draw.vertexBytes.buffer.asFloat32List(
    draw.vertexBytes.offsetInBytes,
    draw.vertexCount * DebugDraw.floatsPerVertex,
  );
  for (var v = 0; v + 1 < draw.vertexCount; v += 2) {
    final o = v * DebugDraw.floatsPerVertex;
    final from = Vector3(floats[o], floats[o + 1], floats[o + 2]);
    if ((from - origin).length2 < 1e-10) {
      final b = o + DebugDraw.floatsPerVertex;
      return Vector3(floats[b], floats[b + 1], floats[b + 2]);
    }
  }
  fail('no gizmo line starts at the light\'s own origin');
}

/// Every line whose own start vertex sits at [origin], as (from, to) pairs —
/// for a spot light, the direction line plus the four cone ribs.
List<(Vector3, Vector3)> _linesFrom(DebugDraw draw, Vector3 origin) {
  final floats = draw.vertexBytes.buffer.asFloat32List(
    draw.vertexBytes.offsetInBytes,
    draw.vertexCount * DebugDraw.floatsPerVertex,
  );
  final result = <(Vector3, Vector3)>[];
  for (var v = 0; v + 1 < draw.vertexCount; v += 2) {
    final o = v * DebugDraw.floatsPerVertex;
    final lineFrom = Vector3(floats[o], floats[o + 1], floats[o + 2]);
    if ((lineFrom - origin).length2 < 1e-10) {
      final b = o + DebugDraw.floatsPerVertex;
      result.add((lineFrom, Vector3(floats[b], floats[b + 1], floats[b + 2])));
    }
  }
  return result;
}

void main() {
  group('mat-25: light gizmos', () {
    test('rotating the light node moves the arrow gizmo', () {
      final light = LightNode(type: LightType.directional)
        ..setLocalForward(Vector3(0.0, -1.0, 0.0));

      final before = DebugDraw()..addLightGizmo(light, size: 1.0);
      final origin = light.readWorldPosition();
      final tipBefore = _firstLineFrom(before, origin);

      // A quarter turn: -Y becomes +X. If the gizmo were a stale snapshot
      // from when it was built rather than something that reads the node's
      // live transform, this would not move it at all.
      light.setLocalForward(Vector3(1.0, 0.0, 0.0));
      final after = DebugDraw()..addLightGizmo(light, size: 1.0);
      final tipAfter = _firstLineFrom(after, origin);

      expect((tipBefore - tipAfter).length, greaterThan(0.5));

      // Not just "it moved" — moved to exactly where the new direction
      // predicts: `size * 4.0` along the node's own new -Z-mapped forward.
      final expectedDirection = light.readDirection()..scale(1.0 * 4.0);
      final expectedTip = origin + expectedDirection;
      expect((tipAfter - expectedTip).length, lessThan(1e-4));
    });

    test("mat-25's own acceptance: a spot's cone pixels are where its angle "
        'and direction put them', () {
      final light = LightNode(
        type: LightType.spot,
        outerConeAngle: math.pi / 6.0, // 30°
      )..setLocalForward(Vector3(0.0, 0.0, -1.0));

      const size = 0.4;
      final draw = DebugDraw()..addLightGizmo(light, size: size);
      final origin = light.readWorldPosition();
      final ribs = _linesFrom(draw, origin);

      // The direction line plus four cone ribs, all starting at the light.
      expect(ribs, hasLength(5));

      final direction = light.readDirection();
      final tip = origin + (direction * (size * 4.0));
      final coneLength = (tip - origin).length;
      final expectedRadius = coneLength * math.tan(light.outerConeAngle);

      // Every rib but the direction line itself lands on the circle the
      // cone angle predicts, `expectedRadius` from the axis at the tip —
      // not merely "a cone-shaped blob somewhere near the light".
      var ribsOnCircle = 0;
      for (final (_, to) in ribs) {
        if ((to - tip).length < 1e-6) continue; // the direction line itself
        final offset = to - tip;
        expect(offset.dot(direction).abs(), lessThan(1e-4));
        expect((offset.length - expectedRadius).abs(), lessThan(1e-4));
        ribsOnCircle++;
      }
      expect(ribsOnCircle, 4);
    });

    test('end to end: LightingSync.apply turns the gizmo on, and the rendered '
        'frame changes because of it', () async {
      final it = cpuTestDevice(width: 96, height: 72);
      final renderer = Renderer.create(device: it.device);
      final stage = ModelerStage.build(device: it.device);
      stage.frameSubject();

      final sync = LightingSync();
      const noLights = SceneLighting();
      final withSpot = SceneLighting(
        lights: <ProjectLight>[
          ProjectLight(type: ProjectLightType.spot, range: 5.0, intensity: 6.0),
        ],
      );

      Future<Uint8List> frameFor(SceneLighting lighting) async {
        sync.sync(stage.scene, lighting);
        final settings = sync.apply(const RenderSettings(), lighting);
        final result = renderer.render(
          width: 96,
          height: 72,
          scene: stage.scene,
          views: stage.views(),
          settings: settings,
        );
        final pixels = await it.device.readPixels(result.frame);
        expect(pixels, isNotNull);
        return pixels!.buffer.asUint8List();
      }

      final without = await frameFor(noLights);
      final with_ = await frameFor(withSpot);

      expect(
        without,
        isNot(equals(with_)),
        reason:
            'adding a light and syncing should turn DebugDrawOptions'
            '.lightGizmos on (LightingSync.apply) and draw something new',
      );
    });
  });
}
