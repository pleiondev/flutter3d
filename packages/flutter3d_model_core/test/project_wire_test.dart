/// The words `.f3dproj` and the command journal write for enums.
///
///     flutter test test/project_wire_test.dart
///
/// **The words were the Dart names on the day the tables replaced `.name`**,
/// so no project saved before changed meaning. This pins each word: a case
/// renamed in Dart keeps its word, and this test is what says so.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_core/src/project_wire.dart';
import 'package:test/test.dart';

void main() {
  void holds<T extends Enum>(
    List<T> values,
    String Function(T) write,
    T? Function(Object?) read,
    List<String> words,
  ) {
    // Mutation: write a value's `.name` after renaming it, and the word in
    // [words] no longer matches.
    expect(values.map(write).toList(), words);
    for (final value in values) {
      expect(read(write(value)), value);
    }
    expect(read('no such word'), isNull);
  }

  test('every table writes the word it wrote at 1.0, and reads it back', () {
    holds(StepAuthor.values, stepAuthorWord, stepAuthorOf, <String>[
      'person',
      'agent',
    ]);
    holds(ProfileTarget.values, profileTargetWord, profileTargetOf, <String>[
      'desktop',
      'mobile',
      'web',
    ]);
    holds(
      TextureFileFormat.values,
      textureFileFormatWord,
      textureFileFormatOf,
      <String>['rgba8', 'bc1', 'bc3', 'bc7', 'etc2Rgba8', 'astc4x4', 'other'],
    );
    holds(SurfaceAlphaMode.values, alphaModeWord, alphaModeOf, <String>[
      'opaque',
      'mask',
      'blend',
    ]);
    holds(TextureWrap.values, textureWrapWord, textureWrapOf, <String>[
      'repeat',
      'clampToEdge',
      'mirroredRepeat',
    ]);
    holds(SelectionMode.values, selectionModeWord, selectionModeOf, <String>[
      'object',
      'mesh',
    ]);
    holds(ElementLevel.values, elementLevelWord, elementLevelOf, <String>[
      'vertex',
      'edge',
      'face',
    ]);
    holds(
      TextureBlendMode.values,
      textureBlendModeWord,
      textureBlendModeOf,
      <String>['normal', 'multiply', 'add', 'screen'],
    );
    holds(TextureChannel.values, textureChannelWord, textureChannelOf, <String>[
      'r',
      'g',
      'b',
      'a',
    ]);
    holds(TransformPivot.values, transformPivotWord, transformPivotOf, <String>[
      'median',
      'individual',
    ]);
    holds(TransformSpace.values, transformSpaceWord, transformSpaceOf, <String>[
      'global',
      'local',
    ]);
    holds(AnimationPath.values, animationPathWord, animationPathOf, <String>[
      'translation',
      'rotation',
      'scale',
      'weights',
      'pointer',
    ]);
    holds(
      AnimationInterpolation.values,
      interpolationWord,
      interpolationOf,
      <String>['step', 'linear', 'cubicSpline'],
    );
    holds(CsgOperation.values, csgOperationWord, csgOperationOf, <String>[
      'union',
      'subtract',
      'intersect',
    ]);
  });
}
