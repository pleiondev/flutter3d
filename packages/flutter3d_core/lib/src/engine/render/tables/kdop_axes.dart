/// The axes of the temporal resolve's k-DOP clip — `N4`.
///
/// A k-DOP bounds the colours of a pixel's neighbourhood by k/2 slabs, one
/// per axis, where a box is the three slabs of the colour space's own axes.
/// Each set here starts with those three, so a k-DOP is never looser than
/// the box, and the rest were chosen by the optimiser published with Ikkala,
/// Lauttia, Jääskeläinen and Mäkitalo, "k-DOP Clipping: Robust Ghosting
/// Mitigation in Temporal Antialiasing", SIGGRAPH Asia 2024 Technical
/// Communications (`github.com/vga-group/taa-kdop-optimizer`, MIT No
/// Attribution): the axes that bound a unit sphere most tightly with the
/// three fixed, which assumes nothing about the scene.
///
///   * [kdop32Axes] is the paper's own 32-DOP, copied from the repository's
///     `kdop_clipping.glsl`.
///   * [kdop16Axes] and [kdop8Axes] are `sphere_optimizer 8 1 0 0 0 1 0 0 0 1`
///     and `sphere_optimizer 4 1 0 0 0 1 0 0 0 1` from that repository, run
///     once (the optimiser is seeded by the C library's default and gives
///     these every time).
///
/// Written by hand rather than generated: they are three short lists, and a
/// generator would be the optimiser itself.
library;

import '../render_settings.dart' show ClipAxis;

/// Four axes: the box and one diagonal.
const List<ClipAxis> kdop8Axes = <ClipAxis>[
  ClipAxis(x: 1.0, y: 0.0, z: 0.0),
  ClipAxis(x: 0.0, y: 1.0, z: 0.0),
  ClipAxis(x: 0.0, y: 0.0, z: 1.0),
  ClipAxis(x: -0.706924, y: 0.0, z: -0.707289),
];

/// Eight axes.
const List<ClipAxis> kdop16Axes = <ClipAxis>[
  ClipAxis(x: 1.0, y: 0.0, z: 0.0),
  ClipAxis(x: 0.0, y: 1.0, z: 0.0),
  ClipAxis(x: 0.0, y: 0.0, z: 1.0),
  ClipAxis(x: 0.488292, y: 0.487593, z: -0.723757),
  ClipAxis(x: -0.706715, y: -0.707498, z: 0.0),
  ClipAxis(x: -0.584890, y: 0.585777, z: -0.561043),
  ClipAxis(x: -0.585556, y: 0.585554, z: 0.560581),
  ClipAxis(x: -0.488051, y: -0.487538, z: -0.723957),
];

/// Sixteen axes, the paper's 32-DOP.
const List<ClipAxis> kdop32Axes = <ClipAxis>[
  ClipAxis(x: 1.0, y: 0.0, z: 0.0),
  ClipAxis(x: 0.0, y: 1.0, z: 0.0),
  ClipAxis(x: 0.0, y: 0.0, z: 1.0),
  ClipAxis(x: 0.820081, y: 0.456727, z: -0.344773),
  ClipAxis(x: 0.540295, y: 0.829202, z: 0.143195),
  ClipAxis(x: 0.255800, y: 0.841084, z: -0.476597),
  ClipAxis(x: -0.406935, y: -0.389062, z: 0.826459),
  ClipAxis(x: -0.826708, y: -0.382923, z: -0.412219),
  ClipAxis(x: 0.260942, y: -0.577482, z: 0.773578),
  ClipAxis(x: 0.254398, y: 0.637821, z: 0.726957),
  ClipAxis(x: 0.310900, y: -0.728083, z: -0.610930),
  ClipAxis(x: 0.798513, y: -0.556827, z: -0.228738),
  ClipAxis(x: 0.673383, y: -0.163602, z: -0.720964),
  ClipAxis(x: -0.813922, y: 0.369658, z: -0.448201),
  ClipAxis(x: 0.477650, y: -0.853722, z: 0.207384),
  ClipAxis(x: -0.554854, y: -0.041550, z: -0.830910),
];
