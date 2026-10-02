import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// Laboratory glass as surfaces of revolution.
///
/// **Almost everything on a bench is round**, so none of it is modelled: each
/// piece is half of its outline, a profile in the (radius, height) plane
/// ordered bottom to top, swept round the Y axis by [LatheShape]. Bottom to
/// top is what makes the normals face out. A repeated point is a hard edge,
/// which is how a lip or a base gets a crisp rim instead of a rounded one.

/// The radius of a test tube's wall, which its label and liquid follow.
const double tubeRadius = 0.08;

/// A test tube's outside: a hemispherical bottom, a straight wall and a
/// slight flare at the mouth. [glassWall] gives it its thickness and rim.
List<Vector2> tubeProfile({double radius = tubeRadius, double height = 0.9}) =>
    <Vector2>[
      ..._roundBottom(radius),
      Vector2(radius, height),
      Vector2(radius * 1.06, height + 0.01),
    ];

/// A test tube's liquid: the same bottom a little inside the glass, cut at
/// [level] and closed with a meniscus.
List<Vector2> tubeLiquidProfile(double level, {double radius = 0.074}) =>
    <Vector2>[..._roundBottom(radius), ...meniscus(radius, level)];

/// The top of a liquid standing at [level] in glass of [radius]: water wets
/// glass, so it climbs the wall a few millimetres and dips towards the
/// middle. A flat cap reads as a solid; the curve and the bright line it
/// catches where it meets the wall are what make it read as liquid.
List<Vector2> meniscus(double radius, double level, {double rise = 0.008}) =>
    <Vector2>[
      Vector2(radius, level + rise),
      Vector2(radius, level + rise),
      Vector2(radius * 0.88, level + rise * 0.4),
      Vector2(radius * 0.66, level + rise * 0.12),
      Vector2(radius * 0.33, level + rise * 0.02),
      Vector2(0, level),
    ];

List<Vector2> _roundBottom(double radius) => <Vector2>[
  for (var i = 0; i <= 8; i++)
    Vector2(
      radius * math.sin(i / 16 * math.pi),
      radius - radius * math.cos(i / 16 * math.pi),
    ),
];

/// A beaker: a flat base, a straight wall and a flared rim.
List<Vector2> beakerProfile() => <Vector2>[
  Vector2(0, 0),
  Vector2(0.2, 0),
  Vector2(0.2, 0),
  Vector2(0.2, 0.42),
  Vector2(0.218, 0.44),
];

/// An Erlenmeyer flask: a flat base, a cone and a neck.
List<Vector2> flaskProfile() => <Vector2>[
  Vector2(0, 0),
  Vector2(0.26, 0),
  Vector2(0.26, 0),
  Vector2(0.27, 0.02),
  Vector2(0.09, 0.42),
  Vector2(0.075, 0.46),
  Vector2(0.075, 0.62),
  Vector2(0.09, 0.62),
  Vector2(0.09, 0.635),
];

/// The flask's liquid up to [level], which may be anywhere on the cone.
List<Vector2> flaskLiquidProfile(double level) {
  // The cone runs from radius 0.262 at 0.02 to 0.09 at 0.42, a hair inside
  // the glass.
  final t = ((level - 0.02) / 0.4).clamp(0.0, 1.0);
  final top = 0.255 + (0.085 - 0.255) * t;
  return <Vector2>[
    Vector2(0, 0.004),
    Vector2(0.255, 0.004),
    Vector2(0.255, 0.004),
    Vector2(0.255, 0.02),
    ...meniscus(top, level),
  ];
}

/// A graduated cylinder: a wide foot, then a long narrow tube.
List<Vector2> cylinderProfile() => <Vector2>[
  Vector2(0, 0),
  Vector2(0.14, 0),
  Vector2(0.14, 0),
  Vector2(0.14, 0.03),
  Vector2(0.14, 0.03),
  Vector2(0.056, 0.03),
  Vector2(0.056, 0.03),
  Vector2(0.056, 0.86),
  Vector2(0.07, 0.88),
];

/// Liquid standing on a flat floor at [floor]: a disc of [radius] raised to
/// [level], with a meniscus on top.
List<Vector2> flatLiquidProfile(double radius, double floor, double level) =>
    <Vector2>[
      Vector2(0, floor),
      Vector2(radius, floor),
      Vector2(radius, floor),
      ...meniscus(radius, level),
    ];

/// Where a tube's label starts and ends, and how much of the turn it covers.
const double labelFrom = 0.52;
const double labelTo = 0.66;
const double labelWrap = 3.4; // about 195 degrees

/// Width over height of the label as it sits on the glass: the arc it covers
/// over its height. The picture drawn for it must have the same proportions,
/// or the text is squashed one way and stretched the other: a wide picture
/// on a tall strip is what made the first labels look pulled upwards.
double labelAspect({
  double radius = tubeRadius,
  double from = labelFrom,
  double to = labelTo,
  double wrap = labelWrap,
}) => (radius + 0.002) * wrap / (to - from);

/// A label wrapped round part of a tube: a strip of the same surface of
/// revolution, just outside the glass.
///
/// **This is why a label needs no decal.** A lathe's u runs with the angle
/// and its v with the distance along the profile, so on a strip of it a
/// texture lands edge to edge with no stretching. [wrap] is how much of the
/// turn it covers, centred on [facing]. Like a real label it goes more than
/// half way round, so the paper shows from the side and nearly from behind;
/// the writing stays in the middle of the card, where it faces the bench's
/// front.
LatheShape labelBand({
  double radius = tubeRadius,
  double from = labelFrom,
  double to = labelTo,
  double facing = math.pi / 2,
  double wrap = labelWrap,
}) => LatheShape(
  name: 'label',
  segments: 24,
  profile: <Vector2>[
    Vector2(radius + 0.002, from),
    Vector2(radius + 0.002, to),
  ],
  startAngle: facing - wrap / 2,
  sweepAngle: wrap,
);

/// Clear glass: the layered model, transmission and an index of 1.5.
Material glass() => Material(
  name: 'glass',
  lighting: LightingModel.pbrLayered,
  baseColor: Vector4(0.92, 0.97, 1.0, 0.12),
  roughness: 0.04,
  alphaMode: MaterialAlphaMode.blend,
  doubleSided: true,
  // A few millimetres of thickness, so what is behind the glass is bent a
  // little rather than seen straight through a sheet with no depth.
  extensions: MaterialExtensions(transmission: 0.95, ior: 1.5, thickness: 0.01),
);

/// A solution: clear liquid that light passes through, tinted by what it
/// holds, with water's index of refraction.
///
/// The colour goes into the attenuation as well as the base colour, so a
/// thicker layer is a deeper colour, as it is in a real tube: the round
/// bottom and the edges read darker than the middle.
Material liquid(Vector3 colour) => Material(
  name: 'liquid',
  lighting: LightingModel.pbrLayered,
  baseColor: Vector4(colour.x, colour.y, colour.z, 0.8),
  roughness: 0.03,
  alphaMode: MaterialAlphaMode.blend,
  // Blended surfaces leave the depth buffer alone, so the see-through
  // tabletop, drawn after the liquids, laid itself over their lower half.
  // Written, the liquid's depth keeps the table behind it.
  depthWrite: true,
  extensions: MaterialExtensions(
    ior: 1.33,
    transmission: 0.35,
    thickness: 0.06,
    attenuationColor: colour,
    attenuationDistance: 0.08,
    specular: 1.0,
    // A wet surface: a clear coat over the colour gives the sharp highlight
    // a liquid has and a painted solid does not.
    clearcoat: 1.0,
    clearcoatRoughness: 0.02,
  ),
);

/// Paper, wearing [label] once it has been drawn.
Material paper([TextureHandle? label]) =>
    Material(name: 'label', albedo: label, roughness: 0.8);

/// How the bench is drawn: under [labSky]. The tabletop's reflections are
/// mirrored geometry (see `Bench`), so no screen-space pass is needed.
final RenderSettings benchSettings = RenderSettings(sky: labSky);

/// The room the bench stands in, as a sky: bright overhead, a pale horizon
/// and a darker floor. Glass shows almost nothing of itself; it shows what is
/// round it, and with nothing round it every tube read as dark plastic. This
/// gives the glass something to reflect and the edges their light.
final SkySettings labSky = SkySettings(
  enabled: true,
  zenith: Vector3(0.82, 0.86, 0.92),
  horizon: Vector3(0.62, 0.66, 0.72),
  nadir: Vector3(0.18, 0.19, 0.22),
  directionToSun: Vector3(0.5, 1.0, 0.6),
  sunColor: Vector3(1.0, 0.97, 0.92),
  glowStrength: 0.0,
);

/// [outer] given a wall of [thickness]: up the outside, over a rounded rim
/// and back down the inside, as one closed outline.
///
/// **A single surface has no rim.** Swept as it is, an outline ends in a
/// bare edge, and seen from above the mouth of a tube read as a flat paper
/// ring. Real glass has a wall: the inside is the outline moved in along its
/// normal, walked top to bottom so its normals face the cavity, and the two
/// meet in a half circle that catches the light.
List<Vector2> glassWall(List<Vector2> outer, {double thickness = 0.004}) {
  // Repeated points mark hard edges; for offsetting, each point's normal
  // comes from its nearest neighbours that are somewhere else.
  final points = <Vector2>[
    for (var i = 0; i < outer.length; i++)
      if (i == 0 || (outer[i] - outer[i - 1]).length > 1e-9) outer[i],
  ];
  Vector2 normal(int i) {
    final before = points[math.max(i - 1, 0)];
    final after = points[math.min(i + 1, points.length - 1)];
    final tangent = (after - before)..normalize();
    return Vector2(tangent.y, -tangent.x); // outward for bottom-to-top
  }

  final inner = <Vector2>[
    for (var i = points.length - 1; i >= 0; i--)
      () {
        final p = points[i] - normal(i) * thickness;
        return Vector2(math.max(p.x, 0), p.y);
      }(),
  ];
  final top = points.last;
  final topInner = inner.first;
  final centre = (top + topInner) * 0.5;
  final across = (top - topInner) * 0.5;
  final up = Vector2(-across.y, across.x);
  final rim = <Vector2>[
    for (var k = 1; k < 6; k++)
      centre +
          across * math.cos(k / 6 * math.pi) +
          up * math.sin(k / 6 * math.pi),
  ];
  return <Vector2>[...points, ...rim, ...inner];
}
