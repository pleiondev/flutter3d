import 'package:flutter3d_core/flutter3d_core.dart' show MeshNode;

/// How brightly a beacon glows, linear, on its brightest channel.
///
/// Chosen to read from the far end of an unlit room without becoming a lamp:
/// a way out is a place, not a light source, and nothing in a dark level is
/// meant to be brighter than a torch.
const double beaconGlow = 0.40;

/// Makes what already glows in [meshes] glow at [brightness]: an objective a
/// player can find in the dark.
///
/// **Why it exists.** An exit rendered in a dark room, and again with the
/// exit hidden, differed in fifty-four pixels out of a hundred and twenty
/// thousand: iron at 0.17 in a corner no light reaches is the same black as
/// the wall behind it, so what the player met at the end of the level was a
/// slab. The model gave its inside a glow, at 0.05, which is a glow only a
/// light meter finds.
///
/// **Only what already emits.** The part a modeller made glow is the part
/// that is raised; the frame round it keeps reading as its material. An
/// object whose frame emitted too would be a rectangle of light with no
/// shape to it.
///
/// **Normalised, not multiplied**, so running it twice over materials an
/// instance shares between its own parts leaves the same brightness rather
/// than a brighter one.
///
/// **Only ever call this on materials the instance owns.** An asset's own
/// materials are shared with every other instance of it, an editor's marks
/// included.
void lightBeacon(List<MeshNode> meshes, {double brightness = beaconGlow}) {
  for (final mesh in meshes) {
    final glow = mesh.material.emissive;
    final brightest = <double>[
      glow.r,
      glow.g,
      glow.b,
    ].reduce((double a, double b) => a > b ? a : b);
    if (brightest <= 0.0) continue;
    mesh.material.emissive = glow.scaled(brightness / brightest);
  }
}
