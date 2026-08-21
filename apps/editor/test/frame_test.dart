/// The picture follows the document, or the editor is lying.
///
///     flutter test test/frame_test.dart
///
/// **The one property an editor cannot be wrong about.** Every other test here
/// checks the document; this checks that what somebody is looking at is that
/// document and not the one it used to be. A brush is batched into its
/// material's mesh, so nothing can be patched in place — moving anything means
/// building the whole level again, and if that ever stops happening the numbers
/// in the corner go on changing while the picture stands still.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:editor/src/editing.dart';
import 'package:editor/src/gizmos.dart';
import 'package:editor/src/vocabulary.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

String _document() => jsonEncode(<String, Object?>{
      'version': 1,
      'name': 'test',
      'materials': <String, Object?>{
        'stone': <String, Object?>{'baseColor': <double>[0.8, 0.8, 0.8, 1.0]},
      },
      'brushes': <Object?>[
        // A floor, so the camera has something to see whatever else moves.
        <String, Object?>{
          'at': <double>[0.0, -1.0, 0.0],
          'size': <double>[40.0, 1.0, 40.0],
          'material': 'stone',
        },
        // The one that will be moved.
        <String, Object?>{
          'at': <double>[0.0, 1.0, -6.0],
          'size': <double>[2.0, 2.0, 2.0],
          'material': 'stone',
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'directional',
          'direction': <double>[-0.4, -1.0, -0.3],
          'color': <double>[1.0, 1.0, 1.0],
          'intensity': 4.0,
        },
      ],
    });

/// A device, a renderer and a camera looking down -Z from head height.
final class _Shown {
  _Shown._(this.device, this.renderer, this.camera);

  factory _Shown.open() {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.05,
        near: 0.1,
        far: 200.0,
      ),
    )..setPosition(0.0, 1.5, 6.0);
    camera.lookAt(Vector3(0.0, 1.0, -6.0));
    return _Shown._(device, renderer, camera);
  }

  final GraphicsDevice device;
  final Renderer renderer;
  final CameraNode camera;

  /// Draws [editing]'s document exactly the way the application does: build the
  /// whole level from the document, then render it.
  Future<Uint8List> draw(Editing editing) async {
    final loaded = await LevelLoader().build(
      editing.level,
      device: device,
      registry: vocabularyOf(editing.level),
    );
    final scene = loaded.scene..add(camera);
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: const RenderSettings(),
    );
    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    return pixels!.buffer.asUint8List();
  }
}

/// How many pixels differ by more than a rounding wobble.
///
/// Two, not the shared default of eight: nothing here is animated, so two
/// renders of an unchanged scene are byte-identical and anything above the
/// noise floor is a real move.
int _differences(Uint8List a, Uint8List b) =>
    differingPixels(a, b, channel: 2);

void main() {
  test('a brush that moves moves in the picture', () async {
    final shown = _Shown.open();
    final editing = Editing.parse(_document(), path: '/levels/test.json')
      ..select(Piece.brush, 1);

    final before = await shown.draw(editing);
    editing.nudge(Vector3(2.0, 0.0, 0.0));
    final after = await shown.draw(editing);

    final moved = _differences(before, after);
    expect(moved, greaterThan(20),
        reason: 'the document moved a brush two metres and $moved pixels '
            'out of ${_width * _height} changed');
  });

  test('and a brush that is added appears', () async {
    final shown = _Shown.open();
    final editing = Editing.parse(_document(), path: '/levels/test.json');

    final before = await shown.draw(editing);
    editing.add(Vector3(0.0, 1.0, 0.0), size: Vector3(2.0, 2.0, 2.0));
    final after = await shown.draw(editing);

    expect(_differences(before, after), greaterThan(20),
        reason: 'a new brush right in front of the camera changed nothing');
  });

  test('and one that is deleted goes', () async {
    final shown = _Shown.open();
    final editing = Editing.parse(_document(), path: '/levels/test.json')
      ..select(Piece.brush, 1);

    final before = await shown.draw(editing);
    editing.remove();
    final after = await shown.draw(editing);

    expect(_differences(before, after), greaterThan(20),
        reason: 'the brush in front of the camera was deleted and the picture '
            'kept it');
  });

  test('and a light that is added lights the room', () async {
    // **The one edit whose effect is not where the edit is.** Moving a brush
    // changes the pixels the brush covers; adding a light changes every pixel
    // it reaches. If the level were not rebuilt from the document, this is the
    // test that would still pass by accident — so it counts a large change
    // rather than any change.
    final shown = _Shown.open();
    final editing = Editing.parse(_document(), path: '/levels/test.json');

    final before = await shown.draw(editing);
    editing.addLight(Vector3(0.0, 2.0, -4.0), intensity: 40.0, range: 20.0);
    final after = await shown.draw(editing);

    final lit = _differences(before, after);
    expect(lit, greaterThan(_width * _height ~/ 8),
        reason: 'a lamp in the middle of the room changed $lit pixels');
  });

  test('and a document nobody touched draws the same twice', () async {
    // The other half of the claim: the differences above are the edits and not
    // the renderer wobbling.
    final shown = _Shown.open();
    final editing = Editing.parse(_document(), path: '/levels/test.json');

    final once = await shown.draw(editing);
    final twice = await shown.draw(editing);

    expect(_differences(once, twice), 0);
  });
}
