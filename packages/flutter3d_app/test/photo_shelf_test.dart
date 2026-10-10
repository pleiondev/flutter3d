/// Photo mode's last step — `N8`: a picture drawn, encoded and on a shelf in
/// one call, and the folder each platform keeps it in.
///
///     flutter test test/photo_shelf_test.dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

({Renderer renderer, Scene scene, CameraNode camera}) _game() {
  final device = CpuDevice(
    width: 64,
    height: 48,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode(
    name: 'eye',
    projection: const PerspectiveProjection(fovY: 0.9),
  )..setPosition(0.0, 0.0, 3.0);
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
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('photo_shelf'));
  tearDown(() => folder.deleteSync(recursive: true));

  test('a picture larger than the game\'s screen lands as one PNG', () async {
    final game = _game();
    final taken = await savePhoto(
      renderer: game.renderer,
      scene: game.scene,
      camera: game.camera,
      width: 150,
      height: 70,
      tileWidth: 64,
      tileHeight: 32,
      shelf: FilePhotoShelf(appName: 'game', directory: folder),
      name: 'shot.png',
    );
    expect(taken.saved.kept, isTrue, reason: taken.saved.message);
    expect(taken.report!.tilesX, 3);
    // Mutation: skip the rename in `_FileSaving.close`. The picture stays a
    // `.part` that no image viewer lists, and the message names a file that
    // is not there.
    final names = folder.listSync().map((e) => e.uri.pathSegments.last);
    expect(names, <String>['shot.png']);
    // The header's size, and the end chunk last: a whole file, of the picture
    // asked for. `photo_capture_test.dart` decodes the pixels.
    final bytes = File('${folder.path}/shot.png').readAsBytesSync();
    final header = ByteData.sublistView(bytes, 16, 24);
    expect((header.getUint32(0), header.getUint32(4)), (150, 70));
    expect(
      String.fromCharCodes(bytes.sublist(bytes.length - 8)),
      startsWith('IEND'),
    );
  });

  test('a capture that fails leaves nothing behind and says why', () async {
    final game = _game();
    final taken = await savePhoto(
      renderer: game.renderer,
      scene: game.scene,
      camera: game.camera,
      width: 150,
      height: 70,
      tileWidth: 0,
      tileHeight: 32,
      shelf: FilePhotoShelf(appName: 'game', directory: folder),
      name: 'shot.png',
    );
    // Mutation: drop the `abandon` in `savePhoto`'s catch. A `.part` holding
    // the PNG's header is left in the player's Pictures folder for every
    // capture that failed.
    expect(taken.saved.kept, isFalse);
    expect(taken.saved.message, contains('cannot cover a picture'));
    expect(folder.listSync(), isEmpty);
  });

  test('a desktop keeps photos in Pictures, a phone in the game\'s folder', () {
    String? where(TargetPlatform platform, Map<String, String> environment) =>
        picturesDirectory(
          appName: 'game',
          platform: platform,
          environment: environment,
          temporary: '/data/user/0/dev.game/cache',
        );
    expect(
      where(TargetPlatform.linux, {'HOME': '/home/p'}),
      '/home/p/Pictures/game',
    );
    expect(
      where(TargetPlatform.windows, {'USERPROFILE': r'C:\Users\p'}),
      r'C:\Users\p\Pictures\game',
    );
    // Mutation: put Android under `$HOME/Pictures` like Linux. `HOME` there is
    // not the application's, the write fails, and no photo is ever kept.
    expect(
      where(TargetPlatform.android, {'HOME': '/'}),
      '/data/user/0/dev.game/files/game/photos',
    );
    expect(where(TargetPlatform.windows, const {}), isNull);
  });
}
