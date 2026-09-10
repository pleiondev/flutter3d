/// Where a number in `ProjectProfile` has to agree with a number in the
/// engine, because nothing else makes them agree.
///
///     flutter test test/profile_limits_test.dart
///
/// **`ProjectProfile` lives in `flutter3d_model_core`, which draws nothing and
/// has never heard of `Skeleton`.** That is the whole reason `doc-13` put a
/// hard ceiling on `maxJoints` rather than leaving it a plain number a profile
/// could set to anything: the shader array it is a budget for is declared here,
/// in the one package that imports both sides, and is the only place a test
/// can catch the two drifting apart.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no profile promises more joints than the skinning shader holds', () {
    // Mutation: raise `ProjectProfile`'s default `maxJoints` back toward the
    // old 128. A profile is a promise about what will load; `Skeleton.maxJoints`
    // is what the per-draw joint array in the shader actually holds, and a
    // profile promising more than that is a profile whose promise the engine
    // cannot keep — the export passes readiness and then draws the wrong pose
    // past joint 64.
    expect(
      const ProjectProfile().maxJoints,
      lessThanOrEqualTo(Skeleton.maxJoints),
    );
    expect(
      ProjectProfile.mobile.maxJoints,
      lessThanOrEqualTo(Skeleton.maxJoints),
    );
  });
}
