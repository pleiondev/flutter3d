import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';

/// Laboratory glass as surfaces of revolution.
///
/// **Almost everything on a bench is round**, so none of it is modelled: each
/// piece is half of its outline, a profile in the (radius, height) plane
/// ordered bottom to top, swept round the Y axis by [LatheShape]. Bottom to
/// top is what makes the normals face out. A repeated point is a hard edge,
/// which is how a lip or a base gets a crisp rim instead of a rounded one.

/// The radius of a test tube's wall, which its label follows: sixteen
/// millimetres across, as a real one is. Everything here is in metres and
/// life size — the liquid in it is worked out in SI (`flutter3d_physics`),
/// and a bench ten times the size would pour like one.
const double tubeRadius = 0.008;

/// How thick the glass is.
const double glassThickness = 0.0005;

/// A test tube's outside: a hemispherical bottom, a straight wall and a
/// slight flare at the mouth. [glassWall] gives it its thickness and rim.
List<Vector2> tubeProfile({double radius = tubeRadius, double height = 0.09}) =>
    <Vector2>[
      ..._roundBottom(radius),
      Vector2(radius, height),
      Vector2(radius * 1.06, height + 0.001),
    ];

/// A test tube's inside: the same bottom a glass's thickness in, straight
/// up to the mouth.
List<Vector2> tubeInside({double radius = tubeRadius, double height = 0.09}) {
  final r = radius - glassThickness;
  return <Vector2>[
    for (final p in _roundBottom(r)) Vector2(p.x, p.y + glassThickness),
    Vector2(r, height - 0.001),
  ];
}

List<Vector2> _roundBottom(double radius) => <Vector2>[
  for (var i = 0; i <= 8; i++)
    Vector2(
      radius * math.sin(i / 16 * math.pi),
      radius - radius * math.cos(i / 16 * math.pi),
    ),
];

/// A beaker: a flat base, a straight wall and a flared rim; fifty
/// millilitres.
List<Vector2> beakerProfile() => <Vector2>[
  Vector2(0, 0),
  Vector2(0.02, 0),
  Vector2(0.02, 0),
  Vector2(0.02, 0.042),
  Vector2(0.0218, 0.044),
];

/// The beaker's inside.
List<Vector2> beakerInside() => <Vector2>[
  Vector2(0, glassThickness),
  Vector2(0.02 - glassThickness, glassThickness),
  Vector2(0.02 - glassThickness, 0.041),
];

/// An Erlenmeyer flask: a flat base, a cone and a neck.
List<Vector2> flaskProfile() => <Vector2>[
  Vector2(0, 0),
  Vector2(0.026, 0),
  Vector2(0.026, 0),
  Vector2(0.027, 0.002),
  Vector2(0.009, 0.042),
  Vector2(0.0075, 0.046),
  Vector2(0.0075, 0.062),
  Vector2(0.009, 0.062),
  Vector2(0.009, 0.0635),
];

/// The flask's inside: the floor, the cone and the neck, a glass's
/// thickness in.
List<Vector2> flaskInside() => <Vector2>[
  Vector2(0, glassThickness),
  Vector2(0.0255, glassThickness),
  Vector2(0.0255, 0.002),
  Vector2(0.0085, 0.042),
  Vector2(0.007, 0.046),
  Vector2(0.007, 0.061),
];

/// A graduated cylinder's glass: a long narrow tube standing on [cylinderFoot].
List<Vector2> cylinderProfile() => <Vector2>[
  Vector2(0, 0.003),
  Vector2(0.0056, 0.003),
  Vector2(0.0056, 0.003),
  Vector2(0.0056, 0.086),
  Vector2(0.007, 0.088),
];

/// The cylinder's inside.
List<Vector2> cylinderInside() => <Vector2>[
  Vector2(0, 0.0034),
  Vector2(0.0051, 0.0034),
  Vector2(0.0051, 0.085),
];

/// The cylinder's foot: a flat hexagonal slab, swept with six segments.
///
/// **It was glass and read as a puddle.** A clear disc lying flat on the
/// bench shows the bench through it and the reflection under it, and from
/// above that is exactly what spilt water looks like. Real cylinders stand
/// on a hexagonal plastic foot, which also stops them rolling away.
List<Vector2> cylinderFoot() => <Vector2>[
  Vector2(0, 0),
  Vector2(0.014, 0),
  Vector2(0.014, 0),
  Vector2(0.014, 0.003),
  Vector2(0.014, 0.003),
  Vector2(0, 0.003),
];

/// The foot's plastic: opaque, a little glossy, laboratory blue.
RenderMaterial footPlastic() => RenderMaterial(
  name: 'foot',
  baseColor: LinearColor.fromSrgb(0.2, 0.42, 0.8, 1),
  roughness: 0.45,
);

/// Where a tube's label starts and ends, and how much of the turn it covers.
const double labelFrom = 0.052;
const double labelTo = 0.066;
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
}) => (radius + 0.0002) * wrap / (to - from);

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
    Vector2(radius + 0.0002, from),
    Vector2(radius + 0.0002, to),
  ],
  startAngle: facing - wrap / 2,
  sweepAngle: wrap,
);

/// Clear glass: the layered model, transmission and an index of 1.5.
RenderMaterial glass() => RenderMaterial(
  name: 'glass',
  lighting: LightingModel.pbrLayered,
  // **Seen by what it reflects, and how much is a matter of taste.** A thin
  // pane that transmits is laid over what is behind it and lets through
  // what it does not reflect (see `g_pane` in the engine), so its alpha
  // weighs what it reflects and adds. At 0.22 an empty tube was a ghost; at
  // one, with every reflection whole, the glass read heavier than the
  // liquids in it. Halfway is what the bench is lit with. The tint is
  // laboratory glass's faint green-grey.
  baseColor: LinearColor.fromSrgb(0.96, 0.985, 0.975, 0.55),
  roughness: 0.03,
  alphaMode: MaterialAlphaMode.blend,
  doubleSided: true,
  // Thin-walled, as glTF means it: no thickness. A tube's wall is a few
  // millimetres of glass round air, and given a volume the engine's caustics
  // would follow light through it as through a solid glass rod.
  // Transmission one: clear glass absorbs next to nothing over a wall, and
  // what it does lose to reflection the Fresnel term already counts.
  extensions: MaterialExtensions(transmission: 1.0, ior: 1.5, specular: 1.0),
);

/// A solution: clear liquid that light passes through, coloured by what it
/// holds, with water's index of refraction.
///
/// **It reads as liquid because of what it does to the light, not its
/// paint.** Fully transmitting, so what is behind it shows through, bent;
/// a convex body ([MaterialExtensions.convexVolume]) [depth] across, so the
/// path through it, and with it the colour and the bend, is deepest down the
/// middle and fades to the silhouette, where a painted cylinder stays one
/// flat colour to its edge; and a wet, glossy surface with a clear coat. The
/// colour is the volume's: [color], in sRGB as it was picked, after [fade]
/// of it — decoded to linear light for the attenuation, which is Beer and
/// Lambert's and so linear — with a base nearly white so it is not given
/// twice.
RenderMaterial liquid(Vector3 color, {double depth = 0.0148}) => RenderMaterial(
  name: 'liquid',
  lighting: LightingModel.pbrLayered,
  baseColor: LinearColor.fromSrgb(
    0.75 + 0.25 * color.x,
    0.75 + 0.25 * color.y,
    0.75 + 0.25 * color.z,
    1.0,
  ),
  roughness: 0.02,
  alphaMode: MaterialAlphaMode.blend,
  // Blended surfaces leave the depth buffer alone, so the see-through
  // tabletop, drawn after the liquids, laid itself over their lower half.
  // Written, the liquid's depth keeps the table behind it.
  depthWrite: true,
  extensions: MaterialExtensions(
    ior: 1.33,
    transmission: 1.0,
    thickness: depth,
    convexVolume: true,
    attenuationColor: LinearColor.fromSrgb(color.x, color.y, color.z, 1.0),
    attenuationDistance: fade,
    specular: 1.0,
    clearcoat: 1.0,
    clearcoatRoughness: 0.0,
  ),
);

/// How far light goes through a solution before it is the solution's colour,
/// in metres: 0.03, three centimetres, about two tubes across.
const double fade = 0.03;

/// Paper, wearing [label] once it has been drawn.
RenderMaterial paper([TextureHandle? label]) =>
    RenderMaterial(name: 'label', albedo: label, roughness: 0.8);

/// How the bench is drawn: under [labSky], with see-through casters shading
/// the sun by what their material lets through
/// (`ShadowSettings.translucentCasters`): the glass casts a faint shadow with
/// darker edges, and each liquid a shadow of its own colour. The tabletop's
/// reflections are mirrored geometry (see `Bench`), so no screen-space pass
/// is needed.
///
/// The shadows are fitted to a bench, not a level: sixty centimetres of view
/// rather than sixty metres, as far as the camera goes, and a normal offset
/// of two millimetres rather than two centimetres, which on glass this size
/// is most of a tube. The map is twice the default's edge: at a metre and
/// 1024 texels a tube's shadow edge stepped by most of a millimetre, which a
/// close look at a sixteen-millimetre tube shows as stairs.
final RenderSettings benchSettings = RenderSettings(
  sky: labSky,
  shadows: const ShadowSettings(
    translucentCasters: true,
    resolution: 2048,
    viewDistance: 0.6,
    normalOffset: 0.002,
  ),
);

/// [benchSettings] with the engine's own caustics on, for a `Bench` made with
/// `photons: true`.
final RenderSettings photonSettings = RenderSettings(
  sky: labSky,
  shadows: const ShadowSettings(
    translucentCasters: true,
    caustics: true,
    causticPhotons: 128,
    resolution: 2048,
    viewDistance: 0.6,
    normalOffset: 0.002,
  ),
);

/// The room the bench stands in, as a sky: bright overhead, a pale horizon
/// and a darker floor. Glass shows almost nothing of itself; it shows what is
/// round it, and with nothing round it every tube read as dark plastic. This
/// gives the glass something to reflect and the edges their light.
final SkySettings labSky = SkySettings(
  enabled: true,
  zenith: LinearColor(0.82, 0.86, 0.92),
  horizon: LinearColor(0.62, 0.66, 0.72),
  nadir: LinearColor(0.18, 0.19, 0.22),
  directionToSun: Vector3(0.5, 1.0, 0.6),
  sunColor: LinearColor(1.0, 0.97, 0.92),
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
List<Vector2> glassWall(
  List<Vector2> outer, {
  double thickness = glassThickness,
}) {
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
  final center = (top + topInner) * 0.5;
  final across = (top - topInner) * 0.5;
  final up = Vector2(-across.y, across.x);
  final rim = <Vector2>[
    for (var k = 1; k < 6; k++)
      center +
          across * math.cos(k / 6 * math.pi) +
          up * math.sin(k / 6 * math.pi),
  ];
  return <Vector2>[...points, ...rim, ...inner];
}
