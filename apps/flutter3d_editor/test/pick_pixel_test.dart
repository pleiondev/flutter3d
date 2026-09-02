/// A click lands on what is drawn, and what is drawn knows its piece of the
/// document.
///
///     flutter test test/pick_pixel_test.dart
///
/// The editor used to answer a click with a ray against every handle's box and
/// a rule for ties — anything that is not a wall wins within a metre of the
/// nearest hit. The rule existed because a monster's box is a metre wider than
/// the monster and a torch's box is inside the wall it hangs on, so a ray
/// could not tell which of two boxes somebody meant. Now the renderer says
/// which mesh is under the pixel, and this is the half the editor owns: from
/// that mesh back to the handle it was drawn for, and for the level's own
/// geometry — one batch per material, no brush of its own — back to the brush
/// by the ray, which on the face drawn there is the face's own.
library;

import 'dart:convert';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/gizmos.dart';
import 'package:flutter3d_editor/src/looks.dart';
import 'package:flutter3d_editor/src/picking.dart';
import 'package:flutter3d_editor/src/scene_dressing.dart';
import 'package:flutter3d_editor/src/vocabulary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

/// A floor, a wall behind it, and a monster standing on the floor a little
/// in front of the wall — with its mark's box reaching into the wall's.
String _document() => jsonEncode(<String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.7, 0.7, 0.7, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, -0.5, -10.0],
      'size': <double>[20.0, 1.0, 20.0],
      'material': 'stone',
    },
    <String, Object?>{
      'at': <double>[0.0, 2.0, -12.5],
      'size': <double>[20.0, 4.0, 1.0],
      'material': 'stone',
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0.0, 3.0, -8.0],
      'color': <double>[1.0, 1.0, 1.0],
      'intensity': 6.0,
      'range': 20.0,
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'monster',
      'at': <double>[0.0, 0.25, -11.6],
    },
  ],
});

/// Where a world point lands in the frame, as fractions from the top left.
({double u, double v}) _project(CameraNode camera, Vector3 point) {
  // Typed, because `Matrix4.operator*` returns `dynamic`.
  final Vector4 clip =
      camera.viewProjection(_width / _height) *
      Vector4(point.x, point.y, point.z, 1.0);
  return (
    u: (clip.x / clip.w + 1.0) / 2.0,
    v: (1.0 - clip.y / clip.w) / 2.0,
  );
}

void main() {
  test('a mark answers its handle and a wall answers its brush', () async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final editing = Editing.parse(_document(), path: 'level.json');
    final loaded = await LevelLoader().build(
      editing.level,
      device: device,
      registry: vocabularyOf(editing.level),
    );
    final scene = loaded.scene;
    final dressing = SceneDressing(device)
      ..textures = loaded.materialTextures
      ..reset()
      ..placeGizmos(
        scene,
        editing,
        looks: Looks.none,
        hidden: const <String>{},
      );

    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.0,
        near: 0.1,
        far: 100.0,
      ),
    )..setPosition(0.0, 1.0, -6.0);
    camera.lookAt(Vector3(0.0, 0.5, -12.0));
    scene.add(camera);
    final view = RenderView(camera: camera);
    final eye = Vector3(0.0, 1.0, -6.0);

    final monster = handlesOf(editing.level).firstWhere(
      (Handle h) => h.kind == Piece.entity,
    );
    final onMark = _project(camera, monster.centre);
    // Well to the side of the mark, on the wall behind it.
    final onWall = _project(camera, Vector3(3.0, 2.0, -12.0));

    final markPick = renderer.pickPixel(onMark.u, onMark.v);
    final wallPick = renderer.pickPixel(onWall.u, onWall.v);
    renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[view],
    );

    // The mark: the mesh drawn there was placed for the monster, and the
    // dressing says so. Mutation: forget to record the owner in placeGizmos —
    // the mark reads as level geometry and the ray answers the floor under
    // it.
    final markNode = await markPick;
    expect(markNode, isNotNull, reason: 'nothing was drawn at the mark');
    final owner = dressing.handleFor(markNode);
    expect(owner, isNotNull);
    expect(owner!.kind, Piece.entity);
    expect(owner.index, monster.index);

    // The wall: level geometry, which no handle owns, so the ray through the
    // click names the brush — and it names the wall, not the floor the ray
    // would reach first if it were aimed low.
    final wallNode = await wallPick;
    expect(wallNode, isNotNull, reason: 'nothing was drawn on the wall');
    expect(dressing.handleFor(wallNode), isNull);
    expect(dressing.isMarker(wallNode), isFalse);
    final along = Picking.through(
      Vector2(onWall.u * _width, onWall.v * _height),
      size: Vector2(_width.toDouble(), _height.toDouble()),
      forward: (Vector3(0.0, 0.5, -12.0) - eye)..normalize(),
      right: Vector3(1.0, 0.0, 0.0),
      up: Vector3(0.0, 1.0, 0.0),
      fovY: 1.0,
    );
    expect(Picking.brushAt(editing.level.brushes, eye, along), 1);
  });

  test('the selection cage is known for what it is', () {
    // Mutation: register the marker as an owner — a click on the cage would
    // select the cage's own piece, which is the piece already selected, and
    // nothing under it could ever be picked through the bars.
    final device = CpuDevice(
      width: 8,
      height: 8,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final editing = Editing.parse(_document(), path: 'level.json')
      ..select(Piece.brush, 0);
    final scene = Scene();
    final dressing = SceneDressing(device)..placeMarker(scene, editing);
    final marker = dressing.marker;
    expect(marker, isNotNull);
    final bar = marker!.children.first;
    expect(dressing.isMarker(bar), isTrue);
    expect(dressing.handleFor(bar), isNull);
    expect(dressing.isMarker(null), isFalse);
  });
}
