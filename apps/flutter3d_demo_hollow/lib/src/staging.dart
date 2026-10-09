/// The one place that assembles a run of Cobble Hollow: the ground, the
/// river and its lagoon, the volcano's lava, and what is drawn of them.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        ActionDeclaration,
        ActionSet,
        AxisAction,
        BodyPose,
        GameAction,
        InputState,
        Snapshot;

import 'car.dart';
import 'crane.dart';
import 'looks.dart';
import 'props.dart';
import 'terrain.dart';

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// How far up a face of the ground may look, its normal's rise, and still
/// be drawn as a wall: steeper than about forty-five degrees.
const double _steep = 0.7;

/// The same on the volcano, where only the crater's lip, steeper than
/// about sixty-five degrees, is a wall.
const double _lip = 0.42;

/// A little over the plateau's top, m: what lies higher by the volcano is
/// the volcano.
const double _plateau = 8.3;

/// The lava: molten basalt, dark and opaque, glowing where its flow breaks
/// the crust. Until molten basalt's heat is measured here it takes heat as
/// water at the air's temperature does, which is what it did before it had
/// any.
final Liquid _lava = Liquid(
  properties: NativeLiquidProperties.moltenBasalt,
  optics: LiquidOptics(
    absorb: Vector3.all(13.82),
    backscatter: Vector3(0.7271, 0.2819, 0.1396),
  ),
  heat: NativeLiquidHeat.water(),
  glow: Vector3(6.0, 1.6, 0.25),
);

/// The river's water: a mountain stream's, clear.
final Liquid _water = Liquid.water();

/// The valley's rules, as a `.f3drun` names them: a tape recorded under one
/// number is refused by a build whose valley steps differently, and its pose
/// record is shown instead.
const SimulationVersion hollowSimulation = SimulationVersion(genre: 'hollow');

/// What the player asks of the valley beyond the four ways to drive, which
/// are [GameAction.moveForward] and its kin: the brake held, the crane's
/// neck and swing held, and the four one-off asks — act, right the car, the
/// crane taken or left, the rope.
abstract final class HollowActions {
  static const GameAction brake = GameAction('brake');
  static const GameAction act = GameAction('act');
  static const GameAction rightUp = GameAction('rightUp');
  static const GameAction crane = GameAction('crane');
  static const GameAction grab = GameAction('grab');
  static const GameAction liftUp = GameAction('liftUp');
  static const GameAction liftDown = GameAction('liftDown');
  static const GameAction swingLeft = GameAction('swingLeft');
  static const GameAction swingRight = GameAction('swingRight');

  /// The crane's neck, up positive: what [liftUp] less [liftDown] was.
  static const AxisAction lift = AxisAction('lift');

  /// The crane's swing, left positive: what [swingLeft] less [swingRight]
  /// was.
  static const AxisAction swing = AxisAction('swing');

  /// What the valley declares. [lift] and [swing] name the button pairs a
  /// run recorded before they were axes, so such a run replays with the
  /// crane moving as it did.
  static const ActionSet set = ActionSet('hollow', <ActionDeclaration>[
    ActionDeclaration(GameAction.moveForward, label: 'accelerate'),
    ActionDeclaration(GameAction.moveBack, label: 'reverse'),
    ActionDeclaration(GameAction.moveLeft, label: 'turn left'),
    ActionDeclaration(GameAction.moveRight, label: 'turn right'),
    ActionDeclaration(brake),
    ActionDeclaration(act),
    ActionDeclaration(rightUp, label: 'right the car'),
    ActionDeclaration(crane),
    ActionDeclaration(grab),
    ActionDeclaration(
      lift,
      fromButtons: (negative: liftDown, positive: liftUp),
    ),
    ActionDeclaration(
      swing,
      fromButtons: (negative: swingRight, positive: swingLeft),
    ),
  ]);
}

/// The valley, stepped and drawn.
final class HollowRun {
  HollowRun({
    required GraphicsDevice device,
    required this.scene,
    required this.elements,
    required HollowLooks looks,
    InputState? input,
  }) : _device = device,
       input = input ?? InputState() {
    _ground = groundGrid();
    _buildGround(looks);
    // The river runs off the valley's open edges.
    river = elements.addWater(
      ground: ElementHeightfield.list(
        origin: Vector3.zero(),
        cell: hollowCell,
        nx: hollowCells,
        nz: hollowCells,
        heights: _ground,
      ),
      liquid: _water,
      bed: const Bed(roughness: Bed.mountainStream),
      mist: const MistSettings(),
    );
    for (final side in <GridSide>[
      GridSide.west,
      GridSide.east,
      GridSide.south,
      GridSide.north,
    ]) {
      river.setEdge(side, NativeEdgeFlow.free);
    }
    river
      ..fillBasin(from: Vector3(lagoonX, 0.0, lagoonZ), level: 0.6)
      ..addSpring(
        at: Vector3(springX, 0.0, springZ),
        discharge: 0.6,
        radius: 0.8,
      );
    // The lava's own grid, over the volcano's south flank.
    lava = elements.addWater(
      ground: ElementHeightfield.list(
        origin: Vector3(_lavaX0, 0.0, 0.0),
        cell: hollowCell,
        nx: _lavaCells,
        nz: _lavaCells,
        heights: groundGrid(
          x0: _lavaX0,
          z0: 0.0,
          nx: _lavaCells,
          nz: _lavaCells,
        ),
      ),
      liquid: _lava,
      bed: const Bed(roughness: 0.05),
    );
    car = StoneCar(
      world,
      device,
      scene,
      Vector3(siteX, groundAt(siteX, siteZ - 6) + 1.2, siteZ - 6),
      looks,
    );
    stones = QuarryStones(world, scene, looks);
    idol = Idol(world, device, scene, looks);
    rafts = Rafts(world, device, scene, looks);
    trees = Trees(world, scene, fire, looks);
    village = Village(world, device, scene, fire, looks);
    volcano = Volcano(world, device, scene, lava, village.huts, looks);
    // On the quarry's north rim, facing into it.
    final craneAt = Vector3(
      quarryX,
      groundAt(quarryX, quarryZ - quarryHalfZ - 2.2),
      quarryZ - quarryHalfZ - 2.2,
    );
    crane = DinoCrane(
      world,
      device,
      scene,
      at: craneAt,
      facing: -1.5707963267948966,
      beast: looks.beast,
    );
    _craneAt = craneAt;
  }

  /// The lava's grid: from x = 36 to the east edge, from the north edge
  /// past the cliff.
  static const double _lavaX0 = 32.0;
  static const int _lavaCells = 64;

  final GraphicsDevice _device;
  final Scene scene;

  /// The river, the lava and the fires as the core has them, drawn and
  /// heard; the run steps the world itself.
  final Elements elements;

  NativeWorld get world => elements.world;
  late final List<double> _ground;
  late final WaterBody river, lava;
  FireView get fire => elements.fireView;
  late final StoneCar car;
  late final QuarryStones stones;
  late final Idol idol;
  late final Rafts rafts;
  late final Trees trees;

  /// What the fires, the falls and the splashes sound like this frame.
  PhysicsHearing get hearing => elements.hearing!;
  late final Village village;
  late final Volcano volcano;
  late final DinoCrane crane;

  /// Whether the player works the crane rather than drives.
  bool craning = false;

  /// What the last action did, for the panel.
  String said = '';

  late final Vector3 _craneAt;

  /// Whether the car stands near enough the crane to work it.
  bool get nearCrane => (car.position - _craneAt).length < 9.0;

  /// The one action key: at the water, fill the barrel; at a burning hut,
  /// empty it over it.
  void act() {
    final p = car.position;
    if (idol.carried) {
      if (Vector2(p.x - villageX, p.z - villageZ).length < 6.0) {
        idol.setDown();
        said = 'The idol is home.';
        return;
      }
    } else if (!idol.home && idol.lift(car.body, car.deck, p)) {
      said = 'The idol is on the car: bring it to the village.';
      return;
    }
    final here = world.sampleShallow(river.native, p.x, p.z);
    if (here != null && here.depth > 0.3) {
      car.water = StoneCar.barrelHolds;
      said = 'The barrel is full.';
      return;
    }
    if (car.water >= 25.0 && village.douse(p, kilograms: car.water)) {
      car.water = 0.0;
      said = 'Water over the hut.';
      return;
    }
    said = car.water <= 0.0
        ? 'Drive into the river or the lagoon to fill the barrel.'
        : 'Nothing burning near enough.';
  }

  /// Where the eye is, for the ripples that fade with distance.
  final Vector3 eye = Vector3.zero();

  /// The lagoon's surface over the origin, m.
  double get lagoonLevel =>
      world.sampleShallow(river.native, lagoonX, lagoonZ)?.surface ?? 0.0;

  void _buildGround(HollowLooks looks) {
    final n = hollowCells;
    final vertices = Float32List(n * n * _stride);
    double at(int i, int j) =>
        _ground[i.clamp(0, n - 1) + j.clamp(0, n - 1) * n];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final x = (i + 0.5) * hollowCell, z = (j + 0.5) * hollowCell;
        final h = at(i, j);
        final normal = Vector3(
          -(at(i + 1, j) - at(i - 1, j)) / (2 * hollowCell),
          1.0,
          -(at(i, j + 1) - at(i, j - 1)) / (2 * hollowCell),
        )..normalize();
        // Along u, which runs with x: east, bent to lie in the slope. Its
        // fourth number leaves the bitangent n × t at −z: the shaders take
        // the bitangent the way v decreases, a normal map's green pointing
        // up the picture (material_maps.glsl), and v runs with z.
        final tangent = (Vector3(1.0, 0.0, 0.0) - normal * normal.x)
          ..normalize();
        final o = (i + j * n) * _stride;
        // What covers the ground is in the baked picture, which spans the
        // whole valley; the colour of the vertices only shades it, a few
        // per cent lighter or darker from one to the next, the same every
        // run.
        final tuft = (((i * 73856093) ^ (j * 19349663)) & 0xff) / 255.0;
        final shade = 0.95 + 0.1 * tuft;
        vertices
          ..[o] = x
          ..[o + 1] = h
          ..[o + 2] = z
          ..[o + 3] = normal.x
          ..[o + 4] = normal.y
          ..[o + 5] = normal.z
          ..[o + 6] = x / hollowSize
          ..[o + 7] = z / hollowSize
          ..[o + 8] = tangent.x
          ..[o + 9] = tangent.y
          ..[o + 10] = tangent.z
          ..[o + 11] = 1
          ..[o + 12] = shade
          ..[o + 13] = shade
          ..[o + 14] = shade
          ..[o + 15] = 1;
      }
    }
    final indices = <int>[
      for (var j = 0; j < n - 1; j++)
        for (var i = 0; i < n - 1; i++) ...<int>[
          i + j * n,
          i + (j + 1) * n,
          i + 1 + j * n,
          i + 1 + j * n,
          i + (j + 1) * n,
          i + 1 + (j + 1) * n,
        ],
    ];
    // A picture seen from above has next to nothing to give a wall: the
    // cliff, the quarry's sides and the crater's lip would wear a few pixels
    // drawn out into streaks. Those faces are drawn apart, their rock laid
    // on from the side.
    Vector3 corner(int k) => Vector3(
      vertices[k * _stride],
      vertices[k * _stride + 1],
      vertices[k * _stride + 2],
    );
    // The volcano's own slopes, above the plateau it stands on: the cliff
    // under it is the plateau's rock, as the rest of the cliff is.
    bool volcanic(int t) {
      final a = corner(indices[t]);
      return a.y > _plateau &&
          Vector2(a.x - volcanoX, a.z - volcanoZ).length < volcanoRadius + 1.0;
    }

    // The cone's flanks keep the picture from above, which suits them; only
    // the crater's lip is steep enough to need the side.
    bool steep(int t) {
      final a = corner(indices[t]);
      final face = (corner(indices[t + 1]) - a).cross(
        corner(indices[t + 2]) - a,
      )..normalize();
      return face.y.abs() < (volcanic(t) ? _lip : _steep);
    }

    final walls = <int>[
      for (var t = 0; t < indices.length; t += 3)
        if (steep(t)) t,
    ];
    final level = <int>[
      for (var t = 0; t < indices.length; t += 3)
        if (!steep(t)) ...indices.sublist(t, t + 3),
    ];

    _addWalls(
      vertices,
      indices,
      <int>[
        for (final t in walls)
          if (!volcanic(t)) t,
      ],
      covered(
        'cliff',
        looks.granite,
        // As the bare rock is in the baked picture where the walls meet it.
        tint: Vector4(0.74, 0.72, 0.68, 1.0),
        repeat: Vector2.all(1.0 / 5.0),
        roughness: 0.95,
      ),
    );
    _addWalls(
      vertices,
      indices,
      <int>[
        for (final t in walls)
          if (volcanic(t)) t,
      ],
      covered(
        'crater',
        looks.basalt,
        tint: Vector4(0.85, 0.8, 0.75, 1.0),
        repeat: Vector2.all(1.0 / 6.0),
        roughness: 0.95,
      ),
    );
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          _device,
          MeshData(
            layout: VertexLayout.standard,
            vertices: vertices,
            indices: Uint32List.fromList(level),
          ),
        ),
        RenderMaterial(
          name: 'ground',
          lighting: repeating,
          albedo: looks.ground,
          // The baked picture is three centimetres a pixel; the relief of
          // dry earth, repeating every two metres, is what the eye finds in
          // the ground under the car.
          normal: looks.groundRelief,
          normalScale: 0.8,
          roughness: 0.95,
          textureTransforms: <MaterialMap, TextureTransform>{
            MaterialMap.normal: TextureTransform(
              scale: Vector2.all(hollowSize / 2.0),
            ),
          },
        ),
        name: 'ground',
      ),
    );
    final floor = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setMesh(
      floor,
      world.createMesh(<Vector3>[
        for (var j = 0; j < n; j++)
          for (var i = 0; i < n; i++)
            Vector3((i + 0.5) * hollowCell, at(i, j), (j + 0.5) * hollowCell),
      ], indices),
    );
  }

  /// The triangles of the ground that start at each of [triangles] in
  /// [indices], drawn in [material] as a mesh of their own: each corner
  /// keeps its place and its normal, so the light runs on across the seam,
  /// but takes its picture from the side the face looks to, along x or
  /// along z, in metres, and upright.
  void _addWalls(
    Float32List ground,
    List<int> indices,
    List<int> triangles,
    RenderMaterial material,
  ) {
    if (triangles.isEmpty) return;
    final vertices = Float32List(triangles.length * 3 * _stride);
    var o = 0;
    for (final t in triangles) {
      final k = <int>[for (var c = 0; c < 3; c++) indices[t + c] * _stride];
      final a = Vector3(ground[k[0]], ground[k[0] + 1], ground[k[0] + 2]);
      final face =
          (Vector3(ground[k[1]], ground[k[1] + 1], ground[k[1] + 2]) - a).cross(
            Vector3(ground[k[2]], ground[k[2] + 1], ground[k[2] + 2]) - a,
          );
      // Looking east or west, the picture runs along z; else along x.
      final alongZ = face.x.abs() > face.z.abs();
      for (final s in k) {
        for (var f = 0; f < _stride; f++) {
          vertices[o + f] = ground[s + f];
        }
        final x = ground[s], y = ground[s + 1], z = ground[s + 2];
        vertices
          ..[o + 6] = alongZ ? z : x
          ..[o + 7] = -y
          ..[o + 8] = alongZ ? 0.0 : 1.0
          ..[o + 9] = 0.0
          ..[o + 10] = alongZ ? 1.0 : 0.0
          ..[o + 11] = 1.0;
        o += _stride;
      }
    }
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          _device,
          MeshData(
            layout: VertexLayout.standard,
            vertices: vertices,
            indices: Uint32List.fromList(
              List<int>.generate(triangles.length * 3, (k) => k),
            ),
          ),
        ),
        material,
        name: material.name,
      ),
    );
  }

  /// What the player asks for: the window's keys write it, a tape writes it
  /// on a replay, and the step alone reads it, at its top, so a run is its
  /// tape. Nothing a step does reads a key.
  final InputState input;

  /// The valley's step, phase by phase, on [loop]: the controls in
  /// `input`, the rafts and the volcano in `movers` (what the valley drives
  /// on its own, before the world sweeps), the core's world in `physics`,
  /// the elements — the flames held, the world's events read, the water and
  /// fire drawn — in `elements`, and the bodies' looks put where the world
  /// has them once a frame, in `animate`.
  ///
  /// **A fixed step now, at the loop's world rate.** The valley was stepped
  /// with each frame's own time, a thirtieth of a second at most; it is
  /// stepped in sixtieths whatever the display, so a run is the same run on
  /// a fast machine and a slow one.
  void install(LoopRegistry loop) {
    loop
      ..addSystem('hollow.controls', LoopPhase.input, (_) => _control())
      ..addSystem('hollow.valley', LoopPhase.movers, (step) {
        rafts.update(step.dt);
        volcano.update(step.dt);
      })
      ..addSystem(
        'hollow.world',
        LoopPhase.physics,
        (step) => world.step(step.dt),
      )
      ..addSystem(
        'hollow.elements',
        LoopPhase.fields,
        (step) => elements.update(step.dt, eye: eye),
      )
      ..addSystem('hollow.show', LoopPhase.animate, (_) => show());
  }

  /// One step of [dt] and what is drawn of it, in the order [install] runs
  /// them: for a reel, which steps the valley by its own frames.
  void step(double dt) {
    _control();
    rafts.update(dt);
    volcano.update(dt);
    world.step(dt);
    elements.update(dt, eye: eye);
    show();
  }

  /// The one-off asks first — act, right the car, the crane, the rope, in
  /// that order, as the keys used to be heard before the step — then the car
  /// or the crane worked as the held actions say.
  void _control() {
    final i = input;
    if (i.pressed(HollowActions.act)) act();
    if (i.pressed(HollowActions.rightUp)) car.rightUp();
    if (i.pressed(HollowActions.crane)) {
      craning = !craning && nearCrane;
      said = craning
          ? 'At the crane: I/K neck, J/L swing, G rope, C to drive.'
          : nearCrane
          ? 'Back in the car.'
          : 'Drive up to the crane at the quarry first.';
    }
    if (craning && i.pressed(HollowActions.grab)) crane.grab(stones.bodies);
    double axis(GameAction plus, GameAction minus) =>
        (i.held(plus) ? 1.0 : 0.0) - (i.held(minus) ? 1.0 : 0.0);
    if (craning) {
      car.drive(throttle: 0, turn: 0, hold: true);
      // Axes now, bound to I/K and J/L as composites; a run recorded when
      // they were four buttons is upgraded by [HollowActions.set].
      crane.work(
        lift: i.axis(HollowActions.lift),
        swing: i.axis(HollowActions.swing),
      );
    } else {
      crane.work(lift: 0, swing: 0);
      car.drive(
        throttle: axis(GameAction.moveForward, GameAction.moveBack),
        turn: axis(GameAction.moveLeft, GameAction.moveRight),
        hold: i.held(HollowActions.brake),
      );
    }
  }

  // ------------------------------------------------------------- saving

  /// The valley as it stands after a step: the core's world with the water,
  /// the lava, the heat and every body in it, the flames the elements hold,
  /// and what only this side keeps — the barrel, the crane taken or not, the
  /// rafts and bombs launched, the volcano's clock and dice, the lashings.
  ///
  /// **The bodies by their handles**, which the core gives back the same
  /// after a restore: a raft launched after this was taken is gone again
  /// when it is put back, and one taken out since comes back.
  Snapshot save() => Snapshot(<String, Object?>{
    'world': base64Encode(world.snapshot()),
    'elements': elements.saveElements(),
    'water': car.water,
    'craning': craning,
    'said': said,
    'rafts': rafts.save(),
    'volcano': volcano.save(),
    'idol': idol.save(),
    'crane': crane.save(),
  });

  /// Puts the valley back as [save] wrote it. Throws a [FormatException] for
  /// a snapshot that is not one of this valley's.
  void restore(Snapshot snapshot) {
    final d = snapshot.data;
    if (d case {
      'world': final String bytes,
      'elements': final Map<String, Object?> saved,
      'water': final num water,
      'craning': final bool craning,
      'said': final String said,
    }) {
      world.restore(base64Decode(bytes));
      // Contacts and events of the world that was left are not this one's.
      world.readEvents();
      elements.restoreElements(saved);
      car.water = water.toDouble();
      this.craning = craning;
      this.said = said;
      rafts.restore(d['rafts']);
      volcano.restore(d['volcano']);
      idol.restore(d['idol']);
      crane.restore(d['crane']);
      show();
      return;
    }
    throw const FormatException('not a snapshot of Cobble Hollow');
  }

  /// Where the run's moving bodies are, for the pose record a `.f3drun`
  /// carries beside its tape: the car, the idol, the quarry's blocks, the
  /// rafts and the bombs, each by a name it keeps for the run.
  Iterable<BodyPose> poses() sync* {
    BodyPose pose(String name, NativeBody body) =>
        BodyPose(name, world.localPositionOf(body), world.orientationOf(body));
    yield pose('car', car.body);
    yield pose('idol', idol.body);
    for (var k = 0; k < stones.stones.length; k++) {
      yield pose('stone#$k', stones.stones[k].body);
    }
    for (final r in rafts.rafts) {
      yield pose('raft#${r.body.raw}', r.body);
    }
    for (final b in volcano.bombs) {
      yield pose('bomb#${b.body.raw}', b.body);
    }
  }

  /// The bodies drawn where the world has them.
  void show() {
    car.update();
    stones.update();
    idol.update();
    crane.update();
  }

  void dispose() {
    elements.dispose();
    world.dispose();
  }
}
