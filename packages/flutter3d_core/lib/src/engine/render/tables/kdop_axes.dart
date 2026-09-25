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

/// Four axes: the box and one diagonal.
const List<(double, double, double)> kdop8Axes = <(double, double, double)>[
  (1.0, 0.0, 0.0),
  (0.0, 1.0, 0.0),
  (0.0, 0.0, 1.0),
  (-0.706924, 0.0, -0.707289),
];

/// Eight axes.
const List<(double, double, double)> kdop16Axes = <(double, double, double)>[
  (1.0, 0.0, 0.0),
  (0.0, 1.0, 0.0),
  (0.0, 0.0, 1.0),
  (0.488292, 0.487593, -0.723757),
  (-0.706715, -0.707498, 0.0),
  (-0.584890, 0.585777, -0.561043),
  (-0.585556, 0.585554, 0.560581),
  (-0.488051, -0.487538, -0.723957),
];

/// Sixteen axes, the paper's 32-DOP.
const List<(double, double, double)> kdop32Axes = <(double, double, double)>[
  (1.0, 0.0, 0.0),
  (0.0, 1.0, 0.0),
  (0.0, 0.0, 1.0),
  (0.820081, 0.456727, -0.344773),
  (0.540295, 0.829202, 0.143195),
  (0.255800, 0.841084, -0.476597),
  (-0.406935, -0.389062, 0.826459),
  (-0.826708, -0.382923, -0.412219),
  (0.260942, -0.577482, 0.773578),
  (0.254398, 0.637821, 0.726957),
  (0.310900, -0.728083, -0.610930),
  (0.798513, -0.556827, -0.228738),
  (0.673383, -0.163602, -0.720964),
  (-0.813922, 0.369658, -0.448201),
  (0.477650, -0.853722, 0.207384),
  (-0.554854, -0.041550, -0.830910),
];
