/// `hasShapeKeyAtFrame`: screen 15's own key dot, computed without a widget.
///
///     flutter test test/shape_key_state_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/shape_key_state.dart';
import 'package:flutter_test/flutter_test.dart';

const double _fps = 30.0;

/// A clip whose object 5 carries a two-component `weights` track keyed at
/// frame 10, built the same way `KeyShape.apply` itself builds one.
ProjectClip _clipWithWeightsKeyAtFrame10() {
  final table = KeyTable(componentCount: 2)
    ..setKey(KeyTable.timeOfFrame(10, _fps), <double>[0.5, 0.25]);
  return ProjectClip(
    tracks: <ProjectTrack>[
      ProjectTrack(
        objectId: 5,
        track: table.toAnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.weights,
        ),
      ),
    ],
  );
}

void main() {
  group('hasShapeKeyAtFrame', () {
    test('true on the frame a weights key was set at', () {
      expect(
        hasShapeKeyAtFrame(
          clip: _clipWithWeightsKeyAtFrame10(),
          objectId: 5,
          frame: 10,
          fps: _fps,
        ),
        isTrue,
      );
    });

    test('false on a frame with no key', () {
      expect(
        hasShapeKeyAtFrame(
          clip: _clipWithWeightsKeyAtFrame10(),
          objectId: 5,
          frame: 11,
          fps: _fps,
        ),
        isFalse,
      );
    });

    test('false for a different object entirely', () {
      expect(
        hasShapeKeyAtFrame(
          clip: _clipWithWeightsKeyAtFrame10(),
          objectId: 6,
          frame: 10,
          fps: _fps,
        ),
        isFalse,
      );
    });

    test('null clip reads as no key at all', () {
      expect(
        hasShapeKeyAtFrame(clip: null, objectId: 5, frame: 10, fps: _fps),
        isFalse,
      );
    });

    test('a rotation track on the same object at the same time is not a '
        'shape key', () {
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          ProjectTrack(
            objectId: 5,
            track: AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.rotation,
              interpolation: AnimationInterpolation.linear,
              times: Float32List.fromList(<double>[
                KeyTable.timeOfFrame(10, _fps),
              ]),
              values: Float32List.fromList(<double>[0, 0, 0, 1]),
              componentCount: 4,
            ),
          ),
        ],
      );

      expect(
        hasShapeKeyAtFrame(clip: clip, objectId: 5, frame: 10, fps: _fps),
        isFalse,
      );
    });
  });
}
