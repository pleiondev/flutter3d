/// Pure decisions the material panel makes, pulled out so a `test()` can ask
/// them directly — the same split `properties_sections.dart` already draws
/// for which section a mode shows.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// The material row [object] is painted with, or null when it has none.
///
/// [ModelObject.materialSlots] can in principle name more than one row; the
/// panel edits the first, the same slot [MaterialPool.forObject] paints the
/// viewport with.
int? activeMaterialSlot(ModelObject object) =>
    object.materialSlots.isEmpty ? null : object.materialSlots.first;

/// Whether a metallic slider bound to [lighting] should respond at all.
///
/// A dielectric-only shader such as Lambert has no metallic parameter to
/// bind — [LightingModel.usesMetallic] is the engine's own answer to which
/// shaders do — so a slider left active there would move a number nothing
/// reads.
bool metallicIsMeaningful(LightingModel lighting) => lighting.usesMetallic;

/// The shader [surface]'s own fields should be shown for.
///
/// **Derived from [SurfaceMaterial.unlit], the one shader bit a project
/// material actually carries today.** Nothing in `ProjectMaterial` or
/// `SurfaceMaterial` names a lighting model the way a linked `.fmat`'s own
/// `MaterialDocument.lighting` does — seeing that field's own doc comment —
/// so there is no way yet for a material authored inside this project to
/// read back as Lambert; [bindSurfaceMaterial] itself always paints with
/// [LightingModel.pbr] unless a material is unlit. [metallicIsMeaningful] is
/// written against [LightingModel] rather than against this function so that
/// the day a material gets a shader field of its own (`mat-04`'s fuller
/// row), the gate needs no change — only this mapping does.
LightingModel lightingModelOf(SurfaceMaterial surface) =>
    surface.unlit ? LightingModel.unlit : LightingModel.pbr;

/// The row [bytes] already sits at in [images], or null when nothing there
/// matches — the same content match [AddImage] itself makes before it
/// appends a new row.
///
/// The material panel calls [AddImage] and then needs to know which slot to
/// point [SetTexture] at; [AddImage] does not hand its row back (see its own
/// doc comment on why a material or an image never carries an id of its
/// own), so this is the same lookup done from the caller's side, against the
/// project as it reads immediately after that command lands.
int? indexOfImageBytes(List<EncodedImage> images, List<int> bytes) {
  for (var i = 0; i < images.length; i++) {
    final EncodedImage each = images[i];
    if (each.bytes.length != bytes.length) continue;
    var same = true;
    for (var j = 0; j < bytes.length; j++) {
      if (each.bytes[j] != bytes[j]) {
        same = false;
        break;
      }
    }
    if (same) return i;
  }
  return null;
}
