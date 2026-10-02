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

/// A test tube: a hemispherical bottom, a straight wall and a small lip.
List<Vector2> tubeProfile({double radius = tubeRadius, double height = 0.9}) =>
    <Vector2>[
      ..._roundBottom(radius),
      Vector2(radius, height),
      Vector2(radius * 1.12, height),
      Vector2(radius * 1.12, height + 0.012),
    ];

/// A test tube's liquid: the same bottom a little inside the glass, cut at
/// [level] and closed with a flat top.
List<Vector2> tubeLiquidProfile(double level, {double radius = 0.074}) =>
    <Vector2>[
      ..._roundBottom(radius),
      Vector2(radius, level),
      Vector2(radius, level),
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
    Vector2(top, level),
    Vector2(top, level),
    Vector2(0, level),
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
/// [level] and capped. Hard edges at both rims.
List<Vector2> flatLiquidProfile(double radius, double floor, double level) =>
    <Vector2>[
      Vector2(0, floor),
      Vector2(radius, floor),
      Vector2(radius, floor),
      Vector2(radius, level),
      Vector2(radius, level),
      Vector2(0, level),
    ];

/// A label wrapped round part of a tube: a strip of the same surface of
/// revolution, just outside the glass.
///
/// **This is why a label needs no decal.** A lathe's u runs with the angle
/// and its v with the distance along the profile, so on a strip of it a
/// texture lands edge to edge with no stretching. [wrap] is how much of the
/// turn it covers, centred on [facing]; past about a quarter turn its edges
/// go round the side and a long formula loses its ends.
LatheShape labelBand({
  double radius = tubeRadius,
  double from = 0.5,
  double to = 0.72,
  double facing = math.pi / 2,
  double wrap = 1.6,
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
  extensions: MaterialExtensions(transmission: 0.95, ior: 1.5),
);

/// A solution: its colour is the whole of it.
Material liquid(Vector3 colour) => Material(
  name: 'liquid',
  baseColor: Vector4(colour.x, colour.y, colour.z, 0.85),
  roughness: 0.15,
  alphaMode: MaterialAlphaMode.blend,
);

/// Paper, wearing [label] once it has been drawn.
Material paper([TextureHandle? label]) =>
    Material(name: 'label', albedo: label, roughness: 0.8);
