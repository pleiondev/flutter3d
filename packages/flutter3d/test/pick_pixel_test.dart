/// Picking by pixel: the pass the renderer builds on a frame something asked,
/// and nothing on the frames nothing did.
///
///     flutter test test/pick_pixel_test.dart
///
/// Against the fake device, which draws nothing and records everything, so the
/// questions here are about what the pass *is*: which target, cleared to
/// what, which id each draw was handed, and which pixel was read back. That a
/// real backend answers with the right node is
/// `flutter3d_cpu/test/pick_pixel_test.dart`.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/box_shapes.dart';
import 'package:flutter3d/src/engine/geometry/mesh_geometry.dart';
import 'package:flutter3d/src/engine/render/frame_graph.dart';
import 'package:flutter3d/src/engine/render/frame_plan.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_node.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 64;
const int _height = 48;

/// An application node that fails. Registered in the overlay phase, it runs
/// after the id pass, so the frame goes down with a question the device has
/// already been handed.
final class _FailingNode extends RenderNode {
  const _FailingNode();

  @override
  String get name => 'failing overlay';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  void execute(NodeFrame frame) => throw StateError('the overlay went wrong');
}

/// One pixel's worth of bytes carrying [id].
ByteData _pixelWith(int id) {
  final bytes = Uint8List(4);
  bytes[0] = id & 0xFF;
  bytes[1] = (id >> 8) & 0xFF;
  bytes[2] = (id >> 16) & 0xFF;
  bytes[3] = 255;
  return ByteData.sublistView(bytes);
}

void main() {
  late FakeBackend device;
  late Renderer renderer;
  late Scene scene;
  late RenderView view;
  late MeshNode left;
  late MeshNode right;

  setUp(() {
    device = FakeBackend();
    renderer = Renderer.create(device: device);
    left = MeshNode(
      DeviceMesh.upload(device, CuboidShape().build()),
      Material(),
      name: 'left',
    )..setPosition(-1.5, 0.0, -5.0);
    right = MeshNode(
      DeviceMesh.upload(device, CuboidShape().build()),
      Material(),
      name: 'right',
    )..setPosition(1.5, 0.0, -5.0);
    scene = Scene()
      ..add(left)
      ..add(right)
      ..add(CameraNode());
    view = RenderView(camera: scene.cameras.single);
  });

  void frame() => renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[view],
  );

  /// The pass drawing ids: the only one with a frame-sized eight-bit colour
  /// attachment and a depth attachment beside it.
  Iterable<FakePass> idPasses() => device.passes.where(
    (FakePass pass) =>
        pass.descriptor.colors.length == 1 &&
        pass.descriptor.depth != null &&
        pass.color.texture.format == TextureFormat.r8g8b8a8UNormInt &&
        pass.color.texture.width == _width,
  );

  test('costs nothing on a frame nobody asked', () {
    // Mutation: make the node active always — every frame draws the scene
    // twice and reads nothing back.
    frame();
    expect(idPasses(), isEmpty);
    expect(device.readbacks, isEmpty);
  });

  test('draws every mesh as its own number and reads one pixel back', () async {
    final asked = renderer.pickPixel(0.75, 0.5);
    frame();

    final pass = idPasses().single;
    expect(pass.submitted, isTrue);
    expect(pass.color.clearValue?.storage, <double>[
      0.0,
      0.0,
      0.0,
      0.0,
    ], reason: 'zero is the id nothing has');
    expect(
      pass.descriptor.depth!.texture.storageMode,
      StorageMode.deviceTransient,
    );
    expect(
      pass.recordedOf<RecordedBlend>().map((RecordedBlend b) => b.state),
      everyElement(isNull),
      reason: 'an id is not a colour and half of one is nothing',
    );

    // One IdInfo block per draw, numbered from one in draw order. Mutation:
    // start the ids at zero — the first mesh becomes indistinguishable from
    // the clear.
    final ids = pass
        .recordedOf<RecordedUniformBlock>()
        .where((RecordedUniformBlock b) => b.block == 'IdInfo')
        .map((RecordedUniformBlock b) => b.members['id']!)
        .toList();
    expect(ids, hasLength(2));
    expect(ids[0][0], closeTo(1 / 255, 1e-6));
    expect(ids[1][0], closeTo(2 / 255, 1e-6));
    expect(ids[0][1], 0.0);
    expect(ids[0][3], 1.0);
    expect(pass.drawCount, 2);

    // The pixel three quarters across and half way down, and only that.
    // Mutation: read the whole target — a frame of bytes per click.
    final readback = device.readbacks.single;
    expect(identical(readback.texture, pass.color.texture), isTrue);
    expect(
      readback.region,
      const ScreenRect(
        x: _width * 3 ~/ 4,
        y: _height ~/ 2,
        width: 1,
        height: 1,
      ),
    );

    // The fake answers zeros, which is the clear: nothing there.
    expect(await asked, isNull);
  });

  test('maps the number that comes back to the node that was drawn', () async {
    // Mutation: index the list by the id rather than by the id less one — the
    // second draw's number names the first.
    device.answerReadback = (_, _) => _pixelWith(2);
    final asked = renderer.pickPixel(0.5, 0.5);
    frame();
    expect(identical(await asked, right), isTrue);

    device.answerReadback = (_, _) => _pixelWith(1);
    final again = renderer.pickPixel(0.5, 0.5);
    frame();
    expect(identical(await again, left), isTrue);
  });

  test('answers nothing for a number no draw had', () async {
    // A stale texture, a driver that wrote garbage: a number past the list is
    // not a node, and guessing one would be worse than none.
    device.answerReadback = (_, _) => _pixelWith(7);
    final asked = renderer.pickPixel(0.5, 0.5);
    frame();
    expect(await asked, isNull);
  });

  test('clamps a point outside the frame to its edge', () async {
    renderer.pickPixel(1.5, -0.5).ignore();
    frame();
    expect(
      device.readbacks.single.region,
      const ScreenRect(x: _width - 1, y: 0, width: 1, height: 1),
    );
  });

  test('answers several questions from one pass', () async {
    renderer.pickPixel(0.1, 0.1).ignore();
    renderer.pickPixel(0.9, 0.9).ignore();
    frame();
    expect(idPasses(), hasLength(1));
    expect(device.readbacks, hasLength(2));
  });

  test(
    'a question asked of a renderer that is disposed is answered null',
    () async {
      final asked = renderer.pickPixel(0.5, 0.5);
      renderer.dispose();
      expect(await asked, isNull);
    },
  );

  test(
    'a question whose frame fails is answered with the failure, once',
    () async {
      // The id pass has run and handed its readback to the device by the time
      // the overlay throws, so the question is answered twice over: by the
      // frame's catch, with the failure, and a microtask later by the device,
      // with a pixel. Mutation: drop the `isCompleted` check in the pick pass —
      // the second answer throws "Future already completed" from inside a
      // `then`, which is an unhandled error nobody's `await` sees.
      renderer.addNode(const _FailingNode());
      final asked = renderer.pickPixel(0.5, 0.5);
      expect(frame, throwsStateError);
      expect(device.readbacks, hasLength(1), reason: 'the id pass had run');
      await expectLater(asked, throwsStateError);
      // The device's answer, arriving at a completer already finished.
      await pumpEventQueue();
    },
  );
}
