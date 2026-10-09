/// Water, fire and bodies for a game, drawn and heard: the view half of the
/// elements, over the simulation `flutter3d_elements` steps — so a game
/// says only what is where.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        EventRegistry,
        Flutter3dPlugin,
        LoopContext,
        LoopPhase,
        PluginApiVersion,
        PluginHost,
        PluginManifest,
        PluginTouches,
        Registration;
import 'package:vector_math/vector_math.dart';

import 'fire_light.dart';
import 'fire_view.dart';
import 'liquid_look.dart';
import 'liquid_view.dart';
import 'physics_hearing.dart';

/// How much of the elements is drawn at most.
final class ElementsQuality {
  const ElementsQuality({required this.liquid, required this.fire});

  /// A desktop or a console, or a phone.
  factory ElementsQuality.of({required bool phone}) => phone
      ? const ElementsQuality(
          liquid: LiquidDetail.light,
          fire: FireDetail.light,
        )
      : const ElementsQuality(liquid: LiquidDetail.full, fire: FireDetail.full);

  final LiquidDetail liquid;
  final FireDetail fire;
}

/// What a liquid is: how it flows ([properties]), what it does to light
/// ([optics]), what heat sees of it ([heat]), and the light it gives off
/// itself, [glow] — molten rock's.
final class Liquid {
  const Liquid({
    required this.properties,
    required this.optics,
    required this.heat,
    this.glow,
    this.atAirTemperature = false,
  });

  /// Fresh water: pure water's flow, light and heat. A pond, a river or a
  /// crypt's pool has what is dissolved and carried in it besides, which is
  /// the game's to give in [optics].
  ///
  /// At [temperature] K when one is given; otherwise [atAirTemperature] —
  /// as warm as the air of whichever world it is poured into, read from
  /// that world by [Elements.addWater].
  static Liquid water({double? temperature}) => Liquid(
    properties: NativeLiquidProperties.water,
    optics: LiquidOptics.pureWater,
    heat: temperature == null
        ? NativeLiquidHeat.water()
        : NativeLiquidHeat.water(temperature: temperature),
    atAirTemperature: temperature == null,
  );

  final NativeLiquidProperties properties;
  final LiquidOptics optics;
  final NativeLiquidHeat heat;
  final Vector3? glow;

  /// Whether [heat]'s temperature is the air's of the world the liquid is
  /// in rather than its own: read by [Elements.addWater], which then pours
  /// it at [NativeWorld.airTemperature]. A liquid given a [heat] of its own
  /// — through [copyWith] too — is at that heat's.
  final bool atAirTemperature;

  /// [heat] as it is in [world]: at the world's air temperature when the
  /// liquid is [atAirTemperature].
  NativeLiquidHeat heatIn(NativeWorld world) =>
      atAirTemperature ? heat.at(world.airTemperature) : heat;

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  Liquid copyWith({
    NativeLiquidProperties? properties,
    LiquidOptics? optics,
    NativeLiquidHeat? heat,
    Vector3? glow,
    bool? atAirTemperature,
    bool clearGlow = false,
  }) => Liquid(
    properties: properties ?? this.properties,
    optics: optics ?? this.optics,
    heat: heat ?? this.heat,
    glow: clearGlow ? null : (glow ?? this.glow),
    atAirTemperature: atAirTemperature ?? this.atAirTemperature,
  );
}

/// Water, fire and bodies for a game, drawn and heard: the view half of the
/// elements, over an [ElementsSimulation] that steps them.
///
/// ```dart
/// final elements = await Elements.open(device: device, renderer: renderer,
///     scene: scene, load: rootBundle.load,
///     quality: ElementsQuality.of(phone: isPhone));
/// final pond = elements.addWater(ground: ElementHeightfield.sampled(...),
///     liquid: Liquid.water(), bed: const Bed(roughness: Bed.naturalStream));
/// pond.fillBasin(from: lagoon, level: 0.6);
/// final crate = elements.addBody(Solid.box(half, material: pine,
///     density: 500), at: p, look: node);
/// // each frame
/// elements.update(dt, eye: camera.worldPosition);
/// ```
///
/// **Two halves** (item 19): [simulation] steps — the world, the flames, every
/// element's step — and needs no renderer; this draws and sounds it. [update]
/// does both, for a game that steps the elements once a frame; a game on an
/// `EngineLoop` steps [simulation] in the `elements` phase
/// ([ElementsSimulationPlugin]) and calls [draw] in the frame
/// ([ElementsViewPlugin]).
///
/// **Fire and water are elements like any other** ([ElementHook]): each step
/// runs them, water then fire, then any element a plugin added
/// ([addElement]), before the world steps; and they are drawn in the same
/// order after it. What the world itself raises goes to [listener] and, once
/// [publishTo] names a bus, onto the bus as [ElementEvent]s.
final class Elements {
  Elements._(
    this.simulation, {
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    required this._liquidBundle,
    required this.quality,
    required FireLights lights,
    required this.hearing,
  }) : _device = device,
       _scene = scene,
       fireView = FireView(
         world: simulation.world,
         device: device,
         scene: scene,
         renderer: renderer,
         detail: quality.fire,
         lights: lights,
       );

  /// The half that steps: the world, the flames, every element's step.
  final ElementsSimulation simulation;

  /// Plugin elements drawn after water and fire, in the order added.
  final List<ElementHook> _views = <ElementHook>[];

  /// Every element this holds, water and fire first, in the order they
  /// step and draw.
  List<ElementHook> get elements => <ElementHook>[
    ...simulation.elements,
    for (final hook in _views)
      if (!simulation.elements.contains(hook)) hook,
  ];

  /// Adds a plugin element: stepped by [simulation] after fire and water,
  /// before the world, and drawn after them while its switch is on
  /// ([ElementsSteps.isOn]). With [step] false it is only drawn — for an
  /// element a loop steps ([installElement]). Throws an [ArgumentError] for
  /// an id already held.
  Registration addElement(ElementHook hook, {bool step = true}) {
    for (final h in elements) {
      if (h.id == hook.id) {
        throw ArgumentError.value(
          hook.id,
          'hook',
          'the elements already hold an element "${hook.id}"',
        );
      }
    }
    final stepping = step ? simulation.addElement(hook) : null;
    _views.add(hook);
    return Registration(() {
      stepping?.cancel();
      _views.remove(hook);
    });
  }

  /// [ElementsSimulation.saveElements].
  Map<String, Object?> saveElements() => simulation.saveElements();

  /// [ElementsSimulation.restoreElements].
  void restoreElements(Map<String, Object?> saved) =>
      simulation.restoreElements(saved);

  /// [ElementsSimulation.publishTo].
  Registration publishTo(EventRegistry bus) => simulation.publishTo(bus);

  /// A world of its own, which it steps.
  static Future<Elements> open({
    required GraphicsDevice device,
    required Renderer renderer,
    required Scene scene,
    required Future<ByteData> Function(String asset) load,
    ElementsQuality quality = const ElementsQuality(
      liquid: LiquidDetail.full,
      fire: FireDetail.full,
    ),
    FireLights lights = const FireLights.clusters(),
    PhysicsHearing Function(NativeWorld world)? hearing,
  }) => over(
    ElementsSimulation.open(),
    device: device,
    renderer: renderer,
    scene: scene,
    load: load,
    quality: quality,
    lights: lights,
    hearing: hearing,
  );

  /// [world], which the game steps itself: followed, drawn and heard, not
  /// stepped.
  static Future<Elements> adopt(
    NativeWorld world, {
    required GraphicsDevice device,
    required Renderer renderer,
    required Scene scene,
    required Future<ByteData> Function(String asset) load,
    ElementsQuality quality = const ElementsQuality(
      liquid: LiquidDetail.full,
      fire: FireDetail.full,
    ),
    FireLights lights = const FireLights.clusters(),
    PhysicsHearing Function(NativeWorld world)? hearing,
  }) => over(
    ElementsSimulation.adopt(world),
    device: device,
    renderer: renderer,
    scene: scene,
    load: load,
    quality: quality,
    lights: lights,
    hearing: hearing,
  );

  /// The view of [simulation], which something else may step: a loop in its
  /// `elements` phase, a server's replay with this drawn beside it.
  static Future<Elements> over(
    ElementsSimulation simulation, {
    required GraphicsDevice device,
    required Renderer renderer,
    required Scene scene,
    required Future<ByteData> Function(String asset) load,
    ElementsQuality quality = const ElementsQuality(
      liquid: LiquidDetail.full,
      fire: FireDetail.full,
    ),
    FireLights lights = const FireLights.clusters(),
    PhysicsHearing Function(NativeWorld world)? hearing,
  }) async {
    final bundle = await load(LiquidLook.asset);
    renderer.renderSteps.addMaterials(await device.loadShaders(bundle));
    return Elements._(
      simulation,
      device: device,
      scene: scene,
      renderer: renderer,
      liquidBundle: bundle,
      quality: quality,
      lights: lights,
      hearing: hearing?.call(simulation.world),
    );
  }

  /// The core's world: what this does not say, the game reaches through.
  NativeWorld get world => simulation.world;

  /// Whether [update] steps [world]; not for one [adopt]ed.
  bool get steps => simulation.steps;

  /// How much is drawn at most.
  final ElementsQuality quality;

  /// The fires, and what lights and puts them out.
  Fires get fires => simulation.fires;

  /// What draws the fires.
  final FireView fireView;

  /// What is heard, or null for a game that hears nothing.
  final PhysicsHearing? hearing;

  /// What the elements tell the game ([ElementsListener]); null for none.
  /// The simulation's: the callbacks about the world are told as it steps,
  /// the drawing's ([ElementsListener.budget], [ElementsListener.seen],
  /// [ElementsListener.lost]) as this draws.
  ElementsListener? get listener => simulation.listener;
  set listener(ElementsListener? value) => simulation.listener = value;

  /// Which steps are taken ([ElementsSteps]); set, every view takes it at
  /// once.
  ElementsSteps get switches => _steps;
  set switches(ElementsSteps value) {
    _steps = value;
    fireView.steps = value.fire;
    for (final w in _waters) {
      w.view.steps = value.liquid;
    }
    if (!value.sound) _silence();
  }

  ElementsSteps _steps = ElementsSteps.all;

  void _silence() {
    final ears = hearing;
    if (ears == null) return;
    ears.fires.clear();
    ears.falls.clear();
    ears.splashes.clear();
  }

  /// The fires in the camera's picture as of the last update given one.
  final Set<NativeBody> _inSight = <NativeBody>{};

  /// [ElementsSimulation.heatFluxAt].
  double heatFluxAt(Vector3 at) => simulation.heatFluxAt(at);

  /// The share of a person's tolerance [flux] W/m² uses up a second,
  /// ISO 13571:2012's: nothing at or below 2.5 kW/m² (§8.4), and above it
  /// the time to a second-degree burn t = 6.9·q^(−1.56) minutes, q in
  /// kW/m² (Eq. 7, after Wieczorek and Dembsey, 2001). A whole dose is a
  /// character's whole health. [FireExposure.burnDoseRate].
  static double burnDoseRate(double flux) => FireExposure.burnDoseRate(flux);

  /// [ElementsSimulation.waterAt].
  ({WaterBody water, NativeShallowSample sample})? waterAt(Vector3 at) =>
      simulation.waterAt(at);

  /// [ElementsSimulation.seenThroughSmoke].
  double seenThroughSmoke(Vector3 from, Vector3 to) =>
      simulation.seenThroughSmoke(from, to);

  void _watch(CameraNode camera, double aspect) {
    final l = listener;
    final m = camera.viewProjection(aspect);
    final now = <NativeBody>{};
    for (final f in world.fires()) {
      final middle = f.at + f.axis * (0.5 * f.reach);
      final c = m.transform(Vector4(middle.x, middle.y, middle.z, 1.0));
      final w = c.w;
      if (w > 0.0 && c.x.abs() <= w && c.y.abs() <= w) {
        now.add(f.body);
        if (!_inSight.contains(f.body)) l?.seen?.call(f);
      }
    }
    for (final gone in _inSight.difference(now)) {
      l?.lost?.call(gone);
    }
    _inSight
      ..clear()
      ..addAll(now);
  }

  final GraphicsDevice _device;
  Scene _scene;

  /// The scene it draws into; set again, everything it draws moves there.
  Scene get scene => _scene;
  set scene(Scene value) {
    if (identical(value, _scene)) return;
    for (final w in _waters) {
      for (final node in w.view.nodes) {
        final drawn = node.parent != null || identical(node.scene, _scene);
        node.removeFromParent();
        if (drawn) value.add(node);
      }
    }
    fireView.scene = value;
    _scene = value;
  }

  ({Vector3 along, Vector3 light})? _sun;
  ({Vector3 zenith, Vector3 horizon})? _sky;

  /// The sun every water is lit by: the direction its light travels, and
  /// its colour times its intensity.
  void sun({required Vector3 along, required Vector3 light}) {
    _sun = (along: along.clone(), light: light.clone());
    for (final w in _waters) {
      w.look.sun(along: along, light: light);
    }
  }

  /// The sky every water mirrors.
  void sky({required Vector3 zenith, required Vector3 horizon}) {
    _sky = (zenith: zenith.clone(), horizon: horizon.clone());
    for (final w in _waters) {
      w.look.sky(zenith: zenith, horizon: horizon);
    }
  }

  final ByteData _liquidBundle;

  /// The waters this draws, each with its view and look, in the order
  /// added.
  final List<_DrawnWater> _waters = <_DrawnWater>[];

  /// The looks kept on the bodies taken in, moved to them each [draw].
  final Map<TrackedBody, SceneNode> _looks = <TrackedBody, SceneNode>{};

  /// The look kept on [body] — what [addBody] or [track] was given — or
  /// null for none.
  SceneNode? lookOf(TrackedBody body) => _looks[body];

  /// What draws [water]: its surface, falling sheet, drops, mist and
  /// bubbles. Throws an [ArgumentError] for a water this does not draw.
  LiquidView viewOf(WaterBody water) => (_drawnOf(water)..show()).view;

  /// The look [water]'s surface is drawn with: its sun, its sky, its glow.
  /// Throws an [ArgumentError] for a water this does not draw.
  ///
  /// For a game that changes one water's look after pouring it, apart from
  /// the others [sun] and [sky] light together: a lava pool that cools and
  /// stops glowing, a pond that silts up and darkens. It was the water's own
  /// `look` field before the simulation and its views were split.
  LiquidLook waterLookOf(WaterBody water) => _drawnOf(water).look;

  _DrawnWater _drawnOf(WaterBody water) {
    for (final w in _waters) {
      if (identical(w.water, water)) return w;
    }
    throw ArgumentError.value(water, 'water', 'not drawn by these elements');
  }

  /// The events of the last step.
  List<NativeEvent> get events => simulation.events;

  /// The wind everywhere, m/s, unless a wind grid says otherwise; the water
  /// roughens with it as Cox and Munk measured.
  Vector3 get wind => world.windAt(Vector3.zero());
  set wind(Vector3 value) {
    world.wind = value;
    for (final w in _waters) {
      w.look.wind = value.length;
    }
  }

  /// A water of [liquid] over [ground], held back by [bed], drawn with its
  /// own look; [mist] where water falls into it.
  WaterBody addWater({
    required ElementHeightfield ground,
    required Liquid liquid,
    required Bed bed,
    MistSettings? mist,
    LiquidDetail? detail,
  }) {
    final water = simulation.addWater(
      ground: ground,
      properties: liquid.properties,
      heat: liquid.heatIn(world),
      bed: bed,
    );
    final native = water.native;
    final look = LiquidLook.of(_liquidBundle)
      ..optics = liquid.optics
      ..wind = wind.length;
    final glow = liquid.glow;
    if (glow != null) look.glow = glow;
    final sun = _sun, sky = _sky;
    if (sun != null) look.sun(along: sun.along, light: sun.light);
    if (sky != null) look.sky(zenith: sky.zenith, horizon: sky.horizon);
    final view = LiquidView(
      world: world,
      liquid: native,
      ground: ground.heights,
      device: _device,
      scene: _scene,
      look: look.material,
      detail: detail ?? quality.liquid,
      mist: mist,
      properties: liquid.properties,
    );
    view.steps = _steps.liquid;
    _waters.add(_DrawnWater(water, view, look));
    hearing?.listen(native, density: liquid.properties.density);
    return water;
  }

  /// [solid] at [at], turned [turn], moving at [velocity] and spinning at
  /// [spin], drawn by [look]: dynamic, or [type]. [friction] and
  /// [restitution] as the core takes them, and what it collides with by
  /// [layer] and [mask]. [chars] — the look itself when it is a mesh — is
  /// blackened and glows as the body burns.
  TrackedBody addBody(
    Solid solid, {
    required Vector3 at,
    Quaternion? turn,
    Vector3? velocity,
    Vector3? spin,
    SceneNode? look,
    MeshNode? chars,
    NativeBodyType type = NativeBodyType.dynamic,
    double? friction,
    double? restitution,
    ({int layer, int mask})? collides,
  }) {
    final native = simulation.addBody(
      solid,
      at: at,
      turn: turn,
      velocity: velocity,
      spin: spin,
      type: type,
      friction: friction,
      restitution: restitution,
      collides: collides,
    );
    return track(
      native,
      look: look,
      chars: solid.material.ignitionTemperature > 0
          ? chars ?? (look is MeshNode ? look : null)
          : null,
    );
  }

  /// Fixed ground shaped as the triangles [indices] of [vertices], in the
  /// world, made of [material]: a level's floor and walls, a terrain.
  NativeBody addGround(
    List<Vector3> vertices,
    List<int> indices, {
    NativeMaterial? material,
  }) {
    final native = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
    );
    world.setMesh(native, world.createMesh(vertices, indices));
    if (material != null) world.setMaterial(native, material);
    return native;
  }

  /// A body made through [world] — the game's own, in a world it adopted —
  /// taken in: [look] kept on it ([lookOf]), [chars] blackened as it burns.
  TrackedBody track(NativeBody native, {SceneNode? look, MeshNode? chars}) {
    final body = simulation.track(native);
    if (look != null) _looks[body] = look;
    if (chars != null) fireView.watch(native, chars);
    return body;
  }

  /// [ElementsSimulation.follow].
  Follower follow(
    ElementPose Function() pose, {
    required NativeShape shape,
    ({int layer, int mask})? collides,
  }) => simulation.follow(pose, shape: shape, collides: collides);

  /// [thing] — a [TrackedBody], a [Follower] or a [WaterBody] — taken out.
  void remove(Object thing) {
    switch (thing) {
      case TrackedBody(:final native):
        fireView.forget(native);
        _looks.remove(thing);
        simulation.remove(thing);
      case Follower():
        simulation.remove(thing);
      case WaterBody(:final native):
        for (final w in _waters.where((w) => identical(w.water, thing))) {
          w.view.dispose();
        }
        _waters.removeWhere((w) => identical(w.water, thing));
        hearing?.unlisten(native);
        simulation.remove(thing);
    }
  }

  /// [dt] seconds on: [simulation] stepped ([ElementsSimulation.step]),
  /// then [draw]n from [eye], whose pixels span [pixel] radians. A game
  /// stepping a world it adopted, which reads the world's events itself,
  /// hands them in as [events]; otherwise they are read here.
  void update(
    double dt, {
    required Vector3 eye,
    double pixel = 0.001,
    List<NativeEvent>? events,
    CameraNode? camera,
    double aspect = 16 / 9,
  }) {
    if (dt <= 0) return;
    simulation.step(dt, events: events);
    draw(dt, eye: eye, pixel: pixel, camera: camera, aspect: aspect);
  }

  /// Draws and sounds what [simulation] last stepped, [dt] seconds after the
  /// last drawing, from [eye]: the bodies' looks moved to their bodies, each
  /// element drawn — water, fire, then a plugin's while it is on — the
  /// sounds, the budget and what the camera sees. Changes nothing a step
  /// reads.
  void draw(
    double dt, {
    required Vector3 eye,
    double pixel = 0.001,
    CameraNode? camera,
    double aspect = 16 / 9,
  }) {
    if (dt <= 0) return;
    for (final b in simulation.bodies) {
      final look = _looks[b];
      if (look == null) continue;
      look
        ..setPositionFrom(world.localPositionOf(b.native))
        ..setRotation(world.orientationOf(b.native));
    }
    final frame = ElementFrame(
      dt: dt,
      clock: simulation.clock,
      eye: eye,
      pixel: pixel,
      events: events,
      switches: _steps,
    );
    // Water and fire, drawn first and whatever the plugin switches say.
    for (final w in _waters) {
      w.look.update(seconds: frame.clock, eye: frame.eye, pixel: frame.pixel);
      w
        ..show()
        ..view.update(frame.dt);
    }
    fireView.update(frame.dt);
    for (final hook in List.of(_views)) {
      if (_steps.isOn(hook.id, byDefault: hook.switchedBy.onByDefault)) {
        hook.view(frame);
      }
    }
    if (_steps.sound) hearing?.update(dt, events: events);
    final l = listener;
    if (l?.budget != null) {
      for (final (step, wanted, holds) in fireView.wanted) {
        if (wanted > holds) l!.budget!(step, wanted, holds);
      }
      for (final w in _waters) {
        for (final (step, wanted, holds) in w.view.wanted) {
          if (wanted > holds) l!.budget!(step, wanted, holds);
        }
      }
    }
    if (camera != null) _watch(camera, aspect);
  }

  /// Everything taken out, and a world of its own let go.
  void dispose() {
    for (final w in _waters.toList()) {
      remove(w.water);
    }
    simulation.dispose();
  }
}

/// A water [Elements] draws: the simulation's [water], the [view] that
/// draws it and the [look] its surface is drawn with.
final class _DrawnWater {
  _DrawnWater(this.water, this.view, this.look) : _shown = water.ground;

  final WaterBody water;
  final LiquidView view;
  final LiquidLook look;

  /// The ground [view] was last given.
  ElementHeightfield _shown;

  /// [view] given the ground [water] stands on now, when it was dug or
  /// built up since ([WaterBody.setGround]).
  void show() {
    final ground = water.ground;
    if (identical(ground, _shown)) return;
    _shown = ground;
    view.ground = ground.heights;
  }
}

/// An [Elements]' drawing as a view plugin: once a frame, in the `animate`
/// phase, what its simulation last stepped drawn from where [eye] says.
///
/// **Touches only the view**, so it may be switched on and off without a
/// replay noticing; it steps nothing.
final class ElementsViewPlugin extends Flutter3dPlugin {
  ElementsViewPlugin(
    this.elements, {
    required this.eye,
    this.camera,
    this.id = 'elements.view',
  });

  final Elements elements;

  /// Where the camera is this frame: origin-local, as the elements'
  /// positions are (see [ElementPose]).
  final Vector3 Function() eye;

  /// The camera, for what comes into its picture; null for none.
  final CameraNode? Function()? camera;

  final String id;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.view,
    description: 'water, fire and bodies, drawn and heard',
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem(
      '$id.draw',
      LoopPhase.animate,
      (LoopContext context) =>
          elements.draw(context.realDt, eye: eye(), camera: camera?.call()),
    );
  }
}
