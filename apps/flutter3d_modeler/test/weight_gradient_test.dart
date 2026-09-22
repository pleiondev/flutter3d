/// `weight_gradient.dart`'s own arithmetic — the colour stops, the per-vertex
/// weight read, the partial overwrite and the material/settings pair — apart
/// from the picture it draws, which is `weight_gradient_frame_test.dart`'s
/// own row.
///
///     flutter test test/weight_gradient_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/weight_gradient.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The same IEC 61966-2-1 curve `weight_gradient.dart` applies, worked out
/// independently here so a test of it is not the same formula checked
/// against itself.
double _linearChannel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

Vector3 _linearOf(int hex) => Vector3(
  _linearChannel(((hex >> 16) & 0xFF) / 255.0),
  _linearChannel(((hex >> 8) & 0xFF) / 255.0),
  _linearChannel((hex & 0xFF) / 255.0),
);

void _expectClose(Vector4 actual, Vector3 expected, {double eps = 1e-6}) {
  expect(actual.x, closeTo(expected.x, eps));
  expect(actual.y, closeTo(expected.y, eps));
  expect(actual.z, closeTo(expected.z, eps));
  expect(actual.w, 1.0);
}

void main() {
  group('weightGradientColor', () {
    test('no weight is the first stop, converted to linear', () {
      _expectClose(weightGradientColor(0.0), _linearOf(0x2A3A7A));
    });

    test('full weight is the last stop, converted to linear', () {
      _expectClose(weightGradientColor(1.0), _linearOf(0xFF3B5C));
    });

    // Mutation: write the sRGB byte straight into the channel with no
    // decode, and this comes back reading the sRGB fraction instead of the
    // linear one — `weight_gradient.dart`'s own doc comment's whole warning.
    test('full weight is not the sRGB fraction, only the linear one', () {
      final c = weightGradientColor(1.0);
      expect(c.y, isNot(closeTo(0x3B / 255.0, 0.01)));
    });

    for (final stop in <(double, int)>[
      (0.25, 0x4AA3FF),
      (0.50, 0x7EE081),
      (0.75, 0xFFB347),
    ]) {
      test('${stop.$1} lands exactly on its own named stop', () {
        _expectClose(weightGradientColor(stop.$1), _linearOf(stop.$2));
      });
    }

    test('interpolates between two stops rather than snapping to one', () {
      // Halfway between the first two stops, in sRGB — the space the legend's
      // own `LinearGradient` interpolates in — and only then converted, which
      // is `weightGradientColor`'s own documented order.
      final a = <int>[0x2A, 0x3A, 0x7A];
      final b = <int>[0x4A, 0xA3, 0xFF];
      final midSrgb = Vector3(
        (a[0] + b[0]) / 2 / 255.0,
        (a[1] + b[1]) / 2 / 255.0,
        (a[2] + b[2]) / 2 / 255.0,
      );
      _expectClose(
        weightGradientColor(0.125),
        Vector3(
          _linearChannel(midSrgb.x),
          _linearChannel(midSrgb.y),
          _linearChannel(midSrgb.z),
        ),
        eps: 1e-6,
      );
    });

    test('clamps a weight below zero to the zero-weight stop', () {
      final low = weightGradientColor(-4.0);
      final zero = weightGradientColor(0.0);
      expect(low.x, zero.x);
      expect(low.y, zero.y);
      expect(low.z, zero.z);
    });

    test('clamps a weight above one to the full-weight stop', () {
      final high = weightGradientColor(4.0);
      final full = weightGradientColor(1.0);
      expect(high.x, full.x);
      expect(high.y, full.y);
      expect(high.z, full.z);
    });
  });

  group('vertexWeightsForJoint', () {
    test(
      'a freshly assigned vertex reads its own weight for the right joint',
      () {
        // `assignSelection`, not `paintWeight`: `paintWeight` accumulates
        // onto whatever a vertex already has, and a vertex nobody has ever
        // skinned already reads as joint zero at full weight — its own
        // documented default — so painting joint 2 on top would renormalise
        // to 0.5/0.5 rather than land the clean 1.0 this test wants.
        // `assignSelection` replaces the whole list instead.
        final mesh = EditMesh.cuboid();
        mesh.beginStep();
        assignSelection(mesh, <int>[0], 2, 1.0);
        mesh.endStep();

        final weights = vertexWeightsForJoint(mesh, 2);

        expect(weights.length, mesh.vertexSlotCount);
        expect(weights[0], closeTo(1.0, 1e-6));
        for (var v = 1; v < mesh.vertexSlotCount; v++) {
          expect(weights[v], 0.0, reason: 'vertex $v was never painted');
        }
      },
    );

    test('reads zero for a joint a vertex has no influence from', () {
      final mesh = EditMesh.cuboid();
      mesh.beginStep();
      assignSelection(mesh, <int>[0], 2, 1.0);
      mesh.endStep();
      expect(vertexWeightsForJoint(mesh, 5)[0], 0.0);
    });

    test('sums weight across every stored slot naming the same joint', () {
      // Built directly through `setSkin` rather than `assignSelection` or
      // `paintWeight`, neither of which can put the same joint in two of the
      // four raw slots at once — this is the one way to exercise the summing
      // branch rather than a single read.
      final mesh = EditMesh.cuboid();
      mesh.beginStep();
      mesh.setSkin(
        0,
        VertexAttributes(
          joints: Vector4(1, 1, 3, 0),
          weights: Vector4(0.3, 0.2, 0.5, 0.0),
        ),
      );
      mesh.endStep();
      expect(vertexWeightsForJoint(mesh, 1)[0], closeTo(0.5, 1e-6));
      expect(vertexWeightsForJoint(mesh, 3)[0], closeTo(0.5, 1e-6));
    });
  });

  group('paintWeightGradient', () {
    late FakeBackend device;
    late EditMesh mesh;
    late MeshLayoutPlan plan;
    late DeviceMesh deviceMesh;

    setUp(() {
      device = FakeBackend();
      mesh = EditMesh.cuboid();
      plan = MeshLayoutPlan()..build(mesh);
      deviceMesh = DeviceMesh.upload(device, mesh.toMeshData());
    });

    test('overwrites the whole mesh in one call', () {
      paintWeightGradient(
        device: device,
        mesh: deviceMesh,
        plan: plan,
        vertexWeights: List<double>.filled(mesh.vertexSlotCount, 1.0),
      );

      expect(device.overwrites, hasLength(1));
      expect(device.overwrites.single.offsetInBytes, 0);
      expect(
        device.overwrites.single.lengthInBytes,
        deviceMesh.vertices.lengthInBytes,
      );
    });

    test('bumps the mesh version once', () {
      expect(deviceMesh.version, 0);
      paintWeightGradient(
        device: device,
        mesh: deviceMesh,
        plan: plan,
        vertexWeights: List<double>.filled(mesh.vertexSlotCount, 0.0),
      );
      expect(deviceMesh.version, 1);
    });

    test('refuses a mesh uploaded with no source data', () {
      final noSource = DeviceMesh.upload(
        device,
        mesh.toMeshData(),
        keepSourceData: false,
      );
      expect(
        () => paintWeightGradient(
          device: device,
          mesh: noSource,
          plan: plan,
          vertexWeights: List<double>.filled(mesh.vertexSlotCount, 0.0),
        ),
        throwsStateError,
      );
      expect(device.overwrites, isEmpty);
    });

    test('refuses a plan built against a differently-shaped mesh', () {
      final other = EditMesh.cuboid().extrudeFace(0, 0.5);
      final otherPlan = MeshLayoutPlan()..build(other);
      expect(
        () => paintWeightGradient(
          device: device,
          mesh: deviceMesh,
          plan: otherPlan,
          vertexWeights: List<double>.filled(mesh.vertexSlotCount, 0.0),
        ),
        throwsArgumentError,
      );
      expect(device.overwrites, isEmpty);
    });
  });

  group('weightGradientSettings', () {
    test('turns tone mapping off and pins exposure to neutral, keeping the '
        'rest', () {
      const over = RenderSettings(specular: 0.4, wireframe: true);
      final settings = weightGradientSettings(over);
      expect(settings.tonemap, isFalse);
      expect(settings.exposure, 1.0);
      expect(settings.specular, 0.4);
      expect(settings.wireframe, isTrue);
    });
  });

  group('WeightGradientShading', () {
    test('swaps every mesh under the subject in and restores it on the way '
        'out', () {
      final device = FakeBackend();
      final deviceMesh = DeviceMesh.upload(
        device,
        EditMesh.cuboid().toMeshData(),
      );
      final own = Material(name: 'clay');
      final root = SceneNode(name: 'root');
      final node = MeshNode(deviceMesh, own, name: 'leg');
      root.add(node);

      final shading = WeightGradientShading();

      shading.apply(root, active: true);
      expect(node.material, same(kWeightGradientMaterial));

      shading.apply(root, active: false);
      expect(node.material, same(own));
    });

    test('forget makes the next active swap remember whatever is on the '
        'node now', () {
      final device = FakeBackend();
      final deviceMesh = DeviceMesh.upload(
        device,
        EditMesh.cuboid().toMeshData(),
      );
      final first = Material(name: 'first');
      final second = Material(name: 'second');
      final root = SceneNode(name: 'root');
      final node = MeshNode(deviceMesh, first, name: 'leg');
      root.add(node);

      final shading = WeightGradientShading()
        ..apply(root, active: true)
        ..apply(root, active: false); // back to `first`, remembered.

      node.material = second;
      shading.forget();
      shading.apply(root, active: true);
      shading.apply(root, active: false);

      expect(node.material, same(second));
    });

    test('a material painted on while it is off is not painted back over', () {
      final device = FakeBackend();
      final deviceMesh = DeviceMesh.upload(
        device,
        EditMesh.cuboid().toMeshData(),
      );
      final clay = Material(name: 'clay');
      final root = SceneNode(name: 'root');
      final node = MeshNode(deviceMesh, clay, name: 'leg');
      root.add(node);

      // Every frame of an ordinary session: this is walked whether or not the
      // weights sub-mode is open, and it is off.
      final shading = WeightGradientShading()..apply(root, active: false);

      // Then an edit lands — `SceneSync` writes the rebuilt material onto the
      // node after a colour changes in the panel or over MCP.
      final Material edited = Material(name: 'edited');
      node.material = edited;
      shading.apply(root, active: false);

      // Mutation: record what a node was drawn with the first time it is seen
      // and write that back on every frame — which is what this did. The
      // model then keeps the colour it had when the window opened however the
      // document changes, and the panel's own swatch disagrees with the
      // viewport for the rest of the session.
      expect(node.material, same(edited));
    });

    test('and an edit during a weights session survives the way out', () {
      final device = FakeBackend();
      final deviceMesh = DeviceMesh.upload(
        device,
        EditMesh.cuboid().toMeshData(),
      );
      final root = SceneNode(name: 'root');
      final node = MeshNode(deviceMesh, Material(name: 'clay'), name: 'leg');
      root.add(node);

      final shading = WeightGradientShading()..apply(root, active: true);
      final Material edited = Material(name: 'edited');
      node.material = edited;
      shading.apply(root, active: true);
      expect(node.material, same(kWeightGradientMaterial));

      shading.apply(root, active: false);
      expect(node.material, same(edited));
    });
  });
}
