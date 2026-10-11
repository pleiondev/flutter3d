/// `f3d.experiment`: a laboratory experiment written down — the level it
/// happens in, the substances it uses by id, the probes it reads, and a
/// scenario of steps with the readings each step expects.
library;

import 'dart:convert';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart' show MaterialCatalog;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Probe;

import 'check_question.dart';

/// The `f3d.experiment` version this build writes and the newest it reads.
const int experimentVersion = 1;

/// `f3d.experiment` in the format registry.
const FormatSpec experimentFormat = FormatSpec(
  id: 'f3d.experiment',
  version: experimentVersion,
  suffixes: <String>['.f3d.experiment'],
  fixture: 'test/fixtures/v<N>/pendulum.f3d.experiment',
);

/// A substance the experiment uses, by its id in the materials catalog
/// (`f3d.water`, `<pluginId>.brine`), and what it is for.
final class ExperimentSubstance {
  /// Throws an [ArgumentError] for an empty [id].
  ExperimentSubstance({required this.id, this.role}) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'empty');
  }

  /// The catalog id. A reader resolves it against the catalog it runs with
  /// and refuses one it does not hold, naming it.
  final String id;

  /// What the experiment uses it as, in the author's words (`bob`,
  /// `solvent`), or null.
  final String? role;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'role': ?role};
}

/// A number the experiment can be run with: a pendulum's length, a
/// solution's concentration. A step sets it; a student's panel changes it
/// within [min] and [max].
final class ExperimentParameter {
  /// Throws an [ArgumentError] for an empty [id], or for a bound in a unit
  /// that does not measure what [value] does.
  ExperimentParameter({
    required this.id,
    required this.value,
    this.min,
    this.max,
  }) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'empty');
    for (final bound in <Quantity?>[min, max]) {
      if (bound != null && !bound.unit.isCompatibleWith(value.unit)) {
        throw ArgumentError.value(
          bound.unit.symbol,
          'bound',
          'does not measure what ${value.unit.symbol} does',
        );
      }
    }
  }

  /// Its name, unique in the document: what a step's `set` names.
  final String id;

  /// The value the experiment starts with.
  final Quantity value;

  /// The least and the most it may be set to, or null for no bound.
  final Quantity? min;
  final Quantity? max;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'value': value.toJson(),
    if (min case final Quantity bound) 'min': bound.toJson(),
    if (max case final Quantity bound) 'max': bound.toJson(),
  };
}

/// A probe the experiment reads, and the level entity it is on.
final class ExperimentProbe {
  const ExperimentProbe({required this.probe, this.on});

  /// The instrument: what it reads, in which unit, where.
  final Probe probe;

  /// The name of the level entity carrying the probe, or null for one that
  /// reads a point or a section of the world rather than a body.
  final String? on;

  /// The probe's id: what an expected reading names.
  String get id => probe.id;

  Map<String, Object?> toJson() => <String, Object?>{
    ...probe.toJson(),
    'on': ?on,
  };
}

/// A reading a step expects from a probe when it ends: [value] within
/// [tolerance].
final class ExpectedReading {
  /// Throws an [ArgumentError] when [tolerance] does not measure what
  /// [value] does, or is negative.
  ExpectedReading({
    required this.probe,
    required this.value,
    required this.tolerance,
  }) {
    if (!tolerance.unit.isCompatibleWith(value.unit)) {
      throw ArgumentError.value(
        tolerance.unit.symbol,
        'tolerance',
        'does not measure what ${value.unit.symbol} does',
      );
    }
    if (tolerance.value < 0) {
      throw ArgumentError.value(tolerance.value, 'tolerance', 'negative');
    }
  }

  /// The id of the probe read.
  final String probe;

  /// What it should read.
  final Quantity value;

  /// How far from [value] a reading may be and still agree, as a
  /// difference: 5 mK, not a temperature.
  final Quantity tolerance;

  /// Whether [reading] agrees. Throws a [UnitMismatchException] for a
  /// reading of another dimension.
  bool agrees(Quantity reading) =>
      (reading.valueIn(value.unit) - value.value).abs() <=
      tolerance.value * tolerance.unit.scale / value.unit.scale;

  Map<String, Object?> toJson() => <String, Object?>{
    'probe': probe,
    'value': value.toJson(),
    'tolerance': tolerance.toJson(),
  };
}

/// One step of a scenario: the parameters it sets, how long the
/// simulation then runs, what the probes should read at its end, and a
/// question it may ask.
final class ExperimentStep {
  /// Throws an [ArgumentError] for an empty [name] or a [run] that is not
  /// a time.
  ExperimentStep({
    required this.name,
    this.title,
    Map<String, Quantity> set = const <String, Quantity>{},
    this.run,
    List<ExpectedReading> expect = const <ExpectedReading>[],
    this.check,
  }) : set = Map<String, Quantity>.unmodifiable(set),
       expect = List<ExpectedReading>.unmodifiable(expect) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name', 'empty');
    if (run case final Quantity time
        when !time.unit.isCompatibleWith(Unit.second)) {
      throw ArgumentError.value(time.unit.symbol, 'run', 'is not a time');
    }
  }

  /// Its name, unique in the scenario.
  final String name;

  /// What a student reads for it, or null.
  final String? title;

  /// The parameters it sets as it begins, by id.
  final Map<String, Quantity> set;

  /// How long the simulation runs in it, or null for a step that only
  /// sets or asks.
  final Quantity? run;

  /// What the probes should read when it ends.
  final List<ExpectedReading> expect;

  /// The question it asks, or null.
  final CheckQuestion? check;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'title': ?title,
    if (set.isNotEmpty)
      'set': <String, Object?>{
        for (final MapEntry(:key, :value) in set.entries) key: value.toJson(),
      },
    if (run case final Quantity time) 'run': time.toJson(),
    if (expect.isNotEmpty)
      'expect': <Object?>[for (final reading in expect) reading.toJson()],
    if (check case final CheckQuestion question) 'check': question.toJson(),
  };
}

/// A parameter the experiment does not know and an inverse run estimates
/// from [ExperimentDocument.observations]: where it may lie, and what is
/// believed of it before.
///
/// Read and written in this version; nothing here estimates yet.
final class ExperimentUnknown {
  /// Throws an [ArgumentError] when [min] and [max] measure different
  /// things.
  ExperimentUnknown({
    required this.parameter,
    required this.min,
    required this.max,
    Map<String, Object?> prior = const <String, Object?>{},
  }) : prior = Map<String, Object?>.unmodifiable(prior) {
    if (!min.unit.isCompatibleWith(max.unit)) {
      throw ArgumentError.value(
        max.unit.symbol,
        'max',
        'does not measure what ${min.unit.symbol} does',
      );
    }
  }

  /// The id of the parameter it is.
  final String parameter;

  /// Where it may lie.
  final Quantity min;
  final Quantity max;

  /// What is believed of it before any observation, as written
  /// (`{"kind": "uniform"}`); empty for nothing.
  final Map<String, Object?> prior;

  Map<String, Object?> toJson() => <String, Object?>{
    'parameter': parameter,
    'min': min.toJson(),
    'max': max.toJson(),
    if (prior.isNotEmpty) 'prior': prior,
  };
}

/// A reading taken of the real thing: a probe's [value] at [at] seconds of
/// the scenario, with its [uncertainty].
///
/// Read and written in this version; nothing here estimates yet.
final class ExperimentObservation {
  /// Throws an [ArgumentError] when [at] is not a time.
  ExperimentObservation({
    required this.probe,
    required this.at,
    required this.value,
    this.uncertainty,
  }) {
    if (!at.unit.isCompatibleWith(Unit.second)) {
      throw ArgumentError.value(at.unit.symbol, 'at', 'is not a time');
    }
  }

  /// The id of the probe it was read as.
  final String probe;

  /// When, from the start of the scenario.
  final Quantity at;

  /// What was read.
  final Quantity value;

  /// How far it may be off, as a difference, or null for unstated.
  final Quantity? uncertainty;

  Map<String, Object?> toJson() => <String, Object?>{
    'probe': probe,
    'at': at.toJson(),
    'value': value.toJson(),
    if (uncertainty case final Quantity spread) 'uncertainty': spread.toJson(),
  };
}

/// A laboratory experiment as a document (D31): the level it happens in,
/// the substances it uses by id, the probes it reads and a scenario of
/// steps with expected readings — what `flutter3d_education` reads, the
/// editor edits and a lesson viewer plays.
///
/// **Ids, not values.** A substance is a catalog id, a probe is named by
/// its id, a step sets a parameter by id: the document says what an
/// experiment is made of and leaves the numbers of each substance to the
/// catalog, so a corrected catalog corrects every experiment.
///
/// **References are checked as it is read.** A step setting a parameter
/// the document does not declare, or expecting a reading of a probe it does
/// not have, is refused with a [DocumentFormatException] naming both: a
/// typo found when the file opens, not when a student reaches the step.
///
/// **A verifiable experiment runs `deterministic`.** [profile] names the
/// simulation profile; a laboratory a server checks by replay stays on
/// `deterministic`, and `accurate` is for demonstration.
final class ExperimentDocument extends FormatDocument {
  /// Throws an [ArgumentError] for an empty [name] or [level].
  ExperimentDocument({
    required this.name,
    required this.level,
    this.title,
    this.profile = 'deterministic',
    List<ExperimentSubstance> substances = const <ExperimentSubstance>[],
    List<ExperimentParameter> parameters = const <ExperimentParameter>[],
    List<ExperimentProbe> probes = const <ExperimentProbe>[],
    List<ExperimentStep> steps = const <ExperimentStep>[],
    List<ExperimentUnknown> unknowns = const <ExperimentUnknown>[],
    List<ExperimentObservation> observations = const <ExperimentObservation>[],
    super.unknown,
  }) : substances = List<ExperimentSubstance>.unmodifiable(substances),
       parameters = List<ExperimentParameter>.unmodifiable(parameters),
       probes = List<ExperimentProbe>.unmodifiable(probes),
       steps = List<ExperimentStep>.unmodifiable(steps),
       unknowns = List<ExperimentUnknown>.unmodifiable(unknowns),
       observations = List<ExperimentObservation>.unmodifiable(observations) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name', 'empty');
    if (level.isEmpty) throw ArgumentError.value(level, 'level', 'empty');
  }

  /// Reads a document, lifted from any earlier version, or throws a
  /// [DocumentFormatException] saying what is wrong.
  factory ExperimentDocument.fromJson(Map<String, Object?> json) {
    final document = experimentFormat.open(
      json,
      refuse: DocumentFormatException.new,
    );
    try {
      return _read(document);
    } on DocumentFormatException {
      rethrow;
    } on Flutter3dFormatException catch (error) {
      throw DocumentFormatException('an experiment: $error');
    } on ArgumentError catch (error) {
      throw DocumentFormatException('an experiment: ${error.message}');
    }
  }

  /// Reads [text], a whole `.f3d.experiment` file.
  factory ExperimentDocument.parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw DocumentFormatException(
        'an experiment is not JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const DocumentFormatException('an experiment is a JSON object');
    }
    return ExperimentDocument.fromJson(decoded);
  }

  static ExperimentDocument _read(Map<String, Object?> document) {
    Never wrong(String what) => throw DocumentFormatException(what);
    List<Map<String, Object?>> entries(Object? value, String what) =>
        switch (value) {
          null => const <Map<String, Object?>>[],
          final List<Object?> list when list.every((e) => e is Map) =>
            <Map<String, Object?>>[
              for (final entry in list) (entry! as Map).cast<String, Object?>(),
            ],
          _ => wrong('$what is not a list of objects'),
        };
    String text(Map<String, Object?> entry, String key, String what) =>
        switch (entry[key]) {
          final String value when value.isNotEmpty => value,
          _ => wrong('$what names no "$key"'),
        };
    String? optionalText(Map<String, Object?> entry, String key, String what) =>
        switch (entry[key]) {
          null => null,
          final String value => value,
          _ => wrong('$what has a "$key" that is not text'),
        };
    // A quantity is written as `{"value", "unit"}` or, by hand, as text:
    // `"1 m"`, `"0.5 s"`.
    Quantity quantityOf(Object written) => switch (written) {
      final String text => Quantity.parse(text),
      _ => Quantity.fromJson(written),
    };
    Quantity? optionalQuantity(
      Map<String, Object?> entry,
      String key,
      String what,
    ) => switch (entry[key]) {
      null => null,
      final Object written => quantityOf(written),
    };
    Quantity quantity(Map<String, Object?> entry, String key, String what) =>
        optionalQuantity(entry, key, what) ?? wrong('$what has no "$key"');

    final name = text(document, 'name', 'an experiment');
    final level = text(document, 'level', 'experiment "$name"');

    final parameters = <ExperimentParameter>[
      for (final entry in entries(document['parameters'], '"parameters"'))
        () {
          final id = text(entry, 'id', 'a parameter');
          final what = 'parameter "$id"';
          return ExperimentParameter(
            id: id,
            value: quantity(entry, 'value', what),
            min: optionalQuantity(entry, 'min', what),
            max: optionalQuantity(entry, 'max', what),
          );
        }(),
    ];
    final parameterIds = _unique(
      parameters.map((parameter) => parameter.id),
      'parameter',
    );

    final probes = <ExperimentProbe>[
      for (final entry in entries(document['probes'], '"probes"'))
        ExperimentProbe(
          probe: Probe.fromJson(entry),
          on: optionalText(entry, 'on', 'a probe'),
        ),
    ];
    final probeIds = _unique(probes.map((probe) => probe.id), 'probe');

    final scenario = switch (document['scenario']) {
      null => const <String, Object?>{},
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => wrong('"scenario" is not an object'),
    };
    final steps = <ExperimentStep>[
      for (final entry in entries(scenario['steps'], 'the scenario\'s "steps"'))
        () {
          final stepName = text(entry, 'name', 'a step');
          final what = 'step "$stepName"';
          final set = switch (entry['set']) {
            null => const <String, Quantity>{},
            final Map<Object?, Object?> map => <String, Quantity>{
              for (final MapEntry(:key, :value) in map.entries)
                switch (key) {
                  final String id when parameterIds.contains(id) => id,
                  _ => wrong(
                    '$what sets "$key", which is not a parameter of '
                    'experiment "$name"',
                  ),
                }: quantityOf(
                  value ?? wrong('$what sets "$key" to nothing'),
                ),
            },
            _ => wrong('$what has a "set" that is not an object'),
          };
          return ExperimentStep(
            name: stepName,
            title: optionalText(entry, 'title', what),
            set: set,
            run: optionalQuantity(entry, 'run', what),
            expect: <ExpectedReading>[
              for (final reading in entries(entry['expect'], '$what: "expect"'))
                () {
                  final probe = text(reading, 'probe', '$what: a reading');
                  if (!probeIds.contains(probe)) {
                    wrong(
                      '$what expects a reading of "$probe", which is not a '
                      'probe of experiment "$name"',
                    );
                  }
                  final where = '$what: the reading of "$probe"';
                  return ExpectedReading(
                    probe: probe,
                    value: quantity(reading, 'value', where),
                    tolerance: quantity(reading, 'tolerance', where),
                  );
                }(),
            ],
            check: switch (entry['check']) {
              null => null,
              final Object question => CheckQuestion.fromJson(question),
            },
          );
        }(),
    ];
    _unique(steps.map((step) => step.name), 'step');

    return ExperimentDocument(
      name: name,
      level: level,
      title: optionalText(document, 'title', 'experiment "$name"'),
      profile:
          optionalText(document, 'profile', 'experiment "$name"') ??
          'deterministic',
      substances: <ExperimentSubstance>[
        for (final entry in entries(document['substances'], '"substances"'))
          ExperimentSubstance(
            id: text(entry, 'id', 'a substance'),
            role: optionalText(entry, 'role', 'a substance'),
          ),
      ],
      parameters: parameters,
      probes: probes,
      steps: steps,
      unknowns: <ExperimentUnknown>[
        for (final entry in entries(document['unknowns'], '"unknowns"'))
          () {
            final parameter = text(entry, 'parameter', 'an unknown');
            final what = 'the unknown "$parameter"';
            return ExperimentUnknown(
              parameter: parameter,
              min: quantity(entry, 'min', what),
              max: quantity(entry, 'max', what),
              prior: switch (entry['prior']) {
                null => const <String, Object?>{},
                final Map<Object?, Object?> map => map.cast<String, Object?>(),
                _ => wrong('$what has a "prior" that is not an object'),
              },
            );
          }(),
      ],
      observations: <ExperimentObservation>[
        for (final entry in entries(document['observations'], '"observations"'))
          () {
            final probe = text(entry, 'probe', 'an observation');
            final what = 'an observation of "$probe"';
            return ExperimentObservation(
              probe: probe,
              at: quantity(entry, 'at', what),
              value: quantity(entry, 'value', what),
              uncertainty: optionalQuantity(entry, 'uncertainty', what),
            );
          }(),
      ],
      unknown: FormatDocument.unknownIn(
        document,
        known: _known,
        spec: experimentFormat,
      ),
    );
  }

  static Set<String> _unique(Iterable<String> ids, String what) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw DocumentFormatException('two ${what}s are called "$id"');
      }
    }
    return seen;
  }

  static const Set<String> _known = <String>{
    'name',
    'title',
    'level',
    'profile',
    'substances',
    'parameters',
    'probes',
    'scenario',
    'unknowns',
    'observations',
  };

  @override
  FormatSpec get spec => experimentFormat;

  /// What the experiment is called, as a file names it (`pendulum`).
  final String name;

  /// What a student reads it as, or null.
  final String? title;

  /// The level it happens in: a path relative to this document's file.
  final String level;

  /// The simulation profile it runs under, by name: `deterministic`, which
  /// a server can replay and check, unless it says otherwise.
  final String profile;

  /// The substances it uses, by catalog id.
  final List<ExperimentSubstance> substances;

  /// The numbers it can be run with.
  final List<ExperimentParameter> parameters;

  /// The probes it reads.
  final List<ExperimentProbe> probes;

  /// The scenario: its steps, in order.
  final List<ExperimentStep> steps;

  /// Parameters an inverse run would estimate. Kept and written; nothing
  /// in this version estimates.
  final List<ExperimentUnknown> unknowns;

  /// Readings of the real thing an inverse run would fit. Kept and
  /// written; nothing in this version fits.
  final List<ExperimentObservation> observations;

  /// The parameter called [id], or null.
  ExperimentParameter? parameter(String id) =>
      parameters.where((parameter) => parameter.id == id).firstOrNull;

  /// The probe called [id], or null.
  ExperimentProbe? probe(String id) =>
      probes.where((probe) => probe.id == id).firstOrNull;

  /// The step called [name], or null.
  ExperimentStep? step(String name) =>
      steps.where((step) => step.name == name).firstOrNull;

  /// The substances [catalog] does not hold, in the document's order:
  /// empty when every id resolves. What a reader checks before it runs the
  /// experiment, so an unknown id is named rather than met as a null.
  List<ExperimentSubstance> substancesMissingFrom(MaterialCatalog catalog) =>
      <ExperimentSubstance>[
        for (final substance in substances)
          if (catalog.byId(substance.id) == null) substance,
      ];

  /// The document as a `.f3d.experiment` file writes it.
  Map<String, Object?> toJson() => write(<String, Object?>{
    'name': name,
    'title': ?title,
    'level': level,
    if (profile != 'deterministic') 'profile': profile,
    if (substances.isNotEmpty)
      'substances': <Object?>[
        for (final substance in substances) substance.toJson(),
      ],
    if (parameters.isNotEmpty)
      'parameters': <Object?>[
        for (final parameter in parameters) parameter.toJson(),
      ],
    if (probes.isNotEmpty)
      'probes': <Object?>[for (final probe in probes) probe.toJson()],
    'scenario': <String, Object?>{
      'steps': <Object?>[for (final step in steps) step.toJson()],
    },
    if (unknowns.isNotEmpty)
      'unknowns': <Object?>[for (final unknown in unknowns) unknown.toJson()],
    if (observations.isNotEmpty)
      'observations': <Object?>[
        for (final observation in observations) observation.toJson(),
      ],
  });

  /// [toJson] as text, indented the way the fixtures are written.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
