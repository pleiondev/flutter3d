/// The level's water, molten metal, fire and floating wood, drawn through
/// `flutter3d_effects`' [Elements].
///
/// **The run owns them; this only draws them.** The water, the fires and
/// the wood are a world of the physics core's that the run builds when it
/// stages a level and steps in its own fixed step (`run_elements.dart`),
/// so the water holds the runner up and back and the fires burn them, and
/// a replay, a ghost and a test step it to the same bits as the game.
/// What is here is everything that needs a device: the water's surface and
/// falls, the flames and their light, the pits' walls and culverts, the
/// braziers' iron and coal, the wood's looks, and the sound of it all.
///
/// **A copy of the run's world, not the world itself.** What draws the
/// fires is bound to one world for the session, because the renderer keeps
/// what it adds for good, and each level has a world of its own. So the
/// drawing holds one world of its own, and each frame the run has stepped
/// since the last, the run's world is copied into it whole by snapshot:
/// handles and all, so what the run's world calls a pool or a raft, this
/// one calls the same. Nothing is ever stepped here.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show LevelLoader;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'dressing.dart';
import 'run.dart';
import 'run_elements.dart';

/// The effects of a level: built once for the session over [elements],
/// and dressed again for every level the run opens.
final class LevelElements {
  LevelElements({
    required this.elements,
    required this._device,
    required this._liquidBundle,
  });

  /// The water, the fire and the world they are drawn from: one for the
  /// session, adopted, never stepped.
  final Elements elements;

  final GraphicsDevice _device;

  /// The water's compiled material, `LiquidLook.asset`.
  final ByteData _liquidBundle;

  NativeWorld get world => elements.world;

  /// What the fires, the falls and the splashes sound like this frame.
  PhysicsHearing get hearing => elements.hearing!;

  /// The run's elements being drawn, and how many steps of theirs the copy
  /// has.
  RunElements? _run;
  int _copied = -1;

  final List<({LiquidView view, LiquidLook look})> _waters =
      <({LiquidView view, LiquidLook look})>[];
  final List<TrackedBody> _bodies = <TrackedBody>[];

  /// The hazards' own boxes, kept out of sight under what is drawn instead.
  final List<MeshNode> _hidden = <MeshNode>[];

  /// The level's fog, as the liquids mirror it, and its sun.
  Vector3 _fog = Vector3.zero();
  ({Vector3 along, Vector3 light})? _sun;
  double _clock = 0.0;

  /// Dresses [level]: whatever the last level had is taken out, and what
  /// the run built for this one drawn.
  void stage(LevelReady level) {
    _clear();
    final run = level.staged.elements;
    final document = level.loaded.level;
    final scene = level.scene;
    elements.scene = scene;
    _fog = document.fogColor;
    for (final light in document.lights) {
      if (light.type != LevelLightType.directional) continue;
      _sun = (along: light.direction, light: light.color * light.intensity);
      elements.sun(
        along: light.direction,
        light: light.color * light.intensity,
      );
      break;
    }
    if (run == null) return;
    _run = run;
    _copy(run);

    final brushes = <Brush>[
      for (final b in document.brushes)
        if (b.solid) b,
    ];
    final stone = switch (document.materials['stone']) {
      final LevelMaterial m => (
        look: LevelLoader.materialFrom(
          m,
          level.loaded.materialTextures,
          name: 'stone',
        ),
        perMetre: m.texelsPerMeter,
      ),
      null => (
        look: RenderMaterial(
          name: 'stone',
          baseColor: LinearColor.fromSrgb(0.36, 0.36, 0.35, 1.0),
          roughness: 1.0,
        ),
        perMetre: 0.5,
      ),
    };
    for (final pool in run.pools) {
      _water(pool, scene);
      _line(pool.center, pool.half, brushes, stone.look, stone.perMetre, scene);
      final (vx0, vz0) = (
        pool.center.x - pool.half.x,
        pool.center.z - pool.half.z,
      );
      final (vx1, vz1) = (
        pool.center.x + pool.half.x,
        pool.center.z + pool.half.z,
      );
      for (final (k, s) in pool.pours.indexed) {
        final lip = Vector2(s.x.clamp(vx0, vx1), s.z.clamp(vz0, vz1));
        _mouth(lip, (vx0, vz0, vx1, vz1), s, pool.sills[k], scene);
      }
    }
    final dressed = <String>{for (final p in run.pools) p.name};
    _hidden.addAll(scene.meshes.where((m) => dressed.contains(m.name)));
    _float(run, level, scene);
    for (final bed in run.beds) {
      final MeshNode coals;
      if (bed.brazier) {
        coals = _brazier(bed.at, scene);
      } else {
        // A heap of coal lying on the floor of a molten pit.
        coals = _coals(
          bed.at,
          radius: 0.5,
          height: 0.5,
          logs: false,
          scene: scene,
        );
      }
      _bodies.add(elements.track(bed.body));
      elements.fireView.watch(
        bed.body,
        coals,
        fresh: Vector4(0.07, 0.055, 0.045, 1.0),
      );
    }
  }

  /// The run's world copied into the drawing's, when it has stepped.
  void _copy(RunElements run) {
    if (run.steps == _copied) return;
    world.restore(run.world.snapshot());
    _copied = run.steps;
  }

  /// [pool]'s surface, falls and spray, drawn and heard.
  void _water(RunPool pool, Scene scene) {
    final liquid = pool.molten ? RunElements.metal : RunElements.water;
    final look = LiquidLook.of(_liquidBundle)
      ..optics = liquid.optics
      ..wind = elements.wind.length;
    final glow = liquid.glow;
    if (glow != null) look.glow = glow;
    final sun = _sun;
    if (sun != null) look.sun(along: sun.along, light: sun.light);
    // Metal mirrors the fog dimly, water brighter towards its horizon.
    look.sky(
      zenith: pool.molten ? _fog : _fog * 2.0,
      horizon: pool.molten ? _fog * 2.0 : _fog * 4.0 + Vector3.all(0.05),
    );
    final view = LiquidView(
      world: world,
      liquid: pool.liquid,
      ground: pool.ground,
      device: _device,
      scene: scene,
      look: look.material,
      detail: elements.quality.liquid,
      mist: pool.molten ? null : const MistSettings(),
    );
    _waters.add((view: view, look: look));
    elements.hearing?.listen(pool.liquid, density: pool.density);
  }

  /// The pit's walls where the level has none: its floors are slabs a metre
  /// thick laid over nothing, so under a walkway that stands higher than
  /// the pit's floor — the gallery four metres over the spill, the side
  /// walls' feet — the pit's side is open, and its water was seen ending
  /// against a black gap. Each side is faced in [look] from the pit's floor
  /// up to the underside of whatever stands over that side, facing into
  /// the pit, so it shares no face with a brush.
  void _line(
    Vector3 center,
    Vector3 half,
    List<Brush> brushes,
    RenderMaterial look,
    double perMetre,
    Scene scene,
  ) {
    final (x0, x1) = (center.x - half.x, center.x + half.x);
    final (z0, z1) = (center.z - half.z, center.z + half.z);
    final floor = center.y - half.y;
    // Each side: along x or z, where it stands, its span, and which way is
    // into the pit.
    final sides = <(bool, double, double, double, double)>[
      (true, z0, x0, x1, 1.0),
      (true, z1, x0, x1, -1.0),
      (false, x0, z0, z1, 1.0),
      (false, x1, z0, z1, -1.0),
    ];
    const touch = 0.05;
    for (final (alongX, at, from, to, inwards) in sides) {
      final over = brushes.where((b) {
        final h = b.size / 2.0;
        final (across, across0, across1) = alongX
            ? (b.center.z, b.center.x - h.x, b.center.x + h.x)
            : (b.center.x, b.center.z - h.z, b.center.z + h.z);
        final depth = alongX ? h.z : h.x;
        // On the far side of the line from the pit, touching it.
        final beyond = inwards > 0
            ? across + depth <= at + touch && across + depth >= at - touch
            : across - depth >= at - touch && across - depth <= at + touch;
        return beyond &&
            across1 > from &&
            across0 < to &&
            b.center.y - b.size.y / 2.0 > floor + touch;
      });
      if (over.isEmpty) continue;
      // Never over the pit's own top, where the walkways are: what stands
      // higher than that beside a pit stands on something else.
      final top = over
          .map((b) => b.center.y - b.size.y / 2.0)
          .fold(center.y + half.y, math.min);
      if (top <= floor + touch) continue;
      final mesh = DeviceMesh.upload(
        _device,
        _face(
          alongX: alongX,
          at: at,
          from: from,
          to: to,
          bottom: floor,
          top: top,
          inwards: inwards,
          perMetre: perMetre,
        ),
      );
      scene.add(MeshNode(mesh, look, name: 'pit wall'));
    }
  }

  /// A culvert's mouth in the wall the [pour] runs out over, at [lip] on the
  /// pit's [box]: a dark opening as wide as the culvert, its sill where the
  /// water in it runs at [sill], in an iron frame, so the stream has
  /// somewhere to come out of.
  void _mouth(
    Vector2 lip,
    (double, double, double, double) box,
    Pour pour,
    double sill,
    Scene scene,
  ) {
    final (x0, z0, x1, z1) = box;
    // Which wall it is in, and which way out of it is.
    final (Vector2 out, bool alongX) = switch (lip) {
      _ when lip.y <= z0 + 1e-6 => (Vector2(0.0, 1.0), true),
      _ when lip.y >= z1 - 1e-6 => (Vector2(0.0, -1.0), true),
      _ when lip.x <= x0 + 1e-6 => (Vector2(1.0, 0.0), false),
      _ => (Vector2(-1.0, 0.0), false),
    };
    const band = 0.07, standOff = 0.06;
    // Its lintel stays under the ledge's top, short of the edge of the floor.
    final height = math.min(0.42, pour.culvert - band - 0.02);
    if (height <= 0.05) return;
    final width = pour.width;
    final dark = RenderMaterial(
      name: 'culvert',
      baseColor: LinearColor.fromSrgb(0.012, 0.012, 0.012, 1.0),
      roughness: 1.0,
    );
    final iron = _ironLook;
    final bar = _mesh('bar', () => CuboidShape(size: Vector3.all(1.0)).build());
    // Proud of the wall by a centimetre and a half: enough that the depth
    // test never mixes it with the stone behind it.
    final face = lip + out * 0.015;
    final mid = sill + height / 2.0;
    scene.add(
      MeshNode(bar, dark, name: 'culvert mouth')
        ..setPosition(face.x, mid, face.y)
        ..setScale(alongX ? width : 0.01, height, alongX ? 0.01 : width),
    );
    // The frame: a lintel over it and a jamb either side, an iron band
    // standing six centimetres off the wall.
    final frame = lip + out * (standOff / 2.0);
    final across = alongX ? Vector2(1.0, 0.0) : Vector2(0.0, 1.0);
    for (final (along, y, long, tall) in <(double, double, double, double)>[
      (0.0, sill + height + band / 2.0, width + 2 * band, band),
      (-(width + band) / 2.0, mid, band, height),
      ((width + band) / 2.0, mid, band, height),
    ]) {
      final at = frame + across * along;
      scene.add(
        MeshNode(bar, iron, name: 'culvert frame')
          ..setPosition(at.x, y, at.y)
          ..setScale(alongX ? long : standOff, tall, alongX ? standOff : long),
      );
    }
  }

  /// A wall's face standing at [at] across x ([alongX]) or z, from [from]
  /// to [to] along it and [bottom] to [top], facing [inwards] along the
  /// axis across it, its texture laid in world metres at [perMetre] as the
  /// level's own brushes lay theirs, so the stone runs on from theirs.
  static MeshData _face({
    required bool alongX,
    required double at,
    required double from,
    required double to,
    required double bottom,
    required double top,
    required double inwards,
    required double perMetre,
  }) {
    final normal = alongX
        ? Vector3(0.0, 0.0, inwards)
        : Vector3(inwards, 0.0, 0.0);
    // The face's own axes as the level's brushes take them: `u × v` is the
    // normal, and the stone's texture is the world projected on them.
    final u = alongX ? Vector3(inwards, 0.0, 0.0) : Vector3(0.0, 0.0, -inwards);
    final v = Vector3(0.0, 1.0, 0.0);
    final builder = MeshBuilder(
      VertexLayout.standard,
      reserveVertices: 4,
      reserveIndices: 6,
    );
    final (a, b) = inwards * (alongX ? 1.0 : -1.0) > 0
        ? (from, to)
        : (to, from);
    for (final (along, y) in <(double, double)>[
      (a, bottom),
      (b, bottom),
      (b, top),
      (a, top),
    ]) {
      final p = alongX ? Vector3(along, y, at) : Vector3(at, y, along);
      builder.addVertex(
        position: p,
        normal: normal,
        texcoord: Vector2(p.dot(u) * perMetre, p.dot(v) * perMetre),
        tangent: Vector4(u.x, u.y, u.z, -1.0),
      );
    }
    builder.addQuad(0, 1, 2, 3);
    return builder.build();
  }

  /// The iron of the braziers and the culverts' frames: wrought iron gone
  /// dark with heat and damp.
  late final RenderMaterial _ironLook = RenderMaterial(
    name: 'iron',
    baseColor: LinearColor.fromSrgb(0.09, 0.085, 0.08, 1.0),
    roughness: 0.6,
    metallic: 0.85,
  );

  /// An iron brazier standing [at] its feet, its bowl heaped with coal and
  /// two split logs, alight: a hammered bowl with a rolled rim on three
  /// splayed legs, braced by a ring a third of the way up. The coal in it is
  /// returned, which the fire chars.
  MeshNode _brazier(Vector3 at, Scene scene) {
    final iron = _ironLook;
    final bowl = _mesh(
      'bowl',
      () => LatheShape(
        // Out and up the outside to the rim, then back down the inside:
        // a bowl with a wall to it, open at the top.
        profile: <Vector2>[
          Vector2(0.0, 0.0),
          Vector2(0.14, 0.0),
          Vector2(0.30, 0.10),
          Vector2(0.40, 0.22),
          Vector2(0.425, 0.27),
          Vector2(0.395, 0.27),
          Vector2(0.37, 0.215),
          Vector2(0.27, 0.115),
          Vector2(0.12, 0.04),
          Vector2(0.0, 0.04),
        ],
        segments: 20,
      ).build(),
    );
    final rim = _mesh(
      'rim',
      () => const TorusShape(
        radius: 0.41,
        tubeRadius: 0.022,
        segments: 24,
        tubeSegments: 6,
      ).build(),
    );
    final brace = _mesh(
      'brace',
      () => const TorusShape(
        radius: 0.33,
        tubeRadius: 0.014,
        segments: 24,
        tubeSegments: 5,
      ).build(),
    );
    final leg = _mesh(
      'leg',
      () => const CylinderShape(
        radiusTop: 0.018,
        radiusBottom: 0.024,
        segments: 6,
      ).build(),
    );
    final foot = _mesh(
      'foot',
      () => const SphereShape(radius: 0.045, segments: 8, rings: 4).build(),
    );
    const bowlAt = RunElements.bowlAt;
    scene
      ..add(
        MeshNode(bowl, iron, name: 'brazier bowl')
          ..setPosition(at.x, at.y + bowlAt, at.z),
      )
      ..add(
        MeshNode(rim, iron, name: 'brazier rim')
          ..setPosition(at.x, at.y + bowlAt + 0.27, at.z),
      )
      ..add(
        MeshNode(brace, iron, name: 'brazier brace')
          ..setPosition(at.x, at.y + 0.30, at.z),
      );
    for (var k = 0; k < 3; k++) {
      final turn = 2 * math.pi * k / 3 + 0.4;
      final out = Vector3(math.cos(turn), 0.0, math.sin(turn));
      // From a foot on the floor wide of the bowl to the bowl's underside.
      final low = at + out * 0.40;
      final high = at + out * 0.16 + Vector3(0.0, bowlAt + 0.03, 0.0);
      final along = high - low;
      final mid = (low + high) * 0.5;
      scene
        ..add(
          MeshNode(leg, iron, name: 'brazier leg')
            ..setPosition(mid.x, mid.y, mid.z)
            ..setRotation(
              Quaternion.fromTwoVectors(
                Vector3(0.0, 1.0, 0.0),
                along.normalized(),
              ),
            )
            ..setScale(1.0, along.length, 1.0),
        )
        ..add(
          MeshNode(foot, iron, name: 'brazier foot')
            ..setPosition(low.x, at.y + 0.012, low.z)
            ..setScale(1.0, 0.45, 1.0),
        );
    }
    // The coal's bed sits in the bowl's throat and crowns a few
    // centimetres over the rim. The body that burns stands just over it and
    // narrower than the bowl: a flame is drawn from where the core says the
    // fire is, its tongues rooted a little under that, and from the coal
    // itself they hung down past the bowl between the legs.
    // The run's body that burns is `RunElements`'.
    return _coals(
      Vector3(at.x, at.y + bowlAt + 0.19, at.z),
      radius: 0.36,
      height: 0.12,
      logs: true,
      scene: scene,
    );
  }

  /// Coal heaped over a mound [radius] wide and [height] high from [at],
  /// and, where [logs], two split logs laid crossed on it.
  ///
  /// The mound is the coal glowing in the heart of the heap, and what the
  /// fire chars and lights; lumps of coal lie close over it, a quarter of
  /// them glowing with it and the rest black, so the light shows in the
  /// gaps between the lumps rather than over a face of the heap. The mound
  /// is returned, the lumps and the logs its children.
  MeshNode _coals(
    Vector3 at, {
    required double radius,
    required double height,
    required bool logs,
    required Scene scene,
  }) {
    double crown(double r) =>
        height * math.sqrt(math.max(0.0, 1.0 - (r * r) / (radius * radius)));
    final mound = _mesh(
      'mound $radius $height',
      () => LatheShape(
        profile: <Vector2>[
          for (var k = 0; k <= 6; k++)
            () {
              final r = radius * (1.0 - k / 6);
              return Vector2(r, crown(r));
            }(),
        ],
        segments: 14,
      ).build(),
    );
    final glowing = RenderMaterial(
      name: 'coal',
      baseColor: LinearColor.fromSrgb(0.07, 0.055, 0.045, 1.0),
      roughness: 0.85,
    );
    final black = RenderMaterial(
      name: 'coal',
      baseColor: LinearColor.fromSrgb(0.035, 0.032, 0.03, 1.0),
      roughness: 0.55,
    );
    final heap = MeshNode(mound, glowing, name: 'coal')
      ..setPosition(at.x, at.y, at.z);
    // Lumps baked into two meshes, the black and the glowing, so a brazier
    // is a handful of draws rather than one a lump.
    for (final (lit, look) in <(bool, RenderMaterial)>[
      (false, black),
      (true, glowing),
    ]) {
      heap.add(
        MeshNode(
          _mesh(
            '${lit ? 'glowing' : 'black'} lumps $radius $height',
            () => _lumps(radius, crown, glowing: lit),
          ),
          look,
          name: 'coal',
        ),
      );
    }
    if (logs) {
      final log = _mesh(
        'split log',
        () => const CylinderShape(
          radiusTop: 0.045,
          radiusBottom: 0.05,
          height: 0.56,
          segments: 7,
        ).build(),
      );
      final wood = RenderMaterial(
        name: 'charred wood',
        baseColor: LinearColor.fromSrgb(0.06, 0.04, 0.03, 1.0),
        roughness: 0.95,
      );
      for (final (turn, rise) in <(double, double)>[(0.5, 0.0), (-1.0, 0.06)]) {
        heap.add(
          MeshNode(log, wood, name: 'log')
            ..setPosition(0.0, height * 0.7 + rise, 0.0)
            ..setRotation(
              Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), turn) *
                  Quaternion.axisAngle(
                    Vector3(0.0, 0.0, 1.0),
                    math.pi / 2 - 0.08,
                  ),
            ),
        );
      }
    }
    scene.add(heap);
    return heap;
  }

  /// The lumps of coal over a mound [radius] wide whose height at a
  /// distance from its middle is [crown]: every fourth of them where
  /// [glowing], the rest where not. Laid on a sunflower's spiral, so they
  /// cover it evenly and close enough to touch, each turned and squashed its
  /// own way; the same for every heap of the same size.
  static MeshData _lumps(
    double radius,
    double Function(double) crown, {
    required bool glowing,
  }) {
    final lump = const SphereShape(radius: 1.0, segments: 6, rings: 4).build();
    final stride = lump.layout.floatsPerVertex;
    final scatter = math.Random(7);
    final count = (radius * radius * 420).round().clamp(24, 110);
    final builder = MeshBuilder(VertexLayout.standard);
    for (var k = 0; k < count; k++) {
      final r = radius * 0.9 * math.sqrt((k + 0.5) / count);
      final turn = k * 2.39996;
      final size = (0.05 + 0.03 * scatter.nextDouble()) * (radius / 0.36);
      final axis = Vector3(scatter.nextDouble(), 1.0, scatter.nextDouble())
        ..normalize();
      final spin = Quaternion.axisAngle(axis, scatter.nextDouble() * math.pi);
      if ((k % 4 == 0) != glowing) continue;
      final scale = Vector3(size * 1.2, size * 0.75, size);
      final center = Vector3(
        r * math.cos(turn),
        crown(r) - 0.3 * size,
        r * math.sin(turn),
      );
      final first = builder.vertexCount;
      for (var v = 0; v < lump.vertexCount; v++) {
        final o = v * stride;
        final p = Vector3(
          lump.vertices[o] * scale.x,
          lump.vertices[o + 1] * scale.y,
          lump.vertices[o + 2] * scale.z,
        );
        // A normal goes through a stretch by its inverse.
        final n = Vector3(
          lump.vertices[o + 3] / scale.x,
          lump.vertices[o + 4] / scale.y,
          lump.vertices[o + 5] / scale.z,
        )..normalize();
        builder.addVertex(
          position: spin.rotated(p)..add(center),
          normal: spin.rotated(n),
          texcoord: Vector2(lump.vertices[o + 6], lump.vertices[o + 7]),
        );
      }
      for (var i = 0; i < lump.indices.length; i += 3) {
        builder.addTriangle(
          first + lump.indices[i],
          first + lump.indices[i + 1],
          first + lump.indices[i + 2],
        );
      }
    }
    return builder.build();
  }

  /// The wood the run floats, in the level's own wood where it has some.
  void _float(RunElements run, LevelReady level, Scene scene) {
    if (run.afloat.isEmpty) return;
    final wood = level.loaded.level.materials['wood'];
    final look = wood == null
        ? RenderMaterial(
            name: 'wood',
            baseColor: LinearColor.fromSrgb(0.42, 0.30, 0.18, 1.0),
            roughness: 0.85,
          )
        : LevelLoader.materialFrom(
            wood,
            level.loaded.materialTextures,
            name: 'wood',
          );
    final log = _mesh(
      'log',
      () => const CylinderShape(
        radiusTop: RunElements.logRadius * 0.92,
        radiusBottom: RunElements.logRadius,
        height: 2 * RunElements.logHalf,
        segments: 12,
      ).build(),
    );
    final plank = _mesh(
      'plank',
      () => CuboidShape(size: Vector3(0.8, 0.14, 2.2)).build(),
    );
    for (final a in run.afloat) {
      final SceneNode node;
      if (a.raft) {
        node = SceneNode(name: 'raft');
        for (final x in <double>[-0.31, 0.0, 0.31]) {
          node.add(
            MeshNode(log, look, name: 'log')
              ..setPosition(x, 0, 0)
              ..setRotation(
                Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
              ),
          );
        }
      } else {
        node = MeshNode(plank, look, name: 'plank');
      }
      scene.add(node);
      _bodies.add(
        elements.track(
          a.body,
          look: node,
          chars: node is MeshNode ? node : null,
        ),
      );
    }
  }

  /// The meshes made once, by name, and kept for every level after.
  final Map<String, DeviceMesh> _meshes = <String, DeviceMesh>{};
  DeviceMesh _mesh(String name, MeshData Function() build) =>
      _meshes.putIfAbsent(name, () => DeviceMesh.upload(_device, build()));

  /// Hides the hazards' boxes drawn in the pools' place. After the fixtures
  /// are placed, every frame: placing them shows them again.
  void hideDressed() {
    for (final node in _hidden) {
      node.isVisible = false;
    }
  }

  /// A frame: the run's world copied in if it has stepped since, and
  /// everything drawn as it then stands, seen from [eye], [dt] on — nought
  /// while the run is held for a photograph. A splash is heard where
  /// anything went into the water in the steps since.
  void update(double dt, {required Vector3 eye}) {
    final run = _run;
    // A level closed is let go before the next is opened, and frames are
    // drawn between: they show the last copy, still.
    if (run == null || run.isDisposed || dt <= 0.0) return;
    _copy(run);
    _clock += dt;
    for (final w in _waters) {
      w.look.update(seconds: _clock, eye: eye);
      w.view.update(dt);
    }
    elements.update(dt, eye: eye, events: run.takeEvents());
  }

  /// Everything the last level had, taken out of the drawing.
  void _clear() {
    for (final w in _waters) {
      w.view.dispose();
      elements.hearing?.unlisten(w.view.liquid);
    }
    _waters.clear();
    for (final b in _bodies) {
      elements.remove(b);
    }
    _bodies.clear();
    _hidden.clear();
    _run = null;
    _copied = -1;
  }

  /// The drawing let go, and the world it copied into with it.
  void dispose() {
    _clear();
    elements.dispose();
    world.dispose();
  }
}
