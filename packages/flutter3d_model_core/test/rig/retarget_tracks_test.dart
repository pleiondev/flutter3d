/// `retargetTracks` over rigs built by hand, with no project anywhere — the
/// point of the rig being read as nodes and tracks.
///
///     dart test test/rig/retarget_tracks_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A root and a head [height] above it.
RetargetRig _post(double height) => RetargetRig(
  nodes: <RigNode>[
    RigNode(id: 1, name: 'root', restLocal: Matrix4.identity()),
    RigNode(
      id: 2,
      name: 'head',
      restLocal: Matrix4.translation(Vector3(0, height, 0)),
      parent: 1,
    ),
  ],
  joints: const <int>[1, 2],
);

AnimationTrack _track(AnimationPath path, List<double> values) =>
    AnimationTrack(
      nodeIndex: 0,
      path: path,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0]),
      values: Float32List.fromList(values),
      componentCount: values.length,
    );

void main() {
  final names = <String>['root', 'head'];

  test('a rig retargeted onto itself is the identity', () {
    final rig = _post(1.0);
    final turn = Quaternion.axisAngle(Vector3(0, 1, 0), 0.7);
    final moved = retargetTracks(
      tracks: <RigTrack>[
        RigTrack(
          nodeId: 2,
          track: _track(AnimationPath.rotation, <double>[
            turn.x,
            turn.y,
            turn.z,
            turn.w,
          ]),
        ),
      ],
      source: rig,
      target: rig,
      boneMap: autoMap(names, names),
      lockFeet: false,
    );
    expect(moved.single.nodeId, 2);
    final values = moved.single.track.values;
    expect(values[0], closeTo(turn.x, 1e-6));
    expect(values[1], closeTo(turn.y, 1e-6));
    expect(values[2], closeTo(turn.z, 1e-6));
    expect(values[3], closeTo(turn.w, 1e-6));
  });

  test('a translation is scaled by the ratio of the two rigs\' heights', () {
    // Mutation: read the height off the joints alone and stop the walk at a
    // parent that is not one. A rig whose root is an armature empty measures
    // a different height and every root-motion clip covers the wrong ground.
    final moved = retargetTracks(
      tracks: <RigTrack>[
        RigTrack(
          nodeId: 1,
          track: _track(AnimationPath.translation, <double>[0, 1, 0]),
        ),
      ],
      source: _post(1.0),
      target: _post(2.0),
      boneMap: autoMap(names, names),
      lockFeet: false,
    );
    expect(moved.single.track.values[1], closeTo(2.0, 1e-6));
  });
}
