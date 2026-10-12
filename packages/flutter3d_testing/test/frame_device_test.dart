/// A frame and a replay drawn on a device the test chose, not only on the
/// software rasteriser.
///
///     flutter test test/frame_device_test.dart
///
/// **A recording fake stands in for the other backends.** What is under test
/// is the wiring: that `device:` is the device the frame is drawn on, that
/// it is opened at the frame's size, that a frame's device is let go once
/// its pixels are read, and that a replay opens one for its whole run. The
/// pixels a GPU backend draws are that backend's own suite's business.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens [FakeBackend]s, and remembers each with the size it was asked for.
final class _Opener {
  final List<({FakeBackend device, int width, int height})> opened =
      <({FakeBackend device, int width, int height})>[];

  Future<GraphicsDevice> call({required int width, required int height}) async {
    final device = FakeBackend();
    opened.add((device: device, width: width, height: height));
    return device;
  }
}

FrameSubject _empty(GraphicsDevice device) {
  final scene = Scene();
  final camera = CameraNode()..lookAt(Vector3(0.0, 0.0, -1.0));
  scene.add(camera);
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
      RenderMaterial(name: 'box'),
    )..setPosition(0.0, 0.0, -4.0),
  );
  return FrameSubject(scene: scene, camera: camera);
}

/// Stands still: a genre with nothing in its run but a step count.
final class _Still extends GenrePlugin<List<int>> {
  @override
  PluginManifest get manifest => PluginManifest(
    id: 'test.still',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
  );

  @override
  String get systemName => 'still.step';

  @override
  void stepSimulation(GenreStepContext<List<int>> step) {
    final simulation = step.simulation;
    simulation[0]++;
  }

  @override
  Snapshot captureSimulation(List<int> simulation) =>
      Snapshot(<String, Object?>{'steps': simulation[0]});

  @override
  void restoreSimulation(GenreRestoreContext<List<int>> restore) {
    final simulation = restore.simulation;
    final state = restore.state;
    simulation[0] = state.data.integer('steps');
  }
}

final class _Subject extends ReplaySubject {
  _Subject(this.start) {
    genre.simulation = <int>[0];
    loop = EngineLoop(input: start.input, plugins: <Flutter3dPlugin>[genre]);
  }

  final ReplayStart start;

  @override
  final _Still genre = _Still();

  @override
  late final EngineLoop loop;

  @override
  FrameSubject frame(int step) => _empty(start.device);
}

Demo _tape() {
  final recorder = InputTapeRecorder(seed: 1);
  final input = InputState();
  for (var i = 0; i < 4; i++) {
    recorder.record(input);
  }
  return Demo(
    level: 'still.json',
    levelHash: 'c0ffee00',
    start: Snapshot(<String, Object?>{'steps': 0}),
    tape: recorder.tape,
    buildStamp: 'test-build',
    checkpoints: DigestTrace(every: 5),
  );
}

void main() {
  group('renderFrame(device:)', () {
    test('draws on the device it opens, at the frame\'s size, and lets it '
        'go once the pixels are read', () async {
      // Mutation: ignore `device` and open the software rasteriser, and the
      // fake opens nothing and records no pass; leave out the dispose, and
      // the fake is still alive after the frame.
      final open = _Opener();
      final frame = await renderFrame(
        width: 24,
        height: 16,
        device: open.call,
        build: (request) => _empty(request.device),
      );
      final it = open.opened.single;
      expect((it.width, it.height), (24, 16));
      expect(it.device.passes, isNotEmpty, reason: 'the frame was drawn on it');
      expect(it.device.readbacks, hasLength(1));
      expect(it.device.isDisposed, isTrue);
      expect(frame.pixels, hasLength(24 * 16 * 4));
      expect((frame.width, frame.height), (24, 16));
    });

    test('hands the builder the device it opened', () async {
      // Mutation: hand the builder a software device of its own, and the
      // meshes are uploaded to a device the frame is not drawn on.
      final open = _Opener();
      GraphicsDevice? seen;
      await renderFrame(
        width: 8,
        height: 8,
        device: open.call,
        build: (request) => _empty(seen = request.device),
      );
      expect(seen, same(open.opened.single.device));
    });
  });

  test('drawOnce draws a subject through a renderer the caller holds, on '
      'the device the caller holds', () async {
    // Mutation: read back a texture other than the frame's, and the fake
    // records a readback of something no pass wrote.
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final frame = await drawOnce(
      device: device,
      renderer: renderer,
      subject: _empty(device),
      width: 12,
      height: 10,
    );
    expect(frame.drawCalls, greaterThan(0));
    expect(device.readbacks.single.region.width, 12);
    expect(frame.pixels, hasLength(12 * 10 * 4));
  });

  test('expectReplayMatches(device:) opens one device for the run and draws '
      'every golden on it', () async {
    // Mutation: open the software rasteriser regardless, and the fake opens
    // nothing; open a device per golden, and two are opened.
    final dir = Directory.systemTemp.createTempSync('frame_device_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final open = _Opener();
    GraphicsDevice? started;
    await expectReplayMatches(
      _tape(),
      start: (start) {
        started = start.device;
        return _Subject(start);
      },
      device: open.call,
      digestAt: const <int>[],
      goldensAt: const <int>[2, 4],
      goldenDirectory: dir.path,
      width: 16,
      height: 12,
      recordMissing: true,
    );
    final it = open.opened.single;
    expect(started, same(it.device));
    expect((it.width, it.height), (16, 12));
    expect(it.device.readbacks, hasLength(2));
    expect(it.device.isDisposed, isTrue);
  });
}
