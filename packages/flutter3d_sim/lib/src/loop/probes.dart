/// Instruments in the simulation: [Probe], where it reads and what, the
/// [ProbeSampler]s that read a quantity, and the loop's reading of them.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        CompiledExpression,
        Expression,
        ExpressionCodec,
        ExpressionScope,
        ExpressionSyntaxException;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../ecs/material_state_component.dart';
import 'engine_loop.dart';

/// Where a [Probe] reads: a point of the world, a section through it, or
/// the body the probe is on.
///
/// **An open set, added to by this package.** A volume comes with the
/// fields of a later release; a `switch` over a region ends with a
/// wildcard. A region a later build wrote that this one does not know is
/// kept as it was written ([kind] names it) and read by nothing.
abstract final class ProbeRegion {
  const ProbeRegion();

  /// The wire name: `point`, `section`, `body`, or a later build's.
  String get kind;

  Map<String, Object?> toJson();

  /// Reads what [toJson] wrote. A kind this build does not know is kept.
  /// Throws a [PluginFormatException] for a known kind that is not what it
  /// says.
  static ProbeRegion fromJson(Object? json) {
    Never wrong(String what) =>
        throw PluginFormatException('a probe region $what', json);
    WorldPosition at(String key) => switch (json is Map ? json[key] : null) {
      [final num x, final num y, final num z] => WorldPosition(
        x.toDouble(),
        y.toDouble(),
        z.toDouble(),
      ),
      _ => wrong('has no "$key" of three numbers'),
    };
    return switch (json) {
      {'kind': 'point'} => ProbePoint(at('at')),
      {'kind': 'section'} => ProbeSection(
        origin: at('origin'),
        normal: at('normal'),
      ),
      {'kind': 'body'} => const ProbeBody(),
      {'kind': final String kind} => _KeptRegion(
        kind,
        Map<String, Object?>.unmodifiable(
          (json as Map).cast<String, Object?>(),
        ),
      ),
      _ => wrong('names no kind'),
    };
  }
}

/// One point of the world, in its own double-precision frame.
final class ProbePoint extends ProbeRegion {
  const ProbePoint(this.at);

  final WorldPosition at;

  @override
  String get kind => 'point';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'at': <double>[at.x, at.y, at.z],
  };
}

/// A plane through the world: what crosses it (a flow through a pipe's
/// section) or what lies on it (a temperature map).
final class ProbeSection extends ProbeRegion {
  /// The plane through [origin] facing [normal], which need not be of
  /// unit length; its direction is what counts.
  const ProbeSection({required this.origin, required this.normal});

  final WorldPosition origin;

  /// The plane's facing, as three numbers in the world's frame.
  final WorldPosition normal;

  @override
  String get kind => 'section';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'origin': <double>[origin.x, origin.y, origin.z],
    'normal': <double>[normal.x, normal.y, normal.z],
  };
}

/// The body the probe is on: the entity carrying the [Probe].
final class ProbeBody extends ProbeRegion {
  const ProbeBody();

  @override
  String get kind => 'body';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind};
}

final class _KeptRegion extends ProbeRegion {
  const _KeptRegion(this.kind, this._json);

  @override
  final String kind;

  final Map<String, Object?> _json;

  @override
  Map<String, Object?> toJson() => _json;
}

/// An instrument in the simulation: a quantity read at a region every
/// step, published as a [ProbeReading] and written on the run's tape.
///
/// **A component, declared in the simulation.** An entity carrying a probe
/// is read at the end of every step, after the `publish` phase's systems,
/// and what it read reaches the view as `PublishedState.probes`: a gauge,
/// a chart or a lesson's question reads that, and never the world, so it
/// works the same when the simulation runs in another isolate or on a
/// server. Reading changes nothing in the world: the probe itself is part
/// of the state (saved, snapshotted, digested as any component is), and
/// what it reads is not.
///
/// **What it reads** is [quantity], an id from the same space as a body's
/// material state (`f3d.temperature`, `<pluginId>.charring`): a
/// [ProbeSampler] registered for it answers, or, at a [ProbeBody], the
/// body's `MaterialStateComponent` does, and `f3d.position` reads where
/// the body is. [unit] is the unit it is reported in.
///
/// **[derived], when given, is what is published instead**: an expression
/// of the language in `flutter3d_foundation` over `x`, the quantity read,
/// and `t`, the simulated seconds, written as text (`x * 1.8 + 32` would be
/// a Fahrenheit reading, if units allowed it; `x / 0.1 [m^2]` a pressure
/// from a force). It is parsed once when the probe is made, compiled once,
/// and its reading is in the coherent unit of its result's dimension.
final class Probe {
  /// A probe [id], reading [quantity] in [unit] at [region]. Throws an
  /// [ExpressionSyntaxException] for a [derived] that does not read in that
  /// scope, and an [ArgumentError] for an empty id.
  Probe({
    required this.id,
    required this.quantity,
    required this.unit,
    this.region = const ProbeBody(),
    String? derived,
  }) : derivedExpression = derived == null
           ? null
           : ExpressionCodec(scope: scopeFor(unit)).decode(derived) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'empty');
    if (quantity.isEmpty) {
      throw ArgumentError.value(quantity, 'quantity', 'empty');
    }
  }

  /// The id of where a body is, as a quantity a probe at a [ProbeBody]
  /// reads: three components in metres, from the body's [WorldPosition].
  static const String positionId = 'f3d.position';

  /// Its id, unique in the simulation: what its readings are named by.
  final String id;

  /// What it reads, by quantity id.
  final String quantity;

  /// The unit [quantity] is reported in, and the unit of `x` in [derived].
  final Unit unit;

  /// Where it reads.
  final ProbeRegion region;

  /// [derived] as the language's tree, or null for a probe that publishes
  /// what it reads.
  final Expression? derivedExpression;

  /// [derivedExpression] as canonical text, or null.
  String? get derived => switch (derivedExpression) {
    null => null,
    final expression => ExpressionCodec(
      scope: scopeFor(unit),
    ).encode(expression),
  };

  /// [derivedExpression], compiled the first time it is read.
  late final CompiledExpression? compiled = switch (derivedExpression) {
    null => null,
    final expression => CompiledExpression(expression),
  };

  /// What a [derived] expression reads in: `x` in [unit], `t` in seconds.
  static ExpressionScope scopeFor(Unit unit) =>
      ExpressionScope.quantities(<String, Unit>{'x': unit, 't': Unit.second});

  /// How a probe is written in a snapshot or a level: `{"id", "quantity",
  /// "unit", "region", "derived"}`.
  static final ComponentCodec<Probe> codec = ComponentCodec<Probe>.of(
    id: 'flutter3d.probe',
    encode: (probe) => probe.toJson(),
    decode: (context) {
      final data = context.data;
      return data is Map ? Probe.fromJson(data) : null;
    },
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'quantity': quantity,
    'unit': unit.toJson(),
    'region': region.toJson(),
    'derived': ?derived,
  };

  /// Reads what [toJson] wrote. Throws a [PluginFormatException] naming
  /// what is wrong, an expression that does not read among it.
  factory Probe.fromJson(Map<Object?, Object?> json) {
    Never wrong(String what) =>
        throw PluginFormatException('a probe $what', json);
    final id = json['id'];
    final quantity = json['quantity'];
    if (id is! String || id.isEmpty) wrong('names no id');
    if (quantity is! String || quantity.isEmpty) {
      wrong('"$id" names no quantity');
    }
    final derived = json['derived'];
    if (derived != null && derived is! String) {
      wrong('"$id" has a derived expression that is not text');
    }
    try {
      return Probe(
        id: id,
        quantity: quantity,
        unit: Unit.fromJson(json['unit']),
        region: json['region'] == null
            ? const ProbeBody()
            : ProbeRegion.fromJson(json['region']),
        derived: derived as String?,
      );
    } on ExpressionSyntaxException catch (error) {
      wrong('"$id" has a derived expression that does not read: $error');
    } on PluginFormatException {
      rethrow;
    } on Flutter3dFormatException catch (error) {
      wrong('"$id" has a unit this build cannot read: $error');
    }
  }

  @override
  String toString() => 'Probe($id: $quantity in $unit at ${region.kind})';
}

/// What a [ProbeSampler] is told about the reading asked of it.
///
/// **One object rather than parameters, so it can grow**: a field here
/// breaks no sampler. Made by the engine: `base`, so a member added later
/// arrives with a default.
abstract base class ProbeSample {
  const ProbeSample();

  /// The probe being read.
  Probe get probe;

  /// The entity carrying it.
  Entity get entity;

  /// The simulation's world, to read and not to change.
  SimWorld get world;

  /// The step just run.
  int get step;

  /// Simulated seconds at the end of [step].
  double get seconds;
}

/// Reads one quantity for a probe: a field's value at a point, a flow
/// through a section, a solver's own number for a body.
///
/// `base`, so a member added later arrives with a default; [sample] takes
/// one growing context.
abstract base class ProbeSampler {
  const ProbeSampler();

  /// A sampler that calls [sample].
  const factory ProbeSampler.of(Quantity? Function(ProbeSample sample) sample) =
      _FunctionSampler;

  /// The quantity at the probe's region, or null where there is none to
  /// read: no reading is published for that step.
  Quantity? sample(ProbeSample sample);
}

final class _FunctionSampler extends ProbeSampler {
  const _FunctionSampler(this._sample);

  final Quantity? Function(ProbeSample sample) _sample;

  @override
  Quantity? sample(ProbeSample sample) => _sample(sample);
}

/// The samplers of one engine, by quantity id: a solver that owns a
/// quantity registers what reads it. `host.registry<ProbeSamplers>()`.
final class ProbeSamplers extends PluginRegistry {
  ProbeSamplers() : _scope = null, _byQuantity = <String, ProbeSampler>{};

  ProbeSamplers._scoped(ProbeSamplers of, PluginScope scope)
    : _scope = scope,
      _byQuantity = of._byQuantity;

  final PluginScope? _scope;
  final Map<String, ProbeSampler> _byQuantity;

  /// Reads [quantity] with [sampler] from now on. Throws an [ArgumentError]
  /// for a quantity another sampler already reads.
  Registration add(String quantity, ProbeSampler sampler) {
    // A plugin reads the quantities it owns, which are in its namespace.
    if (_scope?.manifest.nameProblem(quantity, what: 'the probe quantity')
        case final problem?) {
      throw PluginException(problem);
    }
    if (_byQuantity.containsKey(quantity)) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'already has a sampler; one reads each quantity',
      );
    }
    _byQuantity[quantity] = sampler;
    final registration = Registration(() => _byQuantity.remove(quantity));
    _scope?.track(registration);
    return registration;
  }

  /// The sampler reading [quantity], or null for none.
  ProbeSampler? forQuantity(String quantity) => _byQuantity[quantity];

  @override
  ProbeSamplers forPlugin(PluginScope scope) =>
      ProbeSamplers._scoped(this, scope);
}

/// Reads every probe in [world] at the end of [step], in ascending entity
/// order: what the loop publishes and a trace records.
List<ProbeReading> readProbes(
  SimWorld world,
  ProbeSamplers samplers, {
  required int step,
  required double seconds,
}) {
  final probed = world.query().having<Probe>().entities.toList();
  if (probed.isEmpty) return const <ProbeReading>[];
  probed.sort((a, b) => a.index.compareTo(b.index));
  final sample = _Sample(world, step, seconds);
  return <ProbeReading>[
    for (final entity in probed)
      ?_read(world.get<Probe>(entity)!, entity, samplers, sample),
  ];
}

ProbeReading? _read(
  Probe probe,
  Entity entity,
  ProbeSamplers samplers,
  _Sample sample,
) {
  sample
    ..probe = probe
    ..entity = entity;
  final body = probe.region is ProbeBody;
  if (body && probe.quantity == Probe.positionId) {
    final at = sample.world.get<WorldPosition>(entity);
    if (at == null) return null;
    return ProbeReading(
      probe: probe.id,
      step: sample.step,
      value: <double>[at.x, at.y, at.z],
      unit: Unit.meter,
    );
  }
  final read =
      samplers.forQuantity(probe.quantity)?.sample(sample) ??
      (body
          ? sample.world
                .get<MaterialStateComponent>(entity)
                ?.state[probe.quantity]
          : null);
  if (read == null) return null;
  final compiled = probe.compiled;
  final value = compiled == null
      ? Quantity(read.valueIn(probe.unit), probe.unit)
      : compiled.quantity(<String, Object>{
          'x': read,
          't': Quantity(sample.seconds, Unit.second),
        });
  return ProbeReading(
    probe: probe.id,
    step: sample.step,
    value: <double>[value.value],
    unit: value.unit,
  );
}

final class _Sample extends ProbeSample {
  _Sample(this.world, this.step, this.seconds);

  @override
  final SimWorld world;

  @override
  final int step;

  /// Simulated seconds at the end of [step].
  @override
  final double seconds;

  @override
  late Probe probe;

  @override
  late Entity entity;
}

/// What a run's probes read, step by step: the `probes` a run file writes
/// beside its tape (`Demo.probes`).
///
/// **Outputs, kept with the inputs.** A replay computes them again, so the
/// trace is for what does not replay: a chart drawn from a run file on a
/// build that refuses its tape, a lesson's answer checked without stepping,
/// a twin's history scrubbed from disk.
final class ProbeTrace {
  /// Every reading recorded, in step order.
  List<ProbeReading> get readings => List<ProbeReading>.unmodifiable(_readings);

  final List<ProbeReading> _readings = <ProbeReading>[];

  /// Records what [loop]'s probes read after every step from now on. A step
  /// run again after a rewind replaces what was recorded for it and after
  /// it, so the trace holds the run as it finally went.
  Registration record(EngineLoop loop) => loop.onStepEnd((_) {
    final readings = loop.probeReadings;
    if (readings.isEmpty) return;
    final step = readings.first.step;
    _readings
      ..removeWhere((reading) => reading.step >= step)
      ..addAll(readings);
  });
}
