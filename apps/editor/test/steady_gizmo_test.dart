/// Two marks in one place, drawn again and again.
///
///     flutter test test/steady_gizmo_test.dart
///
/// **"The editor flickers like hell", and the flicker is a pickup and a
/// trigger.** The crypt puts a monster at (0, 1, −12) and a trigger volume four
/// metres wide at (0, 1.5, −12.4), so one mark sits inside the other — and the
/// editor draws a mark for everything the renderer does not.
///
/// This asks the one question nothing else here asked: is the *same* scene, on
/// the *same* renderer, the same picture on the next frame? Every other test
/// renders one frame, or renders twice with the level rebuilt in between.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:editor/src/gizmos.dart';
import 'package:editor/src/vocabulary.dart';
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// The crypt's own arrangement, cut down to the pair that overlaps.
Level _level() => Level.fromJson(jsonDecode(jsonEncode(<String, Object?>{
      'version': 1,
      'materials': <String, Object?>{
        'stone': <String, Object?>{'baseColor': <double>[0.7, 0.7, 0.7, 1.0]},
      },
      'brushes': <Object?>[
        <String, Object?>{
          'at': <double>[0.0, -0.5, -12.0],
          'size': <double>[20.0, 1.0, 20.0],
          'material': 'stone',
        },
        // A wall, and the mark below sits flush against it — which is how a
        // trigger or a note is placed, and where a flat box and a flat wall
        // have the same depth.
        <String, Object?>{
          'at': <double>[0.0, 2.0, -14.0],
          'size': <double>[20.0, 4.0, 1.0],
          'material': 'stone',
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0.0, 3.0, -10.0],
          'color': <double>[1.0, 1.0, 1.0],
          'intensity': 6.0,
          'range': 20.0,
        },
      ],
      'entities': <Object?>[
        <String, Object?>{'type': 'monster', 'at': <double>[0.0, 1.0, -12.0]},
        <String, Object?>{
          'type': 'trigger',
          'at': <double>[0.0, 1.5, -12.4],
          'size': <double>[4.0, 3.0, 2.0],
        },
        // Flush with the wall's face at z = −13.5.
        <String, Object?>{
          'type': 'note',
          'at': <double>[3.0, 2.0, -13.25],
          'size': <double>[1.5, 2.0, 0.5],
        },
        // A door: sized like the trigger and made of something, which is what
        // tells the two apart.
        <String, Object?>{
          'type': 'door',
          'at': <double>[-6.0, 2.0, -13.5],
          'size': <double>[3.0, 4.0, 1.0],
          'material': 'stone',
        },
      ],
    })) as Map<String, Object?>);

void main() {
  test('a region the document sized is a cage, not a slab', () {
    // **The editor's way of saying "this is a region" without knowing what a
    // trigger is.** Something the author gave a size to is something whose
    // extent is the point, and a solid box drawn over one hides what it
    // contains and lies flat against the wall it was placed on.
    final level = _level();
    final handles = <Piece, List<Handle>>{};
    for (final handle in handlesOf(level)) {
      handles.putIfAbsent(handle.kind, () => <Handle>[]).add(handle);
    }
    final entities = handles[Piece.entity]!;

    expect(entities.where((Handle it) => it.volume), hasLength(3),
        reason: 'the trigger, the note and the door carry their own size');

    // **What separates a region from a thing is the material.** A door is
    // sized exactly the way a trigger is, and it is something the level builds
    // — so the editor draws it as the stone or iron it says it is made of,
    // and drawing it as a wireframe was this rule's first mistake.
    final door = level.entities.firstWhere((EntityDef e) => e.type == 'door');
    expect(door.string('material'), isNotNull);
    final trigger =
        level.entities.firstWhere((EntityDef e) => e.type == 'trigger');
    expect(trigger.string('material'), isNull);
    expect(
      entities.where((Handle it) => !it.volume).length,
      greaterThan(0),
      reason: 'a monster has no size of its own and is not a region',
    );
  });

  test('a mark inside another mark draws the same on every frame', () async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final level = _level();
    final loaded = await LevelLoader().build(
      level,
      device: device,
      registry: vocabularyOf(level),
    );
    final scene = loaded.scene;

    // The marks, placed the way `_placeGizmos` places them.
    for (final handle in handlesOf(level)) {
      if (handle.kind == Piece.brush) continue;
      scene.add(
        MeshNode(
          SharedMeshes(device).box(handle.size),
          engine.Material(
            name: 'gizmo',
            baseColor:
                Vector4(handle.tint.x, handle.tint.y, handle.tint.z, 1.0),
            emissive: handle.tint * 0.9,
          ),
          name: 'gizmo',
        )
          ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
          ..castsShadow = false,
      );
    }

    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.05,
        near: 0.1,
        far: 200.0,
      ),
    )..setPosition(0.0, 2.0, -4.0);
    camera.lookAt(Vector3(0.0, 1.2, -12.0));
    scene.add(camera);

    Future<Uint8List> draw() async {
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[
          RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
        ],
        settings: const RenderSettings(),
      );
      return (await device.readPixels(result.frame))!.buffer.asUint8List();
    }

    final first = await draw();
    for (var frame = 2; frame <= 6; frame++) {
      final next = await draw();
      expect(compareFrames(first, next, channel: 0).differing, 0,
          reason: 'frame $frame is a different picture from the first');
    }
  });
}
