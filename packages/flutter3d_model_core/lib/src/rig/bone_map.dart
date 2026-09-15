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

/// Rig-family prefixes [looseAutoMap] strips before matching a name against
/// [_looseCentrelineSynonyms]/[_looseLimbSynonyms] — Mixamo's own
/// `mixamorig:` and 3ds Max Biped's `Bip01_`/`Bip01 `, compared case-
/// insensitively since a source file spells either anywhere from
/// `MIXAMORIG:` to `mixamoRig:`.
const List<String> _loosePrefixes = <String>['mixamorig:', 'bip01_', 'bip01 '];

/// Centreline bone words — nothing to pair a side with — onto one of
/// [humanoidBoneNames]' own five centreline entries.
const Map<String, String> _looseCentrelineSynonyms = <String, String>{
  'hips': 'hips',
  'hip': 'hips',
  'pelvis': 'hips',
  'root': 'hips',
  'spine': 'spine',
  'spine1': 'spine',
  'chest': 'chest',
  'spine2': 'chest',
  'upperchest': 'chest',
  'neck': 'neck',
  'head': 'head',
};

/// One limb's own bone word, without a side yet, onto the suffix a
/// `left`/`right` combines with to land on one of [humanoidBoneNames]' own
/// twelve limb entries — including each suffix's own bare word (`shoulder`,
/// `hip`, `knee`, ...), so a target already named the canonical way (every
/// rig this engine's own `buildSkeleton` produces) reads back onto itself
/// exactly the way [autoMap] already matches it, and this loose pass never
/// does worse for that case than the exact one.
///
/// **`shoulder`/`clavicle` and `arm`/`upperarm` both land on `Shoulder`.** A
/// source rig that names both — Mixamo's own `LeftShoulder` (a clavicle) and
/// `LeftArm` (the actual upper-arm bone) — has both read as the same
/// canonical joint, so [looseAutoMap] gives both source names an entry
/// pointing at the one target bone; that is a known imprecision of a
/// name-only match, not a crash, and typical export order (the clavicle
/// listed before its own child, the upper arm) leaves the upper arm's own
/// entry the one built last, which is also the one whichever caller reads
/// last wins with.
const Map<String, String> _looseLimbSynonyms = <String, String>{
  'shoulder': 'Shoulder',
  'clavicle': 'Shoulder',
  'arm': 'Shoulder',
  'upperarm': 'Shoulder',
  'elbow': 'Elbow',
  'forearm': 'Elbow',
  'lowerarm': 'Elbow',
  'wrist': 'Wrist',
  'hand': 'Wrist',
  'hip': 'Hip',
  'thigh': 'Hip',
  'upleg': 'Hip',
  'knee': 'Knee',
  'leg': 'Knee',
  'calf': 'Knee',
  'shin': 'Knee',
  'ankle': 'Ankle',
  'foot': 'Ankle',
};

/// [rawName] with the first of [_loosePrefixes] that matches removed,
/// case-insensitively — or [rawName] unchanged when none does.
String _stripLoosePrefix(String rawName) {
  final String lower = rawName.toLowerCase();
  for (final String prefix in _loosePrefixes) {
    if (lower.startsWith(prefix)) return rawName.substring(prefix.length);
  }
  return rawName;
}

/// [name], lower-cased with every character but a letter or a digit
/// dropped — what both synonym tables above are keyed by, so `Spine1`,
/// `spine_1` and `SPINE-1` all read as the identical `spine1`, digit kept:
/// [_looseCentrelineSynonyms] tells `spine1` and `spine2` apart by it.
String _lettersOnly(String name) =>
    name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// [afterPrefix]'s own side and its core word, once both the rig-family
/// prefix and the side marker are gone. Mixamo spells a side as a full
/// `Left`/`Right` word at the very start (`LeftUpLeg`); 3ds Max Biped spells
/// it as a lone `L`/`R` token set off by an underscore or a space right
/// after its own prefix (`Bip01_L_UpperArm`, `Bip01 L UpperArm`). Neither of
/// those is anchored to the front of the *whole* name once a caller's own
/// naming puts the side marker mid-word instead (`leg_joint_R_1`,
/// `Bone_Hand.L`) — [_looseSideAnywhere] is the fallback for that shape.
/// Null when [afterPrefix] carries no recognisable side marker at all — a
/// centreline bone, or a name this loose reading does not recognise the
/// shape of.
({bool left, String core})? _looseSide(String afterPrefix) {
  final String lower = afterPrefix.toLowerCase();
  if (lower.startsWith('left')) {
    return (left: true, core: afterPrefix.substring(4));
  }
  if (lower.startsWith('right')) {
    return (left: false, core: afterPrefix.substring(5));
  }
  final Match? token = RegExp(r'^[lr][_ ]').matchAsPrefix(lower);
  if (token != null) {
    return (left: lower[0] == 'l', core: afterPrefix.substring(token.end));
  }
  return _looseSideAnywhere(afterPrefix);
}

/// Every delimiter [_looseSideAnywhere] splits a name on before looking for
/// a side token — underscore, dot, space and hyphen, the separators every
/// naming convention this file already knows (`mixamorig:`'s own colon is
/// handled by [_stripLoosePrefix] before this ever runs) uses somewhere.
final RegExp _looseTokenBoundary = RegExp(r'[_.\- ]');

/// [name] split into words on [_looseTokenBoundary] and on each lower-to-
/// upper camelCase boundary, empty pieces dropped — `leg_joint_R_1` reads as
/// `leg`, `joint`, `R`, `1`; `BoneHandL` reads as `Bone`, `Hand`, `L`.
List<String> _looseTokens(String name) {
  final StringBuffer marked = StringBuffer();
  for (int i = 0; i < name.length; i++) {
    if (i > 0 && _isLowerLetter(name[i - 1]) && _isUpperLetter(name[i])) {
      marked.write('_');
    }
    marked.write(name[i]);
  }
  return marked
      .toString()
      .split(_looseTokenBoundary)
      .where((String token) => token.isNotEmpty)
      .toList();
}

bool _isLowerLetter(String char) => RegExp('[a-z]').hasMatch(char);

bool _isUpperLetter(String char) => RegExp('[A-Z]').hasMatch(char);

/// [_looseSide]'s own fallback once neither Mixamo's nor Biped's start-
/// anchored shape matches at position zero: [afterPrefix] split into
/// [_looseTokens], the first token read as `l`/`r`/`left`/`right`
/// (case-insensitively — the same vocabulary the start-anchored shapes
/// above already match) taken as the side marker wherever in the name it
/// falls, and every *other* token, still in order, rejoined into the core
/// the caller looks up the ordinary way. Null when no token reads as a
/// side at all.
({bool left, String core})? _looseSideAnywhere(String afterPrefix) {
  final List<String> tokens = _looseTokens(afterPrefix);
  for (int i = 0; i < tokens.length; i++) {
    final bool? left = switch (tokens[i].toLowerCase()) {
      'left' => true,
      'right' => false,
      'l' => true,
      'r' => false,
      _ => null,
    };
    if (left == null) continue;
    final List<String> rest = List<String>.of(tokens)..removeAt(i);
    return (left: left, core: rest.join('_'));
  }
  return null;
}

/// [rawName] read against [humanoidBoneNames] the loose way: a rig-family
/// prefix stripped, a side detected by either convention above, and the
/// remaining core word looked up in [_looseCentrelineSynonyms] (no side) or
/// [_looseLimbSynonyms] (paired with the side into `left`/`right` plus a
/// suffix) — or null when nothing in either table answers for it.
String? _looseCanonicalOf(String rawName) {
  final String afterPrefix = _stripLoosePrefix(rawName);
  final ({bool left, String core})? side = _looseSide(afterPrefix);
  if (side == null) {
    return _looseCentrelineSynonyms[_lettersOnly(afterPrefix)];
  }
  final String? suffix = _looseLimbSynonyms[_lettersOnly(side.core)];
  return suffix == null ? null : (side.left ? 'left' : 'right') + suffix;
}

/// A synonym-and-prefix-tolerant [autoMap] — `anim-18`'s own row. Retargeting
/// a mocap file means matching a rig this engine never built and that rarely
/// shares a single literal bone name with one: Mixamo's own
/// `mixamorig:LeftArm`, 3ds Max Biped's `Bip01_L_UpperArm`, or simply a
/// different capitalisation of the same word. [autoMap] itself stays
/// exact-match only — loosening it would risk the "same skeleton — identity"
/// guarantee its own doc comment leans on — so this is the separate, looser
/// pass instead: every one of [sourceNames] and [targetNames] is read
/// through [_looseCanonicalOf], and two names that land on the same one of
/// [humanoidBoneNames] pair up.
///
/// A name [autoMap] would already match exactly matches here too — both
/// synonym tables carry every canonical name as an entry of its own — so a
/// caller can reach for this in place of [autoMap] without losing anything
/// the exact pass already caught.
BoneMap looseAutoMap(List<String> sourceNames, List<String> targetNames) {
  final Map<String, String> targetByCanonical = <String, String>{
    for (final String target in targetNames)
      if (_looseCanonicalOf(target) case final String canon) canon: target,
  };
  final Map<String, String> map = <String, String>{};
  for (final String source in sourceNames) {
    final String? canon = _looseCanonicalOf(source);
    final String? target = canon == null ? null : targetByCanonical[canon];
    if (target != null) map[source] = target;
  }
  return BoneMap(map);
}
