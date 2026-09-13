/// `edu-05`: an `edu_data_source` sampled by fixed step, a binding resolved
/// against a real level, and a `DataSourceTrace` that branches at a step
/// without touching what it branched from.
///
///     flutter test test/data_source_test.dart
///
/// The level JSON below follows `doc/edu-00-interactive-format.md` exactly —
/// flat properties, no `"properties"` wrapper key — the same shape that
/// document's own §2 found broken by a real `Level.fromJson` run, not by
/// inspection.
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Level _twinLevel() => Level.fromJson(
  jsonDecode('''
{
  "name": "lathe-twin",
  "entities": [
    {"type": "lathe", "name": "lathe-body", "at": [0, 0, 0]},
    {"type": "edu_data_source", "name": "lathe-broker", "kind": "sampler"},
    {"type": "edu_step", "name": "step-1", "at": [0, 1, 2],
     "bindings": [
       {"source": "lathe-broker", "path": "temperature",
        "target": "lathe-body.material.emissiveColor"},
       {"source": "lathe-broker", "path": "sensors.spindle.rpm",
        "target": "lathe-body.spindleRpm"}
     ]}
  ]
}
''')
      as Map<String, Object?>,
);

void main() {
  group('resolveBindings', () {
    test('reads a flat, un-wrapped level exactly as edu-00 §2 requires', () {
      final level = _twinLevel();
      expect(level.entities, hasLength(3));
      expect(level.named('lathe-broker')!.type, 'edu_data_source');
      expect(level.named('lathe-broker')!.properties['kind'], 'sampler');
    });

    test('resolves a dotted path one level into the payload', () {
      final level = _twinLevel();
      final step = level.named('step-1')!;
      final registry = DataSourceRegistry(<String, EduDataSource>{
        'lathe-broker': SamplerDataSource(
          (s) => <String, Object?>{
            'temperature': 20.0 + s,
            'sensors': <String, Object?>{
              'spindle': <String, Object?>{'rpm': 1000 + s},
            },
          },
        ),
      });

      final resolved = resolveBindings(step, 5, registry);

      expect(resolved['lathe-body.material.emissiveColor'], 25.0);
      expect(resolved['lathe-body.spindleRpm'], 1005);
    });

    test('a binding naming an unknown source is skipped, not thrown', () {
      final level = Level.fromJson(
        jsonDecode('''
{"entities": [
  {"type": "edu_step", "name": "s", "at": [0,0,0],
   "bindings": [{"source": "nowhere", "path": "x", "target": "a.b"}]}
]}
''')
            as Map<String, Object?>,
      );
      final resolved = resolveBindings(
        level.named('s')!,
        0,
        DataSourceRegistry(<String, EduDataSource>{}),
      );
      expect(resolved, isEmpty);
    });

    test('a step with no bindings resolves to nothing', () {
      final step = _twinLevel().named('lathe-body')!;
      expect(
        resolveBindings(step, 0, DataSourceRegistry(<String, EduDataSource>{})),
        isEmpty,
      );
    });
  });

  group('DataSourceTrace', () {
    test('records forward and reads back what it recorded', () {
      final trace = DataSourceTrace();
      trace.record(0, <String, Object?>{'temperature': 20.0});
      trace.record(1, <String, Object?>{'temperature': 20.1});

      expect(trace.length, 2);
      expect(trace.steps, <int>[0, 1]);
      expect(trace.valueAt(1), <String, Object?>{'temperature': 20.1});
      expect(trace.valueAt(2), isNull);
    });

    test('refuses a step that does not move the trace forward', () {
      final trace = DataSourceTrace()..record(5, const <String, Object?>{});
      expect(
        () => trace.record(5, const <String, Object?>{}),
        throwsArgumentError,
      );
      expect(
        () => trace.record(4, const <String, Object?>{}),
        throwsArgumentError,
      );
    });

    test('survives a round trip through JSON', () {
      final trace = DataSourceTrace()
        ..record(0, <String, Object?>{'temperature': 20.0})
        ..record(1, <String, Object?>{'temperature': 20.1});

      final read = DataSourceTrace.fromJson(
        jsonDecode(jsonEncode(trace.toJson())) as Map<String, Object?>,
      );

      expect(read.steps, trace.steps);
      expect(read.valueAt(1), trace.valueAt(1));
    });

    test(
      'branchAt keeps the prefix, diverges after, and never touches the '
      'trace it branched from',
      () {
        final original = DataSourceTrace();
        for (var s = 0; s <= 10; s++) {
          original.record(s, <String, Object?>{'temperature': 20.0 + s});
        }
        final originalJsonBefore = jsonEncode(original.toJson());

        final branch = original.branchAt(
          5,
          10,
          (s) => <String, Object?>{'temperature': 999.0},
        );

        // The prefix is copied, not shared by reference into a mutable spot —
        // the original is re-serialised below to prove it, not just re-read.
        for (var s = 0; s <= 5; s++) {
          expect(branch.valueAt(s), original.valueAt(s));
        }
        for (var s = 6; s <= 10; s++) {
          expect(branch.valueAt(s), <String, Object?>{'temperature': 999.0});
          expect(branch.valueAt(s), isNot(original.valueAt(s)));
        }

        expect(jsonEncode(original.toJson()), originalJsonBefore);
        expect(original.length, 11);
        expect(branch.length, 11);
      },
    );
  });

  group('Demo.dataSources', () {
    test('is null when nothing bound any external value', () {
      final demo = _demoWithDataSources(null);
      final read = Demo.fromJson(
        jsonDecode(jsonEncode(demo.toJson())) as Map<String, Object?>,
      );
      expect(read.dataSources, isNull);
    });

    test('round-trips a recorded trace, additively', () {
      final trace = DataSourceTrace()
        ..record(0, <String, Object?>{'temperature': 20.0})
        ..record(1, <String, Object?>{'temperature': 20.5});
      final demo = _demoWithDataSources(trace);

      final json = demo.toJson();
      expect(json.containsKey('dataSources'), isTrue);

      final read = Demo.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(read.dataSources, isNotNull);
      expect(read.dataSources!.steps, <int>[0, 1]);
      expect(read.dataSources!.valueAt(1), <String, Object?>{'temperature': 20.5});
    });

    test('an older demo with no "dataSources" key still reads', () {
      final demo = _demoWithDataSources(null);
      final json = demo.toJson()..remove('dataSources');
      final read = Demo.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(read.dataSources, isNull);
    });
  });
}

Demo _demoWithDataSources(DataSourceTrace? trace) {
  final checkpoints = DigestTrace(every: 1)
    ..observe(1, <String, Object?>{'step': 1});
  return Demo(
    level: 'assets/levels/lathe.json',
    levelHash: 'deadbeef',
    start: const Snapshot(<String, Object?>{'random': 1}),
    tape: InputTape(seed: 1, frames: <InputFrame>[InputFrame()]),
    buildStamp: 'test-build',
    checkpoints: checkpoints,
    dataSources: trace,
  );
}
