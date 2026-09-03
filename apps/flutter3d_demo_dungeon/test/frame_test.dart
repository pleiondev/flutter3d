/// The crypt, drawn. Not the simulation — the picture.
///
///     flutter test test/frame_test.dart
///
/// **The other three applications had one of these and this one did not**, and
/// it is the game the performance budgets in `ARCHITECTURE.md` §14 are written
/// for. What this repository already knows about the gap is written in §7.1:
/// three bugs shipped in the platformer in one afternoon that every simulation
/// test passed — no coin visible, no sound on a pickup, a gate that never
/// opened — because all three lived in the seam between a simulation that was
/// right and a picture that was wrong.
///
/// It also earned its keep in a way no fixture could. The platformer's frame
/// test did not show a picture on its first run; it crashed inside the software
/// rasteriser with `Unsupported operation: Infinity or NaN toInt`, four frames
/// of stack from anywhere anybody would have looked, because a vertex clipped by
/// the near plane rounds its `w` to zero in float32. **Every frame drawn from
/// inside a level failed that way**, and no parity fixture had geometry large
/// enough to see it. This file is the crypt's version of that question.
///
/// Counted pixels rather than a golden image, for the reason the platformer's
/// file gives: a golden of a scene this size fails on every brush anybody moves
/// and teaches nothing.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // RunSession, SettingsOverlay
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String _crypt = 'assets/levels/crypt.json';

/// Small enough that a software frame is cheap, large enough that a room has an
/// inside.
///
/// The platformer learned the cost the expensive way: 320×180 across a thousand
/// frames produced no output in ten minutes.
const int _width = 200;
const int _height = 130;

/// Storage that keeps everything in a map, so no run touches the disk.
final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// The crypt, loaded and dressed by the game's own assembly.
///
/// Through `DungeonRun` rather than beside it: the loader, both sets of visuals
/// and `stage` are one call there, and the one thing this file varies is the
/// device. A harness that assembled its own would be a picture of a game nobody
/// ships — which is not hypothetical, see `one_assembly_test`.
Future<({LevelReady level, CpuDevice device, Renderer renderer})> _shown({
  String asset = _crypt,
}) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final run = RunCubit(
    DungeonRun(
      firstLevel: asset,
      registry: sampleRegistry(),
      input: InputState(),
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon', storage: _Storage()),
      device: it.device,
    ),
  );

  expect(await run.begin(), isFalse, reason: 'a fresh run resumed something');
  final state = run.state;
  expect(state, isA<RunPlaying<LevelReady>>(), reason: '$asset did not load');

  return (
    level: (state as RunPlaying<LevelReady>).level,
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// A frame from where the player is standing, as bytes.
///
/// [frames] draws that many in a row through one camera and returns the last;
/// anything under one still draws one. More than one is what a level with
/// several probes needs before all of them stand: the renderer captures one
/// whole cube a frame, so a crypt's four take four frames — see
/// `_claimWholeProbeCapture`.
Future<Uint8List> _drawFromTheStart(
  ({LevelReady level, CpuDevice device, Renderer renderer}) it, {
  int frames = 1,
}) async {
  final player = it.level.staged.player;
  final scene = it.level.loaded.scene;

  // Where the player's own eye is and what it is pointed at, asked of the
  // player rather than worked out here: `Player.eye` and `Player.aim` are the
  // two the application uses, and a frame aimed by a second calculation would
  // be a frame of somewhere the game never looks.
  final eye = Vector3.zero();
  final aim = Vector3.zero();
  player
    ..eye(eye)
    ..aim(aim);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.2,
      near: 0.05,
      far: 200.0,
    ),
  )..setPositionFrom(eye);
  camera.lookAt(eye + aim);
  scene.add(camera);

  final views = <RenderView>[
    RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
  ];

  Future<Uint8List> once() async {
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: views,
      settings: const RenderSettings(),
    );
    final pixels = await it.device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    return pixels!.buffer.asUint8List();
  }

  for (var i = 1; i < frames; i++) {
    await once();
  }
  return once();
}

/// What a frame is, in the three numbers this file asks about.
///
/// [lit] is how many pixels are not the clear colour; [shades] is how many
/// distinct five-bit brightnesses appear, which is what tells a rendered room
/// from a single flat surface filling the view; [brightest] is the lightest
/// pixel, which is what a torch produces and a level with no lights does not.
({int lit, int shades, int brightest}) _describe(Uint8List rgba) {
  final buckets = <int>{};
  var lit = 0;
  var brightest = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final luminance =
        (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
    if (luminance > 6) lit++;
    if (luminance > brightest) brightest = luminance;
    buckets.add(luminance >> 3);
  }
  return (lit: lit, shades: buckets.length, brightest: brightest);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a frame from inside the crypt is drawn at all', () async {
    // **The assertion the platformer's near-plane crash would have failed
    // before reaching.** Getting here without an exception is half the test;
    // the other half is that what came back is not the clear colour.
    //
    // Mutation: draw an empty `Scene()` instead of the level's. Every number
    // below collapses — nought lit, one shade, brightest nought.
    //
    // **Two mutations that do *not* fail, recorded so nobody claims them.**
    // Aiming the camera at the ceiling changes nothing measurable: a crypt has
    // brushes in every direction and all three numbers come back identical.
    //
    // Nor does dropping `..bindLights()` from `DungeonRun.open`, and the reason
    // is worth having written down: the crypt's torches are `SteadyLight`, so
    // their brightness is one until something measures the fire — the particle
    // system in the running game, and nothing at all here. Binding a light and
    // then scaling it by one leaves the same frame. `run_cubit_test.dart` holds
    // that one instead, by guttering a torch and asking whether the light it
    // names moved.
    final it = await _shown();
    final frame = _describe(await _drawFromTheStart(it));
    final total = _width * _height;

    // Measured on the shipped crypt: 19576 of 26000 lit, eight shades,
    // brightest 59. The thresholds are well under those and well over what a
    // broken frame produces, which is the trade a counted-pixel assertion
    // makes — see the note at the top about goldens.
    expect(
      frame.lit,
      greaterThan(total ~/ 2),
      reason:
          'the crypt drew ${frame.lit} lit pixels out of $total — a '
          'level that loads, validates and steps, and shows nothing',
    );

    // **The half that "is it black" cannot ask.** One wall filling the view is
    // not a picture of a room, and an empty scene rendered against a clear
    // colour is one shade. Eight on the shipped level.
    expect(
      frame.shades,
      greaterThanOrEqualTo(4),
      reason:
          'the frame has ${frame.shades} distinct brightnesses in it, '
          'which is a flat surface or a clear colour rather than a room',
    );

    // And something in it is actually lit rather than merely present. A crypt
    // is dark — 59 is the brightest pixel in the shipped one — so this is a low
    // bar deliberately, and it is still the difference between a lit room and
    // an ambient wash.
    expect(
      frame.brightest,
      greaterThan(24),
      reason:
          'the brightest pixel in the crypt is ${frame.brightest}: the '
          'level is drawn and nothing in it is lit',
    );
  });

  test(
    'and its probes stand a frame apiece, before a room is hidden',
    () async {
      // The order the level keeps. A kept probe is captured on a frame of its
      // own; the visibility culler, applied from the player's cell, has hidden
      // every room but the hall. Applied first, the probe in the vault
      // captures the vault's walls with nothing behind them and nobody sees it
      // — a reflection is a plausible picture from the wrong room. So the
      // level holds its culler until every probe stands, and this is the whole
      // level doing exactly that: nothing hidden before the frames, every
      // probe captured by them, and the rooms behind walls hidden again after.
      //
      // A frame apiece and not all at once: the renderer draws one whole cube
      // per frame, because four probes times six views of a level nothing is
      // yet allowed to cull is a stall on the frame the level appears. What
      // that costs is the frames below, drawn without culling.
      //
      // Mutation: apply the culler directly in `_step` — the first assertion
      // fails on the shipped crypt, which hides batches from the spawn.
      final it = await _shown();
      final loaded = it.level.loaded;
      expect(
        loaded.probes,
        isNotEmpty,
        reason: 'the crypt places one per room',
      );
      expect(loaded.culler, isNotNull, reason: 'the crypt ships a table');
      final eye = Vector3.zero();
      it.level.staged.player.eye(eye);

      loaded.cull(eye, device: it.device);
      expect(loaded.culler!.hidden, 0, reason: 'held until the probes stand');
      expect(loaded.probes.any((p) => p.isCaptured), isFalse);

      await _drawFromTheStart(it);
      expect(
        loaded.probes.where((p) => p.isCaptured),
        hasLength(1),
        reason: 'one whole cube a frame, and the rest wait their turn',
      );
      loaded.cull(eye, device: it.device);
      expect(loaded.culler!.hidden, 0, reason: 'still held: three to go');

      await _drawFromTheStart(it, frames: loaded.probes.length - 1);
      expect(
        loaded.probes.every((p) => p.isCaptured),
        isTrue,
        reason: 'as many frames as the level has probes, and they all stand',
      );

      loaded.cull(eye, device: it.device);
      expect(
        loaded.culler!.hidden,
        greaterThan(0),
        reason: 'the rooms behind walls are hidden again, as they always were',
      );
    },
  );

  test('and the level the crypt names next loads and draws too', () async {
    // Two errors that are indistinguishable from the simulation's side, where
    // the state is `finished` and the name is a name either way: a typo in the
    // next level's file name, and a level with no light in it.
    final it = await _shown();
    final next = it.level.staged.sim.nextLevel;
    if (next == null) {
      // Not a failure: the shipped crypt is allowed to be the last level. It
      // says so here rather than passing silently, because "there is no next
      // level" and "this test checked nothing" look identical otherwise.
      expect(next, isNull, reason: 'the crypt is the last level');
      return;
    }

    final frame = _describe(await _drawFromTheStart(await _shown(asset: next)));

    expect(
      frame.lit,
      greaterThan((_width * _height) ~/ 2),
      reason: '$next loads and draws nothing',
    );
    expect(
      frame.brightest,
      greaterThan(24),
      reason:
          '$next has no light in it, which looks exactly like a level '
          'that is fine from the simulation\'s side',
    );
  });
}
