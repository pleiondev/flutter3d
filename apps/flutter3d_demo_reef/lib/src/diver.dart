/// The diver: a body the sea holds up as much as the water it displaces
/// weighs, pushed along by fins, trimmed by the air in a jacket that
/// shrinks as the diver goes down and swells on the way up, and breathing
/// from a tank that empties faster the deeper the breath is drawn.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'looks.dart';

/// Pascals a metre of seawater weighs, over the atmosphere's: a diver at
/// ten metres breathes air at about two atmospheres.
const double _seaPerMetre = 1025.0 * 9.81, _atmosphere = 101325.0;

/// The pressure, atmospheres, [depth] metres under the surface.
double pressureAt(double depth) =>
    1.0 + math.max(depth, 0.0) * _seaPerMetre / _atmosphere;

/// The diver and their gear.
final class Diver {
  Diver(
    this._world,
    GraphicsDevice device,
    Scene scene,
    SeabedLook floor,
    ReefModel figure,
    Vector3 at,
  ) {
    body = _world.addBody(position: at, mass: _mass);
    _world
      ..setShape(body, const NativeShape.capsule(_radius, _half))
      ..lockRotation(body);
    // A man posed swimming, drawn lying along +x the way a diver swims and
    // turned to the heading; in a full wetsuit, gloves, hood and boots,
    // which is his shirt, shorts, hair and socks gone black and his skin
    // with them everywhere below his chin, where the shirt's collar ends.
    final neoprene = Vector4(0.025, 0.028, 0.035, 1.0);
    final skin = figure.pieces.firstWhere((p) => p.name == 'Skin').colour;
    final suited = Vector4(
      neoprene.x / skin.x,
      neoprene.y / skin.y,
      neoprene.z / skin.z,
      1.0,
    );
    look = SceneNode(name: 'diver')
      ..add(
        figure.dress(
          floor,
          name: 'figure',
          recolour: (piece) => switch (piece) {
            'Shirt' || 'Pants' || 'Socks' || 'Hair' => neoprene,
            _ => null,
          },
          painted: (piece, at) =>
              piece == 'Skin' && at.x < _chin ? suited : null,
          device: device,
          roughness: 0.6,
        ),
      );
    Material under(String name, Vector4 colour) =>
        floor.under(name, colour, roughness: 0.4);
    MeshNode part(MeshData mesh, String name, Vector4 colour) => MeshNode(
      DeviceMesh.upload(device, mesh),
      under(name, colour),
      name: name,
    );
    final lying = Quaternion.axisAngle(Vector3(0, 0, 1), -math.pi / 2);
    final torso = figure.anchors['Torso']!.getTranslation();
    // On his back: the jacket's plate and bladder, and the tank strapped
    // over it with its valve by his head.
    final back = torso + Vector3(-0.12, 0.13, 0);
    look
      ..add(
        part(
          CuboidShape(size: Vector3(0.6, 0.06, 0.4)).build(),
          'jacket',
          Vector4(0.03, 0.05, 0.12, 1.0),
        )..setPositionFrom(back),
      )
      ..add(
        part(_tank(), 'tank', Vector4(1.0, 1.0, 1.0, 1.0))
          ..setRotation(lying)
          ..setPositionFrom(back + Vector3(0, 0.12, 0)),
      )
      ..add(
        part(
            MeshData.merge(<MeshData>[
              const CylinderShape(
                radiusTop: 0.025,
                radiusBottom: 0.025,
                height: 0.1,
              ).build(),
              const CylinderShape(
                radiusTop: 0.03,
                radiusBottom: 0.03,
                height: 0.03,
              ).build().transformed(
                Matrix4.compose(
                  Vector3(0, 0.03, 0),
                  Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
                  Vector3(1, 1, 1),
                ),
              ),
            ]),
            'valve',
            Vector4(0.7, 0.7, 0.72, 1.0),
          )
          ..setRotation(lying)
          ..setPositionFrom(back + Vector3(0.35, 0.12, 0)),
      );
    // On his face, the mask and its strap round his hood, and the
    // regulator in his mouth on its hose from the valve. The head's frame
    // looks along its z and up its y.
    final head = figure.anchors['Head']!;
    final face = SceneNode(name: 'face')..setLocalMatrix(head);
    face
      ..add(
        part(
          CuboidShape(size: Vector3(0.17, 0.08, 0.05)).build(),
          'mask',
          Vector4(0.02, 0.02, 0.025, 1.0),
        )..setPosition(0, 0.13, 0.1),
      )
      ..add(
        part(
          CuboidShape(size: Vector3(0.14, 0.06, 0.01)).build(),
          'glass',
          Vector4(0.3, 0.45, 0.5, 1.0),
        )..setPosition(0, 0.13, 0.126),
      )
      ..add(
        part(
          const TorusShape(
            radius: 0.1,
            tubeRadius: 0.008,
            segments: 20,
            tubeSegments: 4,
          ).build(),
          'strap',
          Vector4(0.02, 0.02, 0.025, 1.0),
        )..setPosition(0, 0.13, 0.0),
      )
      ..add(
        part(
          CuboidShape(size: Vector3(0.06, 0.05, 0.05)).build(),
          'regulator',
          Vector4(0.02, 0.02, 0.025, 1.0),
        )..setPosition(0, 0.03, 0.11),
      );
    look.add(face);
    final mouth = head.transformed3(Vector3(0, 0.03, 0.11));
    final valve = back + Vector3(0.38, 0.14, 0);
    final hose = valve - mouth;
    look.add(
      part(
          CylinderShape(
            radiusTop: 0.012,
            radiusBottom: 0.012,
            height: hose.length,
            segments: 6,
          ).build(),
          'hose',
          Vector4(0.02, 0.02, 0.025, 1.0),
        )
        ..setPositionFrom(mouth + hose * 0.5)
        ..setRotation(
          Quaternion.fromTwoVectors(Vector3(0, 1, 0), hose.normalized()),
        ),
    );
    // A fin on each foot, its blade running on along the foot's own
    // length (its y), as wide as its x and thin through its sole (its z).
    final blade = _fin();
    for (final foot in <String>['Foot.L', 'Foot.R']) {
      look.add(
        SceneNode(name: 'fin')
          ..setLocalMatrix(figure.anchors[foot]!)
          ..add(
            MeshNode(
              DeviceMesh.upload(device, blade),
              under('fin', Vector4(1.0, 1.0, 1.0, 1.0)),
              name: 'blade',
            ),
          ),
      );
    }
    scene.add(look);
  }

  /// A twelve-litre aluminium tank standing along its y, valve end up,
  /// 0.6 m long: a domed shoulder, a black rubber boot over its base and
  /// the two black cam bands that hold it to the jacket.
  static MeshData _tank() {
    MeshData lathe(List<(double, double)> profile, Vector4 colour) =>
        LatheShape(
          profile: <Vector2>[for (final (r, y) in profile) Vector2(r, y)],
          segments: 20,
        ).build().withColor(colour);
    final rubber = Vector4(0.03, 0.03, 0.035, 1.0);
    return MeshData.merge(<MeshData>[
      lathe(<(double, double)>[
        (0.0, -0.29),
        (0.07, -0.29),
        (0.088, -0.275),
        (0.09, -0.25),
        (0.09, 0.17),
        (0.086, 0.22),
        (0.072, 0.26),
        (0.048, 0.287),
        (0.022, 0.298),
        (0.0, 0.3),
      ], Vector4(0.5, 0.52, 0.54, 1.0)),
      lathe(<(double, double)>[
        (0.0, -0.305),
        (0.093, -0.305),
        (0.095, -0.18),
        (0.0, -0.18),
      ], rubber),
      for (final y in <double>[-0.04, 0.1])
        lathe(<(double, double)>[
          (0.0, y - 0.022),
          (0.094, y - 0.022),
          (0.094, y + 0.022),
          (0.0, y + 0.022),
        ], rubber),
    ]);
  }

  /// A fin in its foot's frame: a black foot pocket over the foot, then one
  /// blade running on 0.7 m, widening and thinning towards its trailing
  /// edge, dark across its faces with a yellow rail down each side.
  static MeshData _fin() {
    final rubber = Vector4(0.03, 0.03, 0.035, 1.0);
    return MeshData.merge(<MeshData>[
      _loft(
        <(double, double, double)>[
          (-0.08, 0.055, 0.04),
          (0.04, 0.065, 0.048),
          (0.16, 0.07, 0.035),
          (0.22, 0.07, 0.015),
        ],
        rubber,
        rubber,
      ).transformed(Matrix4.translationValues(0, 0, -0.01)),
      _loft(
        <(double, double, double)>[
          for (var k = 0; k <= 8; k++)
            (
              0.12 + 0.7 * k / 8,
              0.075 + 0.055 * math.sqrt(k / 8),
              0.012 - 0.008 * k / 8,
            ),
        ],
        Vector4(0.04, 0.06, 0.11, 1.0),
        Vector4(0.95, 0.72, 0.08, 1.0),
      ),
    ]);
  }

  /// A slab lofted along y through [sections], each its y, half width
  /// across x and half thickness through z: its broad faces in [face], its
  /// edges and ends in [rail], each face flat-shaded.
  static MeshData _loft(
    List<(double, double, double)> sections,
    Vector4 face,
    Vector4 rail,
  ) {
    final vertices = <double>[];
    final indices = <int>[];
    // Four corners, wound so they face [outward]; the triangle's own normal
    // is what each is shaded by.
    void quad(List<Vector3> corners, Vector3 outward, Vector4 colour) {
      final ordered =
          (corners[1] - corners[0])
                  .cross(corners[2] - corners[0])
                  .dot(outward) >=
              0
          ? corners
          : corners.reversed.toList();
      final normal = (ordered[1] - ordered[0]).cross(ordered[2] - ordered[0])
        ..normalize();
      final first = vertices.length ~/ 16;
      for (final p in ordered) {
        vertices.addAll(<double>[
          p.x, p.y, p.z, normal.x, normal.y, normal.z, 0, 0, //
          1, 0, 0, 1, colour.x, colour.y, colour.z, colour.w,
        ]);
      }
      indices.addAll(<int>[
        first,
        first + 1,
        first + 2,
        first,
        first + 2,
        first + 3,
      ]);
    }

    List<Vector3> ring((double, double, double) s) {
      final (y, w, t) = s;
      return <Vector3>[
        Vector3(-w, y, t),
        Vector3(w, y, t),
        Vector3(w, y, -t),
        Vector3(-w, y, -t),
      ];
    }

    for (var k = 0; k + 1 < sections.length; k++) {
      final a = ring(sections[k]), b = ring(sections[k + 1]);
      quad(<Vector3>[a[0], a[1], b[1], b[0]], Vector3(0, 0, 1), face);
      quad(<Vector3>[a[3], a[2], b[2], b[3]], Vector3(0, 0, -1), face);
      quad(<Vector3>[a[1], a[2], b[2], b[1]], Vector3(1, 0, 0), rail);
      quad(<Vector3>[a[0], a[3], b[3], b[0]], Vector3(-1, 0, 0), rail);
    }
    quad(ring(sections.first), Vector3(0, -1, 0), rail);
    quad(ring(sections.last), Vector3(0, 1, 0), rail);
    return MeshData(
      layout: VertexLayout.standard,
      vertices: Float32List.fromList(vertices),
      indices: Uint32List.fromList(indices),
    );
  }

  /// Body and weights, kilograms, and the capsule the sea sees: a tenth of
  /// a cubic metre, a little less than the water it would take to float
  /// the diver with the jacket empty.
  static const double _mass = 106.0, _radius = 0.17, _half = 0.45;

  /// How far along the figure, head forward, his chin is: the wetsuit's
  /// neck, past which his face shows.
  static const double _chin = 0.56;

  /// How hard the fins push at most, N: a diver finning steadily.
  static const double thrust = 60.0;

  /// The tank: twelve litres at two hundred bar, as litres of air at the
  /// surface; and what a resting diver breathes a minute, at the surface.
  static const double tankLitres = 12.0 * 200.0, restingBreath = 18.0;

  /// The jacket: what it holds at most, litres at whatever depth it is, and
  /// how fast its inflator fills it and its valve lets it out, litres a
  /// second at that depth.
  static const double jacketMost = 15.0, inflates = 1.2, dumps = 2.0;

  final NativeWorld _world;
  late final NativeBody body;
  late final SceneNode look;

  /// Air left in the tank, and in the jacket, litres as at the surface.
  double air = tankLitres, jacket = 0.0;

  Vector3 get position => _world.positionOf(body);
  Vector3 get velocity => _world.velocityOf(body);

  /// Metres under the sea's [level], and the pressure there, atmospheres.
  double depthUnder(double level) => level - position.y;

  /// The tank's pressure, bar.
  double get tankBar => air / 12.0;

  /// The jacket's volume where the diver is, litres: Boyle's law, the air in
  /// it squeezed by the water's weight.
  double jacketVolume(double level) => jacket / pressureAt(depthUnder(level));

  /// Minutes of air left at this depth, breathing as now.
  double minutesLeft(double level, {double effort = 0.0}) =>
      air / (restingBreath * (1.0 + effort) * pressureAt(depthUnder(level)));

  /// A step: the fins pushing along [swim] (its length, up to one, how
  /// hard), the jacket filled by [fill] or emptied by [dump], each 0 to 1,
  /// a breath drawn from the tank, and the jacket's lift added.
  void step(
    double dt, {
    required double level,
    required Vector3 swim,
    double fill = 0.0,
    double dump = 0.0,
  }) {
    final effort = math.min(swim.length, 1.0);
    final p = pressureAt(depthUnder(level));
    // Breathing: litres at depth, each one p litres from the tank.
    _draw(restingBreath * (1.0 + effort) / 60.0 * p * dt);
    if (fill > 0.0) jacket += _draw(inflates * fill * p * dt);
    if (dump > 0.0) jacket = math.max(0.0, jacket - dumps * dump * p * dt);
    // Past full, the over-pressure valve lets the rest out.
    jacket = math.min(jacket, jacketMost * p);
    final lift = 1025.0 * 9.81 * jacket / p / 1000.0;
    final push = effort > 0.0
        ? swim.normalized() * (thrust * effort)
        : Vector3.zero();
    _world.addForce(body, push + Vector3(0.0, lift, 0.0));
  }

  /// [litres] of surface air drawn from the tank, as much as it has: what
  /// was drawn.
  double _draw(double litres) {
    final drawn = math.min(litres, air);
    air -= drawn;
    return drawn;
  }

  /// Out of the water at [at] with a full tank and an empty jacket.
  void restart(Vector3 at) {
    air = tankLitres;
    jacket = 0.0;
    _world
      ..setPosition(body, at)
      ..setVelocity(body, Vector3.zero());
  }

  /// Drawn where the body is, lying along [heading], radians about y.
  void update(double heading) {
    final p = position;
    final v = velocity;
    final level = math.sqrt(v.x * v.x + v.z * v.z);
    // Tipped up or down by how the body is going, but only so far as the
    // fins drive it: a diver settling slowly with the jacket empty sinks
    // flat, as a trimmed diver does, rather than standing on their head.
    final pitch = math.atan2(v.y, math.max(level, 1.2)).clamp(-0.6, 0.6);
    look
      ..setPosition(p.x, p.y, p.z)
      ..setRotation(
        Quaternion.axisAngle(Vector3(0, 1, 0), heading) *
            Quaternion.axisAngle(Vector3(0, 0, 1), pitch),
      );
  }
}
