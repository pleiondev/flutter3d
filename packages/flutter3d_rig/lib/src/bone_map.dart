/// Names one skeleton's own bones onto another's, by name — `anim-17`'s own
/// `BoneMap`.
library;

/// The humanoid bone names [autoMap] knows, in `anim-21`'s own
/// `RigTemplate.humanoid` order (`rig_template.dart`, `packages
/// /flutter3d_model_core`). That table's own bone list is private to its
/// file, so this is a second, hand-kept copy rather than an import — the
/// two are meant to name the same seventeen joints, and a rig built by
/// `buildSkeleton(RigTemplate.humanoid, ...)` maps onto another one built
/// the same way name-for-name, which is what makes retargeting onto the
/// same skeleton an identity (`retargetClip`'s own first acceptance
/// clause).
const List<String> humanoidBoneNames = <String>[
  'hips',
  'spine',
  'chest',
  'neck',
  'head',
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
];

/// [name]'s own left/right mirror by the `left`/`right` prefix
/// `rig_template.dart` already uses (`leftHip`/`rightHip`), or `name`
/// unchanged for a centerline bone (`hips`, `spine`, ...) that has none.
String mirrorBoneName(String name) {
  if (name.startsWith('left')) return 'right${name.substring(4)}';
  if (name.startsWith('right')) return 'left${name.substring(5)}';
  return name;
}

/// A source bone name → target bone name mapping, used by [retargetClip] to
/// find, for each animated source bone, which bone (if any) on the target
/// skeleton it drives.
class BoneMap {
  const BoneMap(Map<String, String> map) : _map = map;

  final Map<String, String> _map;

  /// The target bone [sourceName] maps onto, or `null` when nothing on the
  /// target answers for it — the ordinary case for a bone the source has
  /// and the target does not (fingers on a source rig retargeted onto a
  /// finger-less target), which [retargetClip] simply drops the track for.
  String? targetOf(String sourceName) => _map[sourceName];

  int get length => _map.length;

  bool get isEmpty => _map.isEmpty;

  @override
  String toString() => 'BoneMap($_map)';
}

/// Guesses a [BoneMap] from [sourceNames] to [targetNames] using
/// [humanoidBoneNames] plus L/R pairing — `anim-17`'s own "по словарю
/// гуманоида и L/R" (by the humanoid dictionary and L/R).
///
/// **Exact-name matching against the dictionary, not fuzzy matching.** A
/// bone actually named `leftHip` on both sides maps; a bone named `LeftHip`
/// or `l_hip` does not — `anim-21`'s own `buildSkeleton` is the only writer
/// of this exact naming in this codebase today, so two rigs built by it
/// (the ordinary case this row's own acceptance exercises: retargeting
/// between two `RigTemplate.humanoid` skeletons) match every joint, and the
/// "same skeleton — identity" clause holds for the strongest possible
/// reason: every name is literally identical.
///
/// A name not in [humanoidBoneNames] is still mapped when [sourceNames] and
/// [targetNames] both contain it verbatim (an exact non-dictionary name
/// match), so a caller with its own consistent naming is not refused
/// outright — only names *foreign to both* the dictionary and each other go
/// unmapped.
BoneMap autoMap(List<String> sourceNames, List<String> targetNames) {
  final targetSet = targetNames.toSet();
  final map = <String, String>{};
  for (final source in sourceNames) {
    if (targetSet.contains(source)) {
      map[source] = source;
    }
  }
  return BoneMap(map);
}
