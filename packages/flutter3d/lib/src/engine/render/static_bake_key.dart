/// What the static half of the cube atlas was baked with, and when that has to
/// be drawn again.
///
/// **The bake used to outlive the settings that made it.** The static atlas
/// holds everything in a scene that never moves — a dungeon's walls — drawn once
/// and kept for as many frames as the atlas rows stay with the same lights.
/// That is the whole reason a room full of torches is affordable. But "the rows
/// did not change" was the only thing that could make it redraw, so a setting
/// that decides *what the pass puts in it* could be changed and nothing
/// happened: the atlas went on holding what the previous setting produced, for
/// the rest of the run.
///
/// How that was found is worth keeping, because nothing in the code looked
/// wrong. A probe drew the crypt twice on Impeller with opposite `casterFaces`
/// and got two frames identical to the pixel — 419 pixels different from a
/// no-shadow frame, the same 419 both times. A setting with no visible effect
/// and a setting that never arrives look the same from the outside; only a
/// second measurement with the fix in place tells them apart, and that one
/// moves 647.
///
/// Split out of the frame graph so the rule can be read and tested without a
/// device: whether to bake is arithmetic on a handful of numbers, and the pass
/// that follows it is the part that needs a GPU.
library;

import 'shadow_settings.dart';

/// The settings a static bake depends on.
///
/// **What is absent is as deliberate as what is here.** Bias, normal offset,
/// softness, strength and the light radius are all read per fragment when the
/// atlas is *sampled*, so changing one of them needs no redraw at all. Baking
/// again for a bias would redraw every occupied row — six views of the level's
/// static geometry apiece — to produce exactly the pixels already there.
///
/// Only what the pass itself reads belongs in the key:
///
/// * [faces] decides which side of a caster is recorded, so it decides every
///   stored distance;
/// * [padding] widens the volume each face is drawn through, which moves the
///   far plane the distances are normalised against;
/// * the cube resolution is the tile size, and a tile of a different size is a
///   different picture even of the same geometry.
extension type const StaticBakeKey._(
  (int faces, double padding, int resolution) it
) {
  StaticBakeKey.of(ShadowSettings settings)
    : this._((
        settings.casterFaces.index,
        settings.depthPadding,
        settings.cubeResolution,
      ));
}

/// Whether this frame has to draw the static atlas.
///
/// [rowsChanged] is the slot allocator's verdict — a row changed hands, or its
/// owner moved far enough that the walls baked for it are walls seen from
/// somewhere else. [baked] is false before the first bake and after the atlas
/// is reallocated. [was] is the key the standing bake was drawn with, null when
/// there is none.
bool shouldBakeStatic({
  required bool rowsChanged,
  required bool baked,
  required StaticBakeKey? was,
  required StaticBakeKey now,
}) => rowsChanged || !baked || was != now;
