/// The `PaintMirror.jointMirror` map a skeleton's own joint names already
/// imply — `ui/weight_paint_panel.dart`'s own "Mirror" flag, wired without
/// asking a person to draw the map by hand.
///
/// **Only a naming convention this project's own rigs already use.**
/// `mirrorWeights` (`flutter3d_mesh`) reads an entry missing from the map as
/// "stays itself" — a spine or a head bone straddling the plane needs no
/// entry at all, per its own doc comment — so this only ever has to name the
/// pairs that swap sides: a joint whose name ends `.L` mirrors the joint of
/// the same name ending `.R`, and back. A rig using another convention
/// (`_L`/`_R`, `Left`/`Right`) mirrors nothing until it is renamed to match —
/// an honest "not this rig" rather than a guess that mirrors the wrong bone.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// `.L`'s counterpart, `.R`'s, or null for a name with neither suffix.
String? _oppositeSideName(String name) {
  if (name.endsWith('.L')) return '${name.substring(0, name.length - 2)}.R';
  if (name.endsWith('.R')) return '${name.substring(0, name.length - 2)}.L';
  return null;
}

/// [PaintMirror.jointMirror] for [skeleton], read off [project]'s own joint
/// names — keys and values are indices into [skeleton.joints], the same
/// local addressing `weightsOf`'s own `WeightPair.joint` stores and
/// `PaintWeights.mirror` expects.
///
/// A joint with no `.L`/`.R` counterpart in the same skeleton is left out of
/// the map entirely, which is [mirrorWeights]'s own default for a joint
/// meant to stay itself.
Map<int, int> jointMirrorMapByName(
  ModelProject project,
  ProjectSkeleton skeleton,
) {
  final byName = <String, int>{
    for (var i = 0; i < skeleton.joints.length; i++)
      if (project[skeleton.joints[i]] case final ModelObject joint)
        joint.name: i,
  };
  return <int, int>{
    for (var i = 0; i < skeleton.joints.length; i++)
      if (project[skeleton.joints[i]] case final ModelObject joint)
        if (_oppositeSideName(joint.name) case final String opposite)
          if (byName[opposite] case final int j) i: j,
  };
}
