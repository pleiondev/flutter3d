/// A new element, written in Dart, over the elements' world: what a plugin
/// element is, and how one is put into a loop or into an `Elements`.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        Capability,
        Dimension,
        Quantity,
        Unit,
        UnitMismatchException,
        UnsupportedCapabilityException,
        WorldPositionVector;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import 'element_events.dart';
import 'switches.dart' show ElementsSteps;

/// A body of the elements' world, as an element names it: the backend's
/// handle, as a number.
///
/// **Backend-neutral.** An element written against [ElementFields] never
/// names the physics core; the core's world ([NativeElementFields]) reads
/// this as its `NativeBody` of the same number, and another backend as its
/// own. [ElementBody.of] and [native] cross to the core for a hook that
/// knows it runs there.
extension type const ElementBody(int id) {
  /// The core's [body] as an element names it.
  ElementBody.of(NativeBody body) : id = body.raw;

  /// This body as the core names it.
  NativeBody get native => NativeBody(id);
}

/// The world's fields as an element reads and writes them: heat, water,
/// wind and the forces on bodies.
///
/// **Backend-neutral** (item 19): an element's step reads and writes these
/// and nothing of a renderer or of the core, so it runs headless, on a
/// server, and on whatever backend steps the world. The physics core's
/// world is [NativeElementFields]; a test's or another backend's extends
/// this.
///
/// A write here is a write to the world's next step. Positions are
/// [WorldPosition]s, in the world; directions, velocities and forces are
/// float32 vectors.
///
/// **Extended outside this package: an `abstract base class` with a body
/// for every member.** A backend overrides what its world has; anything
/// else is refused with an [UnsupportedCapabilityException] naming the member, so a
/// member added in a minor breaks no backend written against 1.0, and a
/// backend with no water says so when water is asked for rather than
/// failing to compile.
///
/// **By quantity, too** ([quantityOf], [addQuantity]): a field named by a
/// [FieldQuantity] and carried as a foundation [Quantity], in its unit. The
/// fields above answer through it by default; a field this class has no
/// member for — humidity, pressure, a concentration — arrives as a new
/// [FieldQuantity] a backend answers, without a new member here.
abstract base class ElementFields {
  const ElementFields();

  /// The refusal of [member], which this backend does not answer.
  UnsupportedCapabilityException _refuse(String member) =>
      UnsupportedCapabilityException(
        _Member('ElementFields.$member'),
        backend: '$runtimeType',
      );

  // Air and wind.

  /// The air's temperature, K: kelvins, degrees Celsius plus 273.15.
  double get airTemperature => throw _refuse('airTemperature');

  /// The air's density, kg/m³.
  double get airDensity => throw _refuse('airDensity');

  /// The wind at [at], m/s.
  Vector3 windAt(WorldPosition at) => throw _refuse('windAt');

  /// The wind everywhere, unless a wind grid says otherwise.
  set wind(Vector3 value) => throw _refuse('wind');

  // Heat.

  /// [body]'s mean temperature, K.
  double temperatureOf(ElementBody body) => throw _refuse('temperatureOf');

  /// [body]'s surface temperature over the last step, K.
  double surfaceTemperatureOf(ElementBody body) =>
      throw _refuse('surfaceTemperatureOf');

  void setTemperature(ElementBody body, double kelvin) =>
      throw _refuse('setTemperature');

  /// Joules into [body] over the next step, or out of it.
  void addHeat(ElementBody body, double joules) => throw _refuse('addHeat');

  /// Joules into [body] where [point] is.
  void addHeatAt(ElementBody body, WorldPosition point, double joules) =>
      throw _refuse('addHeatAt');

  // Water.

  /// Kilograms of water on [body].
  double waterOf(ElementBody body) => throw _refuse('waterOf');

  /// Kilograms of water onto [body], or off it.
  void addWater(ElementBody body, double kilograms) =>
      throw _refuse('addWater');

  /// The radiant heat falling on [body] from every fire, W/m²: each fire's
  /// on the point of [body] its flame sees, summed, and nothing from a fire
  /// something else stands between. What a character standing in the world
  /// is burnt by ([FieldQuantity.radiantFlux]).
  double radiantFluxOn(ElementBody body) => throw _refuse('radiantFluxOn');

  // Forces.

  /// A force on [body] over the next step, N.
  void addForce(ElementBody body, Vector3 force) => throw _refuse('addForce');

  /// An impulse on [body] now, N s, at [at] or through its middle.
  void applyImpulse(ElementBody body, Vector3 impulse, {WorldPosition? at}) =>
      throw _refuse('applyImpulse');

  /// Where [body] is, in the world.
  WorldPosition positionOf(ElementBody body) => throw _refuse('positionOf');

  /// [body]'s velocity, m/s.
  Vector3 velocityOf(ElementBody body) => throw _refuse('velocityOf');

  /// The bodies whose boxes meet the box from [lo] to [hi]: for whoever
  /// writes an element that acts on a region — a gust over a field, frost
  /// creeping across a floor.
  List<ElementBody> bodiesIn(WorldPosition lo, WorldPosition hi) =>
      throw _refuse('bodiesIn');

  // By quantity.

  /// [quantity] of [body], in the quantity's unit.
  ///
  /// By default [FieldQuantity.temperature] is [temperatureOf],
  /// [FieldQuantity.surfaceTemperature] [surfaceTemperatureOf],
  /// [FieldQuantity.water] [waterOf] and [FieldQuantity.radiantFlux]
  /// [radiantFluxOn]; anything else is refused with an
  /// [UnsupportedCapabilityException] naming it. A backend with more fields
  /// answers them here and hands the rest to `super`.
  Quantity quantityOf(ElementBody body, FieldQuantity quantity) =>
      Quantity(switch (quantity) {
        FieldQuantity.temperature => temperatureOf(body),
        FieldQuantity.surfaceTemperature => surfaceTemperatureOf(body),
        FieldQuantity.water => waterOf(body),
        FieldQuantity.radiantFlux => radiantFluxOn(body),
        _ => throw UnsupportedCapabilityException(
          quantity,
          backend: '$runtimeType',
        ),
      }, quantity.unit);

  /// [amount] of [quantity] into [body] over the next step, or out of it.
  ///
  /// [amount] is taken in its own unit and converted to the quantity's; one
  /// that measures something else is refused with a
  /// [UnitMismatchException]. By default [FieldQuantity.heat] is [addHeat]
  /// and [FieldQuantity.water] [addWater]; anything else is refused with an
  /// [UnsupportedCapabilityException] naming it.
  void addQuantity(ElementBody body, FieldQuantity quantity, Quantity amount) =>
      switch (quantity) {
        FieldQuantity.heat => addHeat(body, amount.valueIn(quantity.unit)),
        FieldQuantity.water => addWater(body, amount.valueIn(quantity.unit)),
        _ => throw UnsupportedCapabilityException(
          quantity,
          backend: '$runtimeType',
        ),
      };
}

/// A field of the elements' world an element reads or adds to by name: what
/// it is, and the unit [ElementFields] keeps it in.
///
/// **An open set**: the constants are the fields every backend of 1.0 has,
/// and a backend with humidity, pressure or a concentration names its own
/// (`FieldQuantity('humidity', Unit.percent)`) and answers it in
/// [ElementFields.quantityOf]. Two are the same field when their [name]s
/// are. A [Capability], so a backend that lacks one refuses it by name.
final class FieldQuantity extends Capability {
  const FieldQuantity(this.name, this.unit);

  /// A body's mean temperature, in kelvin.
  static const FieldQuantity temperature = FieldQuantity(
    'temperature',
    Unit.kelvin,
  );

  /// A body's surface temperature over the last step, in kelvin.
  static const FieldQuantity surfaceTemperature = FieldQuantity(
    'surfaceTemperature',
    Unit.kelvin,
  );

  /// Heat into or out of a body, in joules: added, not read.
  static const FieldQuantity heat = FieldQuantity('heat', Unit.joule);

  /// Water on a body, in kilograms.
  static const FieldQuantity water = FieldQuantity('water', Unit.kilogram);

  /// The radiant heat falling on a body, in watts a square metre: read, not
  /// added ([ElementFields.radiantFluxOn]).
  static const FieldQuantity radiantFlux = FieldQuantity(
    'radiantFlux',
    Unit('W/m²', Dimension(<String, int>{'kg': 1, 's': -3})),
  );

  /// The field's word in a file and a refusal.
  @override
  final String name;

  /// The unit [ElementFields] reads and adds it in.
  final Unit unit;

  @override
  String? get askedBy => 'ElementFields.quantityOf';

  @override
  bool operator ==(Object other) =>
      other is FieldQuantity && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'FieldQuantity($name, ${unit.symbol})';
}

/// A member of [ElementFields] as the capability a backend refuses.
final class _Member extends Capability {
  const _Member(this.name);

  @override
  final String name;
}

/// The physics core's world as [ElementFields], with what only the core
/// has — its fires, its waters — beside them.
final class NativeElementFields extends ElementFields {
  const NativeElementFields(this.world);

  /// The core's world: for what the fields do not name.
  final NativeWorld world;

  Vector3 _local(WorldPosition at) => at.toVector3Relative(world.origin);

  /// The core's air temperature, K: kelvins, degrees Celsius plus 273.15.
  @override
  double get airTemperature => world.airTemperature;

  /// The core's air density, kg/m³.
  @override
  double get airDensity => world.airDensity;

  @override
  Vector3 windAt(WorldPosition at) => world.windAt(_local(at));

  @override
  set wind(Vector3 value) => world.wind = value;

  @override
  double temperatureOf(ElementBody body) => world.temperatureOf(body.native);

  @override
  double surfaceTemperatureOf(ElementBody body) =>
      world.surfaceTemperatureOf(body.native);

  @override
  void setTemperature(ElementBody body, double kelvin) =>
      world.setTemperature(body.native, kelvin);

  @override
  void addHeat(ElementBody body, double joules) =>
      world.addHeat(body.native, joules);

  @override
  void addHeatAt(ElementBody body, WorldPosition point, double joules) =>
      world.addHeatAt(body.native, _local(point), joules);

  /// The fires burning now.
  List<NativeFire> fires() => world.fires();

  @override
  double waterOf(ElementBody body) => world.waterOf(body.native);

  @override
  void addWater(ElementBody body, double kilograms) =>
      world.addWater(body.native, kilograms);

  /// Each fire's radiant heat, Modak's point source at the middle of its
  /// flame ([FireExposure.fluxFrom]), on the first point of [body] a ray
  /// from there toward [body]'s middle meets; nothing from a fire whose ray
  /// meets another body first — a wall, a crate, a cart between — save the
  /// burning body itself. A body the ray misses altogether is taken at its
  /// middle.
  @override
  double radiantFluxOn(ElementBody body) {
    final target = body.native;
    final middle = world.localPositionOf(target);
    var total = 0.0;
    for (final fire in world.fires()) {
      if (fire.body == target) continue;
      final from = FireExposure.middleOf(fire);
      final toward = middle - from;
      final far = toward.length;
      if (far <= 0.0) {
        total += FireExposure.fluxFrom(fire, 0.0);
        continue;
      }
      toward.scale(1.0 / far);
      final hit = world.rayCast(from, toward, far, ignore: fire.body);
      if (hit != null && hit.body != target) continue;
      final at = hit?.at ?? far;
      total += FireExposure.fluxFrom(fire, at * at);
    }
    return total;
  }

  /// [water] at [at], or null off its grid (absent).
  NativeShallowSample? waterAt(NativeShallowLiquid water, WorldPosition at) {
    final local = _local(at);
    return world.sampleShallow(water, local.x, local.z);
  }

  @override
  void addForce(ElementBody body, Vector3 force) =>
      world.addForce(body.native, force);

  @override
  void applyImpulse(ElementBody body, Vector3 impulse, {WorldPosition? at}) =>
      world.applyImpulse(
        body.native,
        impulse,
        at: at == null ? null : _local(at),
      );

  @override
  WorldPosition positionOf(ElementBody body) => world.positionOf(body.native);

  @override
  Vector3 velocityOf(ElementBody body) => world.velocityOf(body.native);

  @override
  List<ElementBody> bodiesIn(WorldPosition lo, WorldPosition hi) =>
      <ElementBody>[
        for (final body in world.queryBox(_local(lo), _local(hi)))
          ElementBody.of(body),
      ];
}

/// What an element's step is told: the fields, the step, and where to say
/// what it did.
final class ElementStep {
  ElementStep({
    required this.fields,
    required this.dt,
    this.step = 0,
    this.resimulated = false,
    void Function(ElementEvent event)? publish,
  }) : _publish = publish; // ignore: prefer_initializing_formals

  final ElementFields fields;

  /// Seconds this step covers: the world's fixed step.
  final double dt;

  /// The step being run, counted by whoever runs it; nought when it does
  /// not count.
  final int step;

  /// Whether this step is being run again — a rollback, a scrub. The
  /// element steps as usual; it is told so it need not say twice what only
  /// a person would hear.
  final bool resimulated;

  final void Function(ElementEvent event)? _publish;

  /// Says that [kind] happened to [body] — and [other], for an event
  /// between two. Onto the step channel when the element runs in a loop;
  /// nowhere when nothing listens.
  void publish(NativeEventKind kind, ElementBody body, {ElementBody? other}) =>
      _publish?.call(
        ElementEvent(kind: kind, body: body.native, other: other?.native),
      );
}

/// What an element's view is told, once a frame.
final class ElementFrame {
  const ElementFrame({
    required this.dt,
    required this.clock,
    required this.eye,
    required this.pixel,
    required this.events,
    required this.switches,
  });

  /// Seconds since the last frame the view was drawn.
  final double dt;

  /// Seconds the elements have run, summed: what ripples and flickers.
  final double clock;

  /// Where the camera is.
  final Vector3 eye;

  /// Radians one of the picture's pixels spans.
  final double pixel;

  /// What the world said in its last step.
  final List<NativeEvent> events;

  /// Which steps are taken.
  final ElementsSteps switches;
}

/// A switch a plugin element answers to in [ElementsSteps], by [id].
final class ElementSwitch {
  const ElementSwitch(this.id, {this.onByDefault = true, this.description});

  /// The element's id, under which [ElementsSteps.isOn] is asked.
  final String id;

  /// Whether the element is drawn and heard when nobody said.
  final bool onByDefault;

  /// One sentence for a settings screen.
  final String? description;
}

/// A new element over the elements' world, written in Dart.
///
/// **Fire and water are two of these.** `Elements` holds its own fire and
/// water as hooks and runs them through the same three doors a plugin's
/// goes through, so what a plugin element can do is exactly what the
/// built-in ones do:
///
/// * **[step], in its own step phase.** It reads and writes the world's
///   fields — heat, water, wind, forces — through [ElementStep.fields],
///   once a fixed step, before the core's solver takes them. Installed in
///   a loop ([installElement]), its phase is [phase], after the engine's
///   `elements` phase and before `rules`.
/// * **[view], once a frame**, drawing and sounding what the step left.
///   Skipped while its switch ([ElementsSteps.isOn]) is off; the world
///   steps the same either way, so a switch never changes a run.
/// * **[save] and [restore]**, its own state for the run's snapshot —
///   whatever it keeps beside the world, which the world's own snapshot
///   does not hold.
///
/// ## The rules of a step
///
/// A step reads no clock and rolls no loose dice, and **its arithmetic is
/// `Portable`'s** (`flutter3d_physics`): `Portable.exp`, `Portable.pow`
/// and the rest give the same bits on every platform, where `dart:math`'s
/// transcendental functions do not. A replay recorded on a phone and
/// checked on a server rests on it; an element that reaches for
/// `math.exp` in its step is one whose runs part on another machine.
///
/// `base`, so a member added later arrives with a default: an element
/// `extends` this and is itself `final` or `base`.
abstract base class ElementHook {
  const ElementHook();

  /// Lower case, unique among the elements of one world: `'frost'`.
  String get id;

  /// The step phase this element runs in when installed in a loop.
  LoopPhase get phase => LoopPhase.step('elements.$id');

  /// The switch it answers to in [ElementsSteps].
  ElementSwitch get switchedBy => ElementSwitch(id);

  /// The event kinds it publishes, each at a code from
  /// `NativeEventKind.firstPluginCode` up.
  List<NativeEventKind> get eventKinds => const <NativeEventKind>[];

  /// One fixed step of the element over the world's fields.
  void step(ElementStep step) {}

  /// Draws and sounds the element, once a frame.
  void view(ElementFrame frame) {}

  /// What it keeps beside the world, as a value JSON can hold; null for
  /// nothing.
  Object? save() => null;

  /// Back to what [save] gave; anything else changes nothing.
  void restore(Object? saved) {}

  @override
  String toString() => 'element $id';
}

/// Puts [hook] into [loop]: its phase after the engine's `elements` and
/// before `rules`, and its step there over [world]'s fields.
///
/// [world] is asked at each step, since a game's world is the level's and
/// a level is replaced; a step with no world steps nothing. What the step
/// publishes goes onto the step channel. Two elements installed one after
/// the other run in that order. The one registration takes both out again.
Registration installElement(
  LoopRegistry loop,
  ElementHook hook, {
  required NativeWorld? Function() world,
}) {
  final phase = loop.addPhase(
    hook.phase,
    after: <String>[LoopPhase.fields.name],
    before: <String>[LoopPhase.rules.name],
  );
  final system = loop.addSystem('${hook.phase.name}.step', hook.phase, (
    LoopContext context,
  ) {
    final w = world();
    if (w == null || w.isDisposed) return;
    hook.step(
      ElementStep(
        fields: NativeElementFields(w),
        dt: context.dt,
        step: context.step,
        resimulated: context.isResimulated,
        publish: context.publish,
      ),
    );
  });
  return Registration(() {
    system.cancel();
    phase.cancel();
  });
}

/// One [ElementHook] as a plugin: its phase and step in the loop, its
/// switch among the engine's [ElementSwitches], its event kinds among the
/// engine's [ElementEventKinds] — each when the engine has that registry.
///
/// Its view is drawn by the `Elements` that draws the world
/// (`Elements.addElement(hook, step: false)`), which knows the camera; the
/// plugin steps it, which is the half a replay holds.
final class ElementPlugin extends Flutter3dPlugin {
  ElementPlugin(this.hook, {required this.world, String? id, this.dependsOn})
    : _id = id; // ignore: prefer_initializing_formals

  final ElementHook hook;

  /// The world the element steps over, asked each step.
  final NativeWorld? Function() world;

  /// Plugins that must be on before this one.
  final List<String>? dependsOn;

  final String? _id;

  @override
  PluginManifest get manifest => PluginManifest(
    id: _id ?? 'element.${hook.id}',
    apiVersion: PluginApiVersion.current,
    dependsOn: dependsOn ?? const <String>[],
    description: 'the ${hook.id} element, stepped over the world\'s fields',
  );

  @override
  void install(PluginHost host) {
    installElement(host.loop, hook, world: world);
    host.maybeRegistry<ElementSwitches>()?.declare(hook.switchedBy);
    final kinds = host.maybeRegistry<ElementEventKinds>();
    if (kinds != null) hook.eventKinds.forEach(kinds.add);
  }
}

/// The switches plugin elements answer to, one per element: what a settings
/// screen lists beside fire and water.
///
/// One per engine, handed to the loop among its registries; an element
/// declares its switch when it is installed, and two elements may not
/// declare one id.
final class ElementSwitches extends PluginRegistry {
  ElementSwitches();

  final List<({ElementSwitch declared, String owner})> _switches =
      <({ElementSwitch declared, String owner})>[];

  /// Every switch declared, in the order declared.
  List<ElementSwitch> get switches => <ElementSwitch>[
    for (final s in _switches) s.declared,
  ];

  /// The switch declared for [id], or null.
  ElementSwitch? operator [](String id) =>
      _switches.where((s) => s.declared.id == id).firstOrNull?.declared;

  /// Declares [declared] for the application. Throws an [ArgumentError]
  /// naming both claimants when its id is taken.
  Registration declare(ElementSwitch declared) => _declare(declared, null);

  Registration _declare(ElementSwitch declared, PluginScope? scope) {
    final owner = scope?.manifest.id ?? 'app';
    for (final existing in _switches) {
      if (existing.declared.id == declared.id) {
        throw ArgumentError.value(
          declared.id,
          'declared',
          'the element switch "${declared.id}" is declared by '
              '${existing.owner} and again by $owner; an element id is '
              'unique in one engine',
        );
      }
    }
    final entry = (declared: declared, owner: owner);
    _switches.add(entry);
    final registration = Registration(() => _switches.remove(entry));
    scope?.track(registration);
    return registration;
  }

  /// [steps] with every declared switch it does not set at its default:
  /// what a settings screen starts from.
  ElementsSteps defaults(ElementsSteps steps) => steps.copyWith(
    elements: <String, bool>{
      for (final s in _switches)
        if (!steps.elements.containsKey(s.declared.id))
          s.declared.id: s.declared.onByDefault,
      ...steps.elements,
    },
  );

  @override
  ElementSwitches forPlugin(PluginScope scope) => _ScopedSwitches(this, scope);
}

final class _ScopedSwitches extends ElementSwitches {
  _ScopedSwitches(this._of, this._scope);

  final ElementSwitches _of;
  final PluginScope _scope;

  @override
  List<ElementSwitch> get switches => _of.switches;

  @override
  ElementSwitch? operator [](String id) => _of[id];

  @override
  Registration declare(ElementSwitch declared) =>
      _of._declare(declared, _scope);

  @override
  ElementsSteps defaults(ElementsSteps steps) => _of.defaults(steps);

  @override
  ElementSwitches forPlugin(PluginScope scope) => _of.forPlugin(scope);
}
