/// Whether a shape has been keyed at the timeline's current frame — screen
/// 15's own key dot (`ui/morphs_panel.dart`), pulled out where it can be
/// tested without a widget, the same reason `animation_wiring.dart`'s own
/// row is a plain function rather than a method on some screen state.
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// Whether [objectId]'s own `weights` track in [clip] carries a keyframe at
/// [frame] (given [fps]) — [KeyTable.frameOfTime] compared on both sides
/// rather than the raw times themselves, since a time that has been through
/// `AnimationTrack`'s own `Float32List` once no longer compares equal, bit
/// for bit, to a freshly computed `frame / fps` (`key_table.dart`'s own note
/// on why `KeyTable.setKey` needs a tolerance rather than `==` for the
/// identical reason).
///
/// **One boolean for the whole object, not one per shape.** `KeyShape`
/// writes every one of an object's own shape weights into the same key at
/// the same instant (`shape_commands.dart`'s own `KeyShape.apply`), so an
/// object carries exactly one `weights` track and there is exactly one
/// answer to "is there a key on this frame" — the same answer every row
/// `MorphsPanel` draws its own dot from.
bool hasShapeKeyAtFrame({
  required ProjectClip? clip,
  required int objectId,
  required int frame,
  required double fps,
}) {
  final ProjectClip? animated = clip;
  if (animated == null) return false;
  for (final ProjectTrack track in animated.tracks) {
    if (track.objectId != objectId) continue;
    if (track.track.path != AnimationPath.weights) continue;
    final KeyTable table = KeyTable.fromAnimationTrack(track.track);
    for (final Key key in table.keys) {
      if (KeyTable.frameOfTime(key.time, fps) == frame) return true;
    }
    return false;
  }
  return false;
}
