/// A game filmed frame by frame: each frame a numbered PNG in its shot's
/// folder, at the reel's size, drawn in one tile unless asked otherwise.
///
///     flutter test test/reel_test.dart
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game_ui/capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

({Renderer renderer, Scene scene, CameraNode camera}) _game() {
  final device = CpuDevice(
    width: 32,
    height: 24,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode(name: 'eye')..setPosition(0.0, 0.0, 3.0);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
        RenderMaterial(lighting: LightingModel.unlit),
        name: 'box',
      ),
    )
    ..add(camera);
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

void main() {
  late Directory out;
  setUp(() => out = Directory.systemTemp.createTempSync('reel'));
  tearDown(() => out.deleteSync(recursive: true));

  test('frames are numbered from nought, four digits, in the shot\'s '
      'folder', () async {
    final game = _game();
    final reel = Reel(
      renderer: game.renderer,
      width: 40,
      height: 20,
      out: out.path,
    );
    final shot = reel.shot('falls');
    expect(shot.folder, '${out.path}/falls');
    for (var i = 0; i < 3; i++) {
      final taken = await shot.film(scene: game.scene, camera: game.camera);
      // Mutation: one tile of 1024 by default — a reel's screen-space
      // passes are cut at a tile's edge, which a single picture never shows.
      expect(taken.report!.tilesX, 1);
    }
    expect(shot.frames, 3);
    // Mutation: count the frame before writing it, and the reel starts at
    // frame_0001 — a numbered sequence an encoder reads from nought misses
    // its first frame.
    final names =
        Directory(shot.folder)
            .listSync()
            .map((FileSystemEntity e) => e.uri.pathSegments.last)
            .toList()
          ..sort();
    expect(names, <String>[
      'frame_0000.png',
      'frame_0001.png',
      'frame_0002.png',
    ]);
    final bytes = File('${shot.folder}/frame_0000.png').readAsBytesSync();
    final header = ByteData.sublistView(bytes, 16, 24);
    expect((header.getUint32(0), header.getUint32(4)), (40, 20));
  });

  test('two shots of one reel keep their own count', () async {
    final game = _game();
    final reel = Reel(
      renderer: game.renderer,
      width: 16,
      height: 16,
      out: out.path,
    );
    final first = reel.shot('one');
    await first.film(scene: game.scene, camera: game.camera);
    await first.film(scene: game.scene, camera: game.camera);
    final second = reel.shot('two');
    await second.film(scene: game.scene, camera: game.camera);
    // Mutation: the frame counter kept on the reel — the second shot starts
    // at frame_0002 in its own folder.
    expect(File('${second.folder}/frame_0000.png').existsSync(), isTrue);
  });

  test('a reel can be drawn in tiles, as a photo is', () async {
    final game = _game();
    final shot = Reel(
      renderer: game.renderer,
      width: 40,
      height: 20,
      out: out.path,
      tileWidth: 16,
      tileHeight: 16,
    ).shot('tiled');
    final taken = await shot.film(scene: game.scene, camera: game.camera);
    expect(taken.report!.tilesX, 3);
  });

  test('a frame that could not be written stops the reel', () async {
    final game = _game();
    // A file where the shot's folder should be: nothing can be made in it.
    File('${out.path}/blocked').writeAsStringSync('');
    final shot = Reel(
      renderer: game.renderer,
      width: 16,
      height: 16,
      out: out.path,
    ).shot('blocked');
    // Mutation: return the failed `PhotoTaken` instead of throwing, and a
    // reel with a hole in it is written to the end and reported as done.
    await expectLater(
      shot.film(scene: game.scene, camera: game.camera),
      throwsStateError,
    );
    expect(shot.frames, 0);
  });

  test('the ease starts and ends at rest, and holds outside the shot', () {
    expect(reelEase(0.0), 0.0);
    expect(reelEase(1.0), 1.0);
    expect(reelEase(0.5), 0.5);
    // Mutation: unclamped — a camera asked for a moment before its shot
    // swings out the other way.
    expect(reelEase(-0.5), 0.0);
    expect(reelEase(1.5), 1.0);
    // At rest at both ends: the first step is smaller than a linear one.
    expect(reelEase(0.01), lessThan(0.01));
  });

  test('the frame name and the step', () {
    expect(reelFrameName(7), 'frame_0007.png');
    expect(reelFrameName(1234), 'frame_1234.png');
    expect(reelFrameStep, closeTo(1.0 / 30.0, 1e-12));
  });
}
