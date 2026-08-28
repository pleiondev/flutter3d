import 'package:flutter3d/flutter3d.dart';

/// How brightly the opening glows, linear, on its brightest channel.
///
/// Chosen to read from the far end of an unlit room without becoming a lamp:
/// the arch is a way out, not a light source, and nothing else in the crypt is
/// meant to be brighter than a torch.
const double kWayOutGlow = 0.40;

/// Makes the inside of the arch a light rather than a hole.
///
/// **The frame was invisible, and measurably so.** Rendered in the crypt, and
/// again with the doorway hidden, the two frames differ in fifty-four pixels out
/// of a hundred and twenty thousand: iron at 0.17 in a corner no torch reaches
/// is the same black as the wall behind it, so what the player met at the end of
/// the level was a slab.
///
/// `make_models.py` already meant this to be handled — its `exit_arch` gives the
/// dark inside a glow "so the frame is not a hole in an unlit wall, which is a
/// hole nobody can find" — but the value it uses is 0.05 at its brightest, which
/// is a glow only a light meter finds.
///
/// **Only what already emits.** The panel is the part with a glow, and raising
/// only that keeps the iron reading as iron: an arch whose frame emitted too
/// would be a rectangle of light with no shape to it.
///
/// Normalised to [kWayOutGlow] rather than multiplied, so running it twice over
/// materials an instance shares between its own parts leaves the same
/// brightness rather than a brighter one.
///
/// **Only ever call this on materials the instance owns.** The editor draws this
/// same file as one of its marks, and the asset's own materials are shared.
void lightTheWayOut(List<MeshNode> meshes) {
  for (final mesh in meshes) {
    final glow = mesh.material.emissive;
    final brightest = <double>[
      glow.x,
      glow.y,
      glow.z,
    ].reduce((double a, double b) => a > b ? a : b);
    if (brightest <= 0.0) continue;
    glow.scale(kWayOutGlow / brightest);
  }
}
