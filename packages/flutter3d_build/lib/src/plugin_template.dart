/// `flutter3d create plugin`: a new plugin package, as files, for each of the
/// five kinds decision 20 of `tasks/0.9-plugins.md` names, and a graphics
/// backend written from `examples/flutter3d_backend_null`.
///
/// **Text, not a directory copied off disk.** The game templates live in the
/// editor's asset bundle because a running editor reads them; a plugin
/// template is read by `dart run flutter3d_build:create` and by the
/// plugin-author MCP server, both plain Dart processes with no bundle, so the
/// files are strings here and a test reads exactly what a person gets.
///
/// **Every file compiles against today's API and installs as it says.** The
/// library is a `Flutter3dPlugin` written the way the engine's own are, the
/// pubspec carries the `flutter3d_plugins:` marker discovery reads, and the
/// tests are two: one that installs the plugin into an `EngineLoop` and looks
/// at what it registered, and one that runs `flutter3d_conformance`'s plugin
/// suite — the suite the badge is earned on.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show packageName;

import 'template_versions.dart';

/// What a plugin is for, which decides what its template installs.
///
/// **A final class with constant instances rather than an enum**, for the
/// reason every open kind in this repository gives (ARCHITECTURE.md §13.1):
/// a sixth kind is a minor release, and a `switch` somebody wrote against
/// five would stop compiling on it.
final class PluginKind {
  const PluginKind._(
    this.name,
    this.about, {
    required this.simulates,
    this.isPlugin = true,
  });

  /// A pass of its own at a render anchor, switched like the engine's steps.
  static const PluginKind renderStep = PluginKind._(
    'render-step',
    'a full-screen pass at a render anchor, switched like a built-in step',
    simulates: false,
  );

  /// Something seen or heard when something happens, aged once a frame.
  static const PluginKind effect = PluginKind._(
    'effect',
    'something seen when an event arrives, aged once a displayed frame',
    simulates: false,
  );

  /// A step phase of its own and the rules that run in it.
  static const PluginKind genre = PluginKind._(
    'genre',
    'a step phase of its own between physics and fields, with a rule '
        'that scores and an event it publishes',
    simulates: true,
  );

  /// A field of the world and the subsystem that steps it in the `fields`
  /// phase.
  static const PluginKind element = PluginKind._(
    'element',
    'a field of the world and a subsystem that steps it in the fields phase '
        'with Portable arithmetic, saved and restored with the run',
    simulates: true,
  );

  /// A tool an agent calls, published under the plugin's id.
  static const PluginKind tool = PluginKind._(
    'tool',
    'an MCP tool published under the plugin\'s id',
    simulates: false,
  );

  /// A graphics backend: a `GraphicsDevice` an application registers with
  /// its device registry, started from the null backend in
  /// `examples/flutter3d_backend_null` under the package's own name. Not a
  /// `Flutter3dPlugin` ([isPlugin] is false): it is opened, not installed.
  static const PluginKind backend = PluginKind._(
    'backend',
    'a graphics backend with no GPU yet, which passes conformance and grows '
        'into one for another API',
    simulates: false,
    isPlugin: false,
  );

  /// The six, in the order `--list` prints them.
  static const List<PluginKind> values = <PluginKind>[
    renderStep,
    effect,
    genre,
    element,
    tool,
    backend,
  ];

  /// The kind called [name], as `--kind` and `plugin.create` spell it.
  ///
  /// Throws an [ArgumentError] naming all six for any other word.
  static PluginKind named(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    throw ArgumentError.value(
      name,
      'kind',
      'a plugin is one of ${values.map((PluginKind k) => k.name).join(', ')}',
    );
  }

  /// The word on the command line: `render-step`, `effect`, `genre`,
  /// `element`, `tool`, `backend`.
  final String name;

  /// Whether the package is a `Flutter3dPlugin` that discovery finds by its
  /// pubspec marker and an engine installs; false for a [backend].
  final bool isPlugin;

  /// One line, for `--list` and a tool's description.
  final String about;

  /// Whether the plugin's manifest says it touches the simulation. A view
  /// plugin is refused anything in the step, so this decides which template
  /// gets the `flutter3d_lints` analyzer plugin as well.
  final bool simulates;

  @override
  String toString() => name;
}

/// The files of a new plugin package called [name], of [kind], by the path
/// each is written to.
///
/// [name] is made a pub package name the way the editor's wizard makes one
/// ([packageName]): lower case, words joined by underscores. The plugin's id
/// is the package's name, which is what its tools and events are filed
/// under, and its class is the name in Pascal case with `Plugin` after it.
Map<String, String> pluginTemplate({
  required String name,
  required PluginKind kind,
}) {
  final package = packageName(name);
  if (kind == PluginKind.backend) return _backendTemplate(package);
  final pascal = _pascal(package);
  final words = <String, String>{
    'name': package,
    'pascal': pascal,
    'class': '${pascal}Plugin',
    'camel': '${pascal[0].toLowerCase()}${pascal.substring(1)}',
    'kind': kind.name,
    'about': kind.about,
  };
  String fill(String text) => text.replaceAllMapped(
    RegExp(r'\{\{(\w+)\}\}'),
    (Match m) => words[m[1]] ?? m[0]!,
  );
  final (library, unitTest, conformanceTest) = switch (kind) {
    PluginKind.renderStep => (_renderLib, _renderTest, _renderConformance),
    PluginKind.effect => (_effectLib, _effectTest, _viewConformance),
    PluginKind.genre => (_genreLib, _genreTest, _stateConformance),
    PluginKind.element => (_elementLib, _elementTest, _stateConformance),
    _ => (_toolLib, _toolTest, _toolConformance),
  };
  return <String, String>{
    'pubspec.yaml': fill(_pubspec(kind)),
    'analysis_options.yaml': fill(
      kind.simulates ? _analysisOptionsSimulation : _analysisOptions,
    ),
    'lib/$package.dart': fill(library),
    'test/${package}_test.dart': fill(unitTest),
    'test/conformance_test.dart': fill(conformanceTest),
    'README.md': fill(_readme),
    'CHANGELOG.md': fill(_changelog),
    '.gitignore': _gitignore,
  };
}

/// The files of a backend called [package]: the null backend of
/// `examples/flutter3d_backend_null`, file for file, with its names in
/// place of the example's.
///
/// **Written from the example, not beside it.** The library and the tests
/// below are the example's own text with `flutter3d_backend_null` as
/// `{{name}}`, `Null` as `{{stem}}`, `null` as `{{label}}` and `nullSection`
/// as `{{lowerStem}}Section`, and `plugin_template_test.dart` compares them
/// with the example, which passes conformance in CI: a backend made from
/// the template starts from that one.
Map<String, String> _backendTemplate(String package) {
  final label = _backendLabel(package);
  final stem = _pascal(label);
  final words = <String, String>{
    'name': package,
    'label': label,
    'stem': stem,
    'lowerStem': '${stem[0].toLowerCase()}${stem.substring(1)}',
  };
  String fill(String text) => text.replaceAllMapped(
    RegExp(r'\{\{(\w+)\}\}'),
    (Match m) => words[m[1]] ?? m[0]!,
  );
  return <String, String>{
    'pubspec.yaml': fill(_backendPubspec),
    'analysis_options.yaml': _analysisOptions,
    'lib/$package.dart': fill(_backendLibrary),
    'bin/material_compiler.dart': fill(_backendCompiler),
    'lib/src/${label}_device.dart': fill(_backendDevice),
    'lib/src/${label}_pass.dart': fill(_backendPass),
    'lib/src/${label}_texels.dart': fill(_backendTexels),
    'test/conformance_test.dart': fill(_backendConformance),
    'test/${label}_device_test.dart': fill(_backendDeviceTest),
    'README.md': fill(_backendReadme),
    'CHANGELOG.md': fill(_backendChangelog),
    '.gitignore': _gitignore,
  };
}

/// What a backend's classes and files are named after: [package] without
/// the engine's prefix and without the word backend, so `flutter3d_metal`
/// and `metal_backend` are both `metal` and declare `MetalDevice`.
String _backendLabel(String package) {
  final bare = switch (package) {
    final p when p.startsWith('flutter3d_backend_') && p.length > 18 =>
      p.substring(18),
    final p when p.startsWith('flutter3d_') && p.length > 10 => p.substring(10),
    final p => p,
  };
  return bare.endsWith('_backend') && bare.length > 8
      ? bare.substring(0, bare.length - 8)
      : bare;
}

/// `my_glow` as `MyGlow`.
String _pascal(String package) => package
    .split('_')
    .where((String part) => part.isNotEmpty)
    .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

String _pubspec(PluginKind kind) {
  final dependencies = <String>[
    dependencyLine('flutter3d_plugin_api'),
    if (kind == PluginKind.renderStep || kind == PluginKind.effect)
      dependencyLine('flutter3d_core'),
    if (kind == PluginKind.renderStep) dependencyLine('flutter3d_hardware'),
    if (kind == PluginKind.element) ...<String>[
      dependencyLine('flutter3d_fields'),
      dependencyLine('flutter3d_foundation'),
    ],
    if (kind.simulates) dependencyLine('flutter3d_sim'),
  ];
  final devDependencies = <String>[
    dependencyLine('flutter3d_conformance'),
    if (!kind.simulates) dependencyLine('flutter3d_sim'),
    '  test: ^1.25.0',
  ];
  return '''
name: {{name}}
description: "A flutter3d plugin: {{about}}."
version: 0.1.0
# The topic the plugin catalogue on flutter3d.pleion.dev is read by.
topics:
  - flutter3d-plugin

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
${dependencies.join('\n')}

dev_dependencies:
${devDependencies.join('\n')}

# What `flutter3d_build`'s discovery reads: an application that depends on
# this package gets {{class}} in its `lib/plugins.g.dart`.
flutter3d_plugins:
  plugin: package:{{name}}/{{name}}.dart#{{class}}
''';
}

const String _analysisOptions = '''
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
''';

const String _analysisOptionsSimulation = '''
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true

# The determinism rules for code that runs inside a fixed step: no wall
# clock, no unseeded Random, Portable rather than dart:math's
# transcendentals. An analysis server plugin, resolved by the analysis server
# on its own, so it is not a dependency of this package.
plugins:
  flutter3d_lints: ^1.0.0-rc.1
''';

const String _readme = '''
# {{name}}

A flutter3d plugin ({{kind}}): {{about}}.

## Using it

An application that depends on this package finds the plugin through
discovery: `flutter3d_build` writes `lib/plugins.g.dart` from the
`flutter3d_plugins:` marker in this package's pubspec, and the application
hands `installedPlugins`, a `PluginGroup`, to its engine. A list written in
code works as well:

```dart
EngineLoop(input: input, plugins: [{{class}}()]);
```

## Conformance

```bash
dart test test/conformance_test.dart
```

runs `flutter3d_conformance`'s plugin suite: the manifest, switching on and
off at a step boundary, determinism (every step run twice from a snapshot),
every backend the manifest declares, and the budget in the manifest's
`extra`. A plugin earns the conformance badge when every check passes on every
declared backend, with a world given to the determinism check and a budget
declared and kept — `flutter3d_conformance`'s README says it in full. The
run writes `{{name}}.conformance.json` beside this pubspec, with the badge
the suite gave: publish it with the package, and once it says
`conformant@1.0`, write `conformance: conformant@1.0` under
`flutter3d_plugins:` in the pubspec.

## Publishing

The pubspec's `flutter3d-plugin` topic is what the plugin catalogue on the
flutter3d site is read by. Keep it, and the catalogue lists the package after
its next build.
''';

const String _changelog = '''
## 0.1.0

- **The first release.** Created by `flutter3d create plugin --kind {{kind}}`.
''';

const String _gitignore = '''
.dart_tool/
build/
pubspec.lock
''';

// ------------------------------------------------------------- render step

const String _renderLib = r'''
/// {{name}}: a render step of its own, drawn over the scene's light after
/// bloom and before tone mapping.
///
/// Installed, it adds the step `{{name}}.step` to the renderer and places one
/// full-screen pass at `RenderAnchor.afterBloom`. `RenderSettings.without`
/// switches it off like a built-in step, and switching bloom off takes it
/// down too, because it needs bloom.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The step, as the renderer reports it in `FrameResult.skipped`.
///
/// Named in the plugin's namespace, `{{name}}.`, as every name a plugin
/// registers is.
const RenderStep {{camel}}Step = RenderStep(
  '{{name}}.step',
  needs: <RenderStep>{RenderStep.bloom},
);

/// The plugin: a view plugin, so switching it changes nothing a replay
/// checks.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'A full-screen pass after bloom.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<RendererSteps>()
      ..addStep({{camel}}Step)
      ..addNode(
        {{pascal}}Pass(),
        at: RenderAnchor.afterBloom,
        step: {{camel}}Step,
      );
  }
}

/// The pass: the fragment stage named `{{name}}`, drawn over the scene's
/// light.
///
/// The stage comes from the application's shader bundle, found by name on
/// the device the frame is drawn with. Until the bundle has one, the pass
/// leaves the picture as it found it.
final class {{pascal}}Pass extends RenderNode {
  {{pascal}}Pass();

  FullscreenEffect? _effect;

  @override
  String get name => '{{name}}.pass';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {
    final effect = _effect ??= switch (frame.device.shaders['{{name}}']) {
      null => null,
      final ShaderHandle shader => FullscreenEffect.overlay(
        name: '{{name}}.pass',
        shader: shader,
      ),
    };
    effect?.execute(frame);
  }
}
''';

const String _renderTest = r'''
/// {{name}} installs its step and its pass, and takes both out again.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the step is the renderer\'s while the plugin is on', () {
    final renderer = Renderer.create(device: FakeBackend());
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[renderer.renderSteps],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    expect(renderer.renderSteps.added, contains({{camel}}Step));

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(renderer.renderSteps.added, isNot(contains({{camel}}Step)));
  });
}
''';

const String _renderConformance = r'''
/// flutter3d_conformance's plugin suite, over a renderer drawn with the
/// hardware layer's fake device: the step and the pass need a renderer to be
/// added to, and the fake needs no GPU.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[
        Renderer.create(device: FakeBackend()).renderSteps,
      ],
    ),
  );
}
''';

// ------------------------------------------------------------------ effect

const String _effectLib = r'''
/// {{name}}: something seen when an event arrives, aged once a displayed
/// frame.
///
/// A view plugin. It hears the frame channel — each event once, and a step
/// run again on a rollback is not heard twice — and ages what it spawned in
/// the `animate` phase. It never touches the step, so switching it on or off
/// changes nothing a replay checks.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The plugin. [watches] is the end of the event names it answers.
final class {{class}} extends Flutter3dPlugin {
  {{class}}({this.watches = 'landed', this.lifetime = 0.6});

  /// An event whose name ends with this spawns a puff: `landed` answers
  /// `runner.landed` and `crate.landed`.
  final String watches;

  /// How long a puff lasts, in seconds of the game's time.
  final double lifetime;

  final List<double> _ages = <double>[];

  /// How many puffs are alive: what a renderer draws.
  int get alive => _ages.length;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'A puff for every event it watches.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.events.onFrame<BusEvent>('{{name}}.spawn', (
      Delivered<BusEvent> heard,
    ) {
      if (heard.event.name.endsWith(watches)) _ages.add(0.0);
    });
    host.loop.addSystem('{{name}}.age', LoopPhase.animate, (
      LoopContext frame,
    ) {
      // The game's time, not the wall clock's: a paused game's puffs wait.
      for (var i = 0; i < _ages.length; i++) {
        _ages[i] += frame.dt;
      }
      _ages.removeWhere((double age) => age >= lifetime);
    });
  }

  @override
  void uninstall(PluginHost host) => _ages.clear();
}
''';

const String _effectTest = r'''
/// {{name}} spawns a puff for the event it watches and lets it go.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

final class _Landed extends BusEvent {
  const _Landed();

  @override
  String get name => 'test.landed';
}

void main() {
  test('a watched event spawns a puff, which lasts its lifetime', () {
    final plugin = {{class}}();
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    loop.events.publishFrame(const _Landed());
    loop.frame(1.0 / 60.0);
    expect(plugin.alive, 1);

    for (var i = 0; i < 3; i++) {
      loop.frame(0.25);
    }
    expect(plugin.alive, 0);
  });
}
''';

const String _viewConformance = r'''
/// flutter3d_conformance's plugin suite. A view plugin keeps nothing a step
/// reads, so the determinism check is given no world of its own.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance({{class}}.new);
}
''';

// ------------------------------------------------------------------- genre

const String _genreLib = r'''
/// {{name}}: a genre's rules, in a step phase of their own.
///
/// The phase sits after the bodies have moved and before the world's fields
/// (`physics` < `{{name}}.rules` < `fields`). Its one rule scores a point
/// every [{{class}}.pointsEvery] steps and publishes [{{pascal}}Scored] on
/// the step channel, so a replay digests it and a sound or a counter hears it
/// on the frame channel once.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// A point scored, with the score it made.
final class {{pascal}}Scored extends BusEvent {
  const {{pascal}}Scored(this.score);

  final int score;

  /// How it is written: the score. A step event is declared with its codec,
  /// so a replay digests what it carries and the view reads it encoded.
  static final EventCodec<{{pascal}}Scored> codec =
      EventCodec<{{pascal}}Scored>.of(
        encode: (event) => event.score,
        decode: (context) => switch (context.data) {
          final int score => {{pascal}}Scored(score),
          _ => null,
        },
      );

  @override
  String get name => '{{name}}.scored';
}

/// The genre's rules phase.
const LoopPhase {{camel}}Rules = LoopPhase.step('{{name}}.rules');

/// The plugin. It touches the simulation: its switch is journalled, and a
/// replay makes it at the same step. Its score is a part of the loop's
/// snapshots, so a rewind, a rollback and the double-step check carry it.
final class {{class}} extends Flutter3dPlugin {
  {{class}}({this.pointsEvery = 60});

  /// Steps between two points.
  final int pointsEvery;

  int _score = 0;

  /// The score so far.
  int get score => _score;

  /// The state a snapshot keeps.
  Map<String, Object?> save() => <String, Object?>{'score': _score};

  /// Puts back what [save] wrote.
  void restore(Map<String, Object?> state) =>
      _score = (state['score'] as num?)?.toInt() ?? 0;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.simulation,
    description: 'A rules phase that scores.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 500, 'eventsPerStep': 8},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<SnapshotRegistry>().add(
      SnapshotPart.of(
        id: '{{name}}.score',
        capture: save,
        restore: (context) => restore(context.data! as Map<String, Object?>),
      ),
    );
    host.loop.addPhase(
      {{camel}}Rules,
      after: const <String>['physics'],
      before: const <String>['fields'],
    );
    host.events.declare<{{pascal}}Scored>(
      '{{name}}.scored',
      description: 'A point scored, with the score it made.',
      codec: {{pascal}}Scored.codec,
    );
    host.loop.addSystem('{{name}}.score', {{camel}}Rules, (
      LoopContext step,
    ) {
      if (step.step % pointsEvery != 0) return;
      _score += 1;
      step.publish({{pascal}}Scored(_score));
    });
  }
}
''';

const String _genreTest = r'''
/// {{name}}'s phase sits where it says, and its rule scores on the step.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the rules phase is between physics and fields', () {
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[{{class}}()],
    );
    final phases = loop
        .phases(PhaseKind.step)
        .map((LoopPhase p) => p.name)
        .toList();
    expect(phases.indexOf('{{name}}.rules'), phases.indexOf('physics') + 1);
    expect(phases.indexOf('fields'), phases.indexOf('{{name}}.rules') + 1);
  });

  test('a point every pointsEvery steps, each heard on the step channel', () {
    final plugin = {{class}}(pointsEvery: 60);
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    final heard = <int>[];
    loop.events.onStep<{{pascal}}Scored>(
      'test',
      (Delivered<{{pascal}}Scored> scored) => heard.add(scored.event.score),
    );
    loop.runSteps(120);
    expect(plugin.score, 2);
    expect(heard, <int>[1, 2]);
  });
}
''';

const String _stateConformance = r'''
/// flutter3d_conformance's plugin suite. The plugin's install puts its state
/// in the loop's snapshots, so the determinism check steps each step twice
/// from it, as an application's rewind and rollback do.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance({{class}}.new);
}
''';

// ----------------------------------------------------------------- element

const String _elementLib = r'''
/// {{name}}: a field of the world and the subsystem that steps it.
///
/// One value per cell, decaying towards nought with a half-life, stepped in
/// the `fields` phase. The field is declared with the subsystem that writes
/// it, so the loop hands the subsystem its values, keeps them in the run's
/// snapshots and copies them for whatever draws them. The arithmetic is
/// `Portable`'s, never `dart:math`'s: a transcendental from the platform's
/// library gives different bits on the VM and in a browser, and a replay
/// checked on a server would part from the player's run.
library;

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The field: one value per cell of a row of 64, written by the decay.
///
/// Named in the plugin's namespace, `{{name}}.`, as every name a plugin
/// registers is.
const FieldDeclaration {{camel}}Field = FieldDeclaration(
  id: '{{name}}.value',
  quantity: '{{name}}.value',
  unit: Unit.one,
  grid: FieldGrid(64, 1, 1),
  writer: FieldAccess.simulation({{pascal}}Decay.id),
);

/// The subsystem: every value falls to half in [halfLife] seconds.
final class {{pascal}}Decay extends Subsystem {
  const {{pascal}}Decay({this.halfLife = 2.0});

  /// Its id, and its system's name in the loop.
  static const String id = '{{name}}.decay';

  static const double _ln2 = 0.6931471805599453;

  /// Seconds for a value to fall to half.
  final double halfLife;

  @override
  SubsystemDeclaration get declaration => const SubsystemDeclaration(
    id: id,
    version: 1,
    writesFields: <String>['{{name}}.value'],
  );

  @override
  void step(SubsystemContext context) {
    final values = context.field({{camel}}Field.id).values;
    final keep = Portable.exp(-context.dt * _ln2 / halfLife);
    for (var i = 0; i < values.length; i++) {
      values[i] *= keep;
    }
  }
}

/// The plugin. It touches the simulation, and declares the field and the
/// subsystem that steps it.
final class {{class}} extends Flutter3dPlugin {
  {{class}}({this.halfLife = 2.0});

  /// Seconds for a value to fall to half.
  final double halfLife;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.simulation,
    description: 'A field that decays with a half-life.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 500, 'eventsPerStep': 8},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<FieldRegistry>().declare({{camel}}Field);
    host.registry<SubsystemRegistry>().register(
      {{pascal}}Decay(halfLife: halfLife),
    );
  }
}
''';

const String _elementTest = r'''
/// {{name}}'s field halves in its half-life, stepped at the world's rate,
/// and is part of the run's snapshots.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('a value halves in one half-life', () {
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[{{class}}(halfLife: 2.0)],
    );
    final field = loop.fields.hostField({{camel}}Field.id)!;
    field.setValueAt(0, 0, 0, 1.0);
    loop.runSteps((2.0 / loop.stepSeconds).round());
    expect(field.valueAt(0, 0, 0), closeTo(0.5, 1e-4));
  });

  test('a restore puts the field back', () {
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[{{class}}()],
    );
    final field = loop.fields.hostField({{camel}}Field.id)!;
    field.setValueAt(3, 0, 0, 4.0);
    final saved = loop.capture();
    loop.runSteps(30);
    loop.restore(saved);
    expect(field.valueAt(3, 0, 0), 4.0);
  });
}
''';

// -------------------------------------------------------------------- tool

const String _toolLib = r'''
/// {{name}}: a tool an agent calls, published as `{{name}}.hello`.
///
/// Every MCP server of the project offers it beside its own tools, and
/// switching the plugin off takes it out of the list; the server tells its
/// client the list changed.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_api/tools.dart';

/// The plugin: a tooling plugin, since a tool runs between frames, not in a
/// step, and draws nothing a player sees.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => PluginManifest(
    id: '{{name}}',
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.tooling,
    permissions: <PluginPermission>{PluginPermission.tools},
    description: 'A tool that answers.',
    extra: const <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<McpTools>()
      ..declareSchemaVersion('1.0.0')
      ..addTool(
        ToolSpec(
          name: 'hello',
          description: 'Says hello back, to show the tool is there.',
          inputSchema: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'who': <String, Object?>{
                'type': 'string',
                'description': 'Who to greet.',
              },
            },
          },
          hints: ToolHints.reads,
        ),
        (ToolCall call) =>
            ToolResult.text('hello, ${call.arguments['who'] ?? 'agent'}'),
      );
  }
}
''';

const String _toolTest = r'''
/// {{name}}'s tool is published under the plugin's id and answers.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_api/tools.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the tool is {{name}}.hello while the plugin is on', () async {
    final tools = McpTools();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[tools],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    final hello = tools.named('{{name}}.hello');
    expect(hello, isNotNull);
    final result = await hello!.run(
      const ToolCall(
        name: '{{name}}.hello',
        arguments: <String, Object?>{'who': 'test'},
      ),
    );
    expect(result.text, 'hello, test');

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(tools.named('{{name}}.hello'), isNull);
  });
}
''';

const String _toolConformance = r'''
/// flutter3d_conformance's plugin suite, with a project's tool registry for
/// the tool to be published in.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:flutter3d_plugin_api/tools.dart';
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[McpTools()],
    ),
  );
}
''';
// ----------------------------------------------------------------- backend

const String _backendPubspec = '''
name: {{name}}
description: "A flutter3d graphics backend, started from the null backend: a device that keeps textures in memory and passes the conformance suite."
version: 0.1.0
# What a catalogue of backends is read by; not `flutter3d-plugin`, since a
# backend is opened through a device registry rather than installed.
topics:
  - flutter3d-backend

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  flutter3d_hardware: ^1.0.0-rc.1+2
  flutter3d_shaders: ^1.0.0-rc.1
  flutter3d_foundation: ^1.0.0-rc.1

# What makes a project's build compile its materials for this backend too:
# the build hook finds this among the project's dependencies and runs the
# compiler for this backend's section, as it runs impellerc for Impeller's.
flutter3d_backend:
  backend: '{{label}}'
  section: '{{label}}'
  compiler: bin/material_compiler.dart

dev_dependencies:
  flutter3d_conformance: ^1.0.0-rc.1
  flutter3d_core: ^1.0.0-rc.1
  test: ^1.25.0
  vector_math: ^2.2.0
''';

const String _backendCompiler = '''
// The {{label}} backend's material compiler as the build runs it: a project
// that depends on this package has its engine bundle and every plugin
// material compiled with `{{stem}}MaterialCompiler` too, because the pubspec's
// `flutter3d_backend:` names this file. The build hands it a request and a
// path, and reads the section back from there.
//
//     dart run {{name}}:material_compiler <request.json> <out>
import 'dart:io';

import 'package:{{name}}/{{name}}.dart';
import 'package:flutter3d_shaders/compile.dart' show runMaterialCompiler;

void main(List<String> arguments) =>
    exit(runMaterialCompiler(const {{stem}}MaterialCompiler(), arguments));
''';

const String _backendReadme = '''
# {{name}}

A flutter3d graphics backend, started from the null backend
(`examples/flutter3d_backend_null` in the engine's repository) by
`flutter3d create plugin --kind backend`.

As written, `{{stem}}Device` has no GPU: it keeps textures in memory,
clears, uploads, overwrites, copies and reads them back, and refuses every
pipeline at its first draw. It already passes every conformance check but
the shader tier.

## Using it

```dart
final registry = DeviceRegistry<Object>();
register{{stem}}Backend(registry);
final device = await registry.open(width: 320, height: 180);
```

## Conformance

```bash
dart test
```

`test/conformance_test.dart` runs `flutter3d_conformance` on the device.
Grow it into a backend for your API one step at a time:

1. Draw: compile the engine's stages (`compileStage` in
   `package:flutter3d_shaders/compile.dart` gives SPIR-V and your
   language's text), answer them from `shaders`, bind by `stageBindings`
   (`package:flutter3d_shaders/backend.dart`), and stop refusing
   pipelines. Then run `shaderChecks` as well.
2. Report each `DeviceFeature` as you implement it: the capability check
   fails on one reported and not done, and on one done and not reported.
3. Compile materials: `{{stem}}MaterialCompiler` writes your section of a
   shader bundle.

The guide for a backend's author is
https://flutter3d.pleion.dev/core/backends/.
''';

const String _backendChangelog = '''
## 0.1.0

- **The first release.** Created by `flutter3d create plugin --kind backend`.
''';
const String _backendLibrary = r'''
/// A flutter3d graphics backend with no GPU: the reference a backend from
/// outside the engine's repository is written from.
///
///     final registry = DeviceRegistry<Object>();
///     register{{stem}}Backend(registry);
///     final device = await registry.open(width: 320, height: 180);
///
/// It keeps textures in memory, clears, uploads and reads them back, and
/// refuses every pipeline at its first draw, so the engine's renderer runs
/// on it and a frame is the clear colour. It reaches the engine through
/// published libraries alone: `flutter3d_hardware` for the device contract
/// and its handles, `flutter3d_shaders/backend.dart` for the material
/// compiler, and nothing under another package's `src/`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';

import 'src/{{label}}_device.dart';

export 'src/{{label}}_device.dart';
export 'src/{{label}}_pass.dart';
export 'src/{{label}}_texels.dart';

/// Adds the {{label}} backend to [registry], and its material compiler to
/// [compilers] when given; the registration takes both out again.
///
/// Last added, first tried, as every backend added to a registry is;
/// [asFallback] makes it the one tried when nothing else opens.
Registration register{{stem}}Backend(
  DeviceRegistry<Object> registry, {
  MaterialCompilerRegistry? compilers,
  bool asFallback = false,
}) {
  final backend = registry.addBackend(
    {{stem}}Device.name,
    (DeviceRequest request) =>
        {{stem}}Device.open(width: request.width, height: request.height),
    asFallback: asFallback,
  );
  final compiler = compilers?.register(const {{stem}}MaterialCompiler());
  return Registration(() {
    compiler?.cancel();
    backend.cancel();
  });
}

/// What the build and `RuntimeShaders` ask to turn a material into this
/// backend's section of a shader bundle.
///
/// The section is the material's stage names, as JSON: a device that
/// compiles nothing needs nothing more to answer them by name. A backend
/// over a real API writes its compiled stages here instead, from
/// [MaterialCompileRequest.stages] (the material as GLSL) or from
/// `compileStage` in `package:flutter3d_shaders/compile.dart`.
final class {{stem}}MaterialCompiler extends MaterialCompiler {
  const {{stem}}MaterialCompiler();

  /// The device's `backendId`, which the registry matches exactly.
  @override
  String get backend => {{stem}}Device.name;

  /// [{{lowerStem}}Section], which no other backend's compiler may take.
  @override
  String get bundleSection => {{lowerStem}}Section;

  @override
  bool get compilesAtRunTime => true;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) =>
      MaterialCompileResult(
        section: ByteData.sublistView(
          utf8.encode(
            jsonEncode(<String>[
              for (final stage in request.stages) stage.name,
            ]),
          ),
        ),
      );
}
''';

const String _backendDevice = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '{{label}}_pass.dart';
import '{{label}}_texels.dart';

/// A [GraphicsDevice] with no GPU and no rasteriser: it keeps textures in
/// memory, clears, uploads, overwrites and reads them back, and refuses
/// every pipeline at its first draw.
///
/// **What a backend is, with the drawing taken out.** Every member here is
/// one a backend for Vulkan, Metal, Direct3D or a server renderer writes
/// too, against the same published libraries: the handles come from
/// `package:flutter3d_hardware/backend.dart`, a pass is a [PassEncoder]
/// with the [CommandEncoder] mixin, and what the device cannot do it says
/// through [features] and refuses by name. The engine's renderer runs on
/// it, a frame is the clear colour, and each pipeline the frame draws with
/// is reported once on [pipelineRefusals] and skipped.
///
/// Opened as every backend is, with [open], so `DeviceRegistry.addBackend`,
/// `flutter3d_testing`'s `renderFrame(device:)` and the conformance suite
/// take it as they take the four in the engine's repository.
///
/// **A member of a backend's own is best private, or named for the
/// backend.** A 1.x minor adds members with bodies to [GraphicsDevice] and
/// [PassEncoder], and a public member here that a later minor names too
/// either stops compiling against it or, with the same signature, silently
/// replaces the new default. [texelsOf] and [isDisposed] are public for this
/// package's tests, and are the two names this device would have to change
/// if a minor took them. That risk is the backend author's; the stability
/// section of `HAL.md` says so.
final class {{stem}}Device extends GraphicsDevice {
  {{stem}}Device._();

  /// Opens a device. The size is the one every backend is opened at; a
  /// device with no surface keeps none, and draws each pass at the size of
  /// its target.
  static Future<{{stem}}Device> open({
    required int width,
    required int height,
  }) async => {{stem}}Device._();

  /// The name a refusal from this device carries.
  static const String name = '{{label}}';

  @override
  String get backendName => name;

  /// [name], said outright rather than left to the default: the id a
  /// compiler and a manifest match is fixed for good, and must not follow a
  /// later rewording of the name people read.
  @override
  String get backendId => name;

  /// Little beyond the base contract: texture-to-texture copies, 32-bit
  /// float targets, which it holds as it holds every other, and 32-bit
  /// indices, which it takes as it takes any. A capability is reported when
  /// the device does it, and refused by name when asked of it otherwise; a
  /// backend grows this set as it grows, and the conformance suite holds
  /// each answer true both ways.
  @override
  final DeviceFeatures features = DeviceFeatures(const <DeviceFeature>{
    DeviceFeature.textureCopy,
    DeviceFeature.float32Renderable,
    DeviceFeature.indexUint32,
  });

  /// The defaults, with no compute: this device has no compute pass.
  @override
  final DeviceLimits limits = const DeviceLimits(
    maxColorAttachments: 4,
    maxSampleCount: 1,
    maxComputeWorkgroupStorageSize: 0,
    maxComputeInvocationsPerWorkgroup: 0,
    maxComputeWorkgroupSizeX: 0,
    maxComputeWorkgroupSizeY: 0,
    maxComputeWorkgroupSizeZ: 0,
    maxComputeWorkgroupsPerDimension: 0,
  );

  /// The formats this device holds: the eight-bit colours an image arrives
  /// in, the half and full float colours the engine renders in, and depth.
  /// Each is held as four floats a texel, so any of them clears, uploads and
  /// reads back.
  static const Set<TextureFormat> heldFormats = <TextureFormat>{
    TextureFormat.r8g8b8a8UNormInt,
    TextureFormat.b8g8r8a8UNormInt,
    TextureFormat.r16g16b16a16Float,
    TextureFormat.r32g32b32a32Float,
    TextureFormat.r32Float,
    TextureFormat.d32Float,
  };

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      switch (format) {
        TextureFormat.d32Float => const TextureFormatSupport(
          sampled: true,
          renderable: true,
          depthStencil: true,
        ),
        _ when heldFormats.contains(format) => const TextureFormatSupport(
          sampled: true,
          renderable: true,
        ),
        _ => TextureFormatSupport.none,
      };

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d32Float;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  int get preferredSampleCount => 1;

  // ------------------------------------------------------------- shaders

  /// Every stage the engine asks for, by name, compiled to nothing: the
  /// renderer is built on this device as on any other, and the pipelines it
  /// links are refused when they draw.
  @override
  final ShaderLibrary shaders = {{stem}}ShaderLibrary();

  /// A bundle is decoded, so bytes that are not one are refused the way
  /// every backend refuses them, and its stages are answered by name. The
  /// section this backend's compiler writes, when the bundle carries one,
  /// adds the materials compiled for it.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      {{stem}}LoadedShaderLibrary(ShaderBundle.decode(bytes));

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => wrapPipeline(
    owner: this,
    backend: Object(),
    name: '${vertex.name}+${fragment.name}',
  );

  // ------------------------------------------------------------ textures

  final Expando<{{stem}}Texels> _texels = Expando<{{stem}}Texels>('texels');

  /// The texels behind [texture], which this device made.
  {{stem}}Texels texelsOf(TextureHandle texture) {
    debugCheckLive(texture, '{{stem}}Device');
    final texels = _texels[texture];
    if (texels == null) {
      throw ArgumentError.value(texture, 'texture', 'was not made by $name');
    }
    return texels;
  }

  TextureHandle _make({
    required int width,
    required int height,
    required TextureFormat format,
    int layers = 1,
    int levels = 1,
    StorageMode storageMode = StorageMode.devicePrivate,
    TextureType type = TextureType.texture2D,
  }) {
    if (!heldFormats.contains(format)) {
      throw refuseResource(
        'a ${format.name} texture',
        '$name holds ${heldFormats.map((f) => f.name).join(', ')}',
      );
    }
    final texels = {{stem}}Texels(
      width: width,
      height: height,
      layers: layers,
      levels: levels,
    );
    final texture = wrapTexture(
      owner: this,
      backend: texels,
      width: width,
      height: height,
      format: format,
      storageMode: storageMode,
      type: type,
      mipLevelCount: levels,
    );
    _texels[texture] = texels;
    return texture;
  }

  /// A flat texture of one of [heldFormats], to draw into, overwrite or
  /// copy. Every other shape is refused by the feature it needs; writing
  /// one with `writeTexture` needs `DeviceFeature.textureWrites`, which this
  /// device does not report.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    // A volume is filled by `writeTexture` alone, so it is refused by that
    // first; the layered shapes a pass can draw into, a storage usage and
    // more than one sample are refused by the feature the descriptor names.
    final dimension = descriptor.dimension;
    if (dimension != TextureDimension.d2 &&
        dimension != TextureDimension.d2Array &&
        dimension != TextureDimension.cube &&
        dimension != TextureDimension.cubeArray) {
      throw refuse(DeviceFeature.textureWrites);
    }
    descriptor.checkFeatures(features, backend: name);
    return _make(
      width: descriptor.width,
      height: descriptor.height,
      format: descriptor.format,
      storageMode: descriptor is RenderTargetDescriptor
          ? descriptor.storageMode
          : StorageMode.devicePrivate,
    );
  }

  /// Refused by the feature the descriptor names first: `buffers`, which
  /// this device does not report.
  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    descriptor.checkFeatures(features, backend: name);
    throw refuse(DeviceFeature.buffers);
  }

  @override
  TransferEncoder beginTransferPass({String? label}) => {{stem}}Transfer(this);

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => throw refuse(DeviceFeature.cubeTextures);

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => throw refuse(DeviceFeature.cubeTextures);

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    if (mipLevels != null && mipLevels.isNotEmpty) {
      throw refuse(DeviceFeature.manualMipmaps);
    }
    final expected = width * height * format.bytesPerTexel;
    if (format.bytesPerTexel == 0 || pixels.lengthInBytes != expected) {
      throw refuseResource(
        'createTextureFromPixels',
        'a ${width}x$height ${format.name} texture takes $expected bytes and '
            '${pixels.lengthInBytes} were given',
      );
    }
    final texture = _make(
      width: width,
      height: height,
      format: format,
      storageMode: StorageMode.hostVisible,
    );
    texelsOf(texture).decode(format, pixels, layer: 0, level: 0);
    return texture;
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {
    if (!readbackFormats.contains(target.format)) {
      throw refuseResource(
        'overwriteTexture',
        'TextureFormat.${target.format.name} is not one of readbackFormats',
      );
    }
    if (mipLevel != 0) {
      throw refuseResource(
        'overwriteTexture',
        'mip level $mipLevel is refused; only the base level (0) may be '
            'overwritten',
      );
    }
    final rect = region ?? ScreenRect.of(target);
    if (rect.x < 0 ||
        rect.y < 0 ||
        rect.x + rect.width > target.width ||
        rect.y + rect.height > target.height) {
      throw ArgumentError(
        'overwriteTexture: $rect does not fit inside a '
        '${target.width}x${target.height} texture',
      );
    }
    if (rgba.lengthInBytes != rect.width * rect.height * 4) {
      throw ArgumentError(
        'overwriteTexture: ${rgba.lengthInBytes} bytes does not match '
        '${rect.width}x${rect.height} RGBA8',
      );
    }
    texelsOf(target).decodeRegion(target.format, rgba, rect);
  }

  @override
  void releaseTexture(TextureHandle texture) => _texels[texture] = null;

  // ------------------------------------------------------------ geometry

  final Expando<Uint8List> _bytes = Expando<Uint8List>('geometry');

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final copy = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final buffer = wrapGeometry(
      backend: copy,
      offsetInBytes: 0,
      lengthInBytes: copy.length,
      release: releaseGeometry,
    );
    _bytes[buffer] = copy;
    return buffer;
  }

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {
    debugCheckLive(target, 'overwriteGeometry');
    final held = target.backend;
    if (held is! Uint8List) {
      throw ArgumentError.value(target, 'target', 'was not made by $name');
    }
    final at = target.offsetInBytes + offsetInBytes;
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'overwriteGeometry: $offsetInBytes + ${bytes.lengthInBytes} does not '
        'fit inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    held.setRange(
      at,
      at + bytes.lengthInBytes,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  @override
  void releaseGeometry(GeometryBuffer geometry) => _bytes[geometry] = null;

  // -------------------------------------------------------------- frames

  @override
  void beginFrame() {}

  /// At once: a pass is done by the time it is submitted.
  @override
  void onFrameComplete(void Function() whenDone) => whenDone();

  /// Clears what the pass clears, and hands back a pass that refuses every
  /// pipeline it draws with.
  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    descriptor
      ..checkAttachmentLimit(limits.maxColorAttachments, backend: name)
      ..checkFeatures(features, backend: name);
    for (final color in descriptor.colors) {
      if (color.loadAction != LoadAction.clear) continue;
      // Every kind of clear as doubles, which hold an integer one exactly.
      final clear = (color.clearValue ?? ClearColor.transparentBlack).channels;
      texelsOf(color.texture).fill(
        layer: color.layer + color.face,
        level: color.mipLevel,
        r: clear[0],
        g: clear[1],
        b: clear[2],
        a: clear[3],
      );
    }
    final depth = descriptor.depth;
    if (depth != null && depth.loadAction == LoadAction.clear) {
      final value = depth.clearValue;
      texelsOf(depth.texture).fill(
        layer: depth.layer + depth.face,
        level: depth.mipLevel,
        r: value,
        g: value,
        b: value,
        a: value,
      );
    }
    return {{stem}}Pass(this);
  }

  /// The texels as they are now: the copy is taken when it is asked for,
  /// so a pass submitted after the call is not in it.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    final texels = texelsOf(texture);
    if (readbackConverts(texture, region: region)) {
      return Future<ByteData>.value(
        texels.encode(TextureFormat.r8g8b8a8UNormInt, ScreenRect.of(texture)),
      );
    }
    final rect = readbackRegionOf(texture, region);
    return Future<ByteData>.value(texels.encode(texture.format, rect));
  }

  // ------------------------------------------------------------ lifetime

  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  final StreamController<DeviceLoss> _lost =
      StreamController<DeviceLoss>.broadcast();

  /// One [DeviceLossReason.destroyed], when [dispose] runs: nothing else can
  /// take a device with no GPU away, and every backend owes a caller at
  /// least the loss it causes itself.
  @override
  Stream<DeviceLoss> get lost => _lost.stream;

  @override
  bool get isLost => _disposed;

  /// Says so on [lost], once, and closes it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lost.add(
      const DeviceLoss(
        reason: DeviceLossReason.destroyed,
        message: 'the device was disposed',
      ),
    );
    unawaited(_lost.close());
  }
}

/// Every stage name, answered with a handle that compiles to nothing.
final class {{stem}}ShaderLibrary with ShaderLibrary {
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  @override
  ShaderHandle? operator [](String name) => _handles.putIfAbsent(
    name,
    () => wrapShader(
      backend: name,
      name: name,
      release: (ShaderHandle h) => forgetShader(_handles, h),
    ),
  );
}

/// A loaded bundle's stages by name, kept across a reload that keeps them.
final class {{stem}}LoadedShaderLibrary with ShaderLibrary, LoadedShaderLibrary {
  {{stem}}LoadedShaderLibrary(ShaderBundle bundle)
    : _bundle = bundle,
      _names = _namesIn(bundle);

  ShaderBundle _bundle;
  Set<String> _names;
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  /// The stages [bundle] claims, and the materials in this backend's own
  /// section: what `{{stem}}MaterialCompiler` wrote, a JSON list of names.
  static Set<String> _namesIn(ShaderBundle bundle) {
    final section = bundle.section({{lowerStem}}Section);
    return <String>{
      ...bundle.names,
      if (section != null)
        ...(jsonDecode(
                  utf8.decode(
                    section.buffer.asUint8List(
                      section.offsetInBytes,
                      section.lengthInBytes,
                    ),
                  ),
                )
                as List<Object?>)
            .cast<String>(),
    };
  }

  @override
  String get name => _bundle.name;

  @override
  ShaderHandle? operator [](String name) => _names.contains(name)
      ? _handles.putIfAbsent(
          name,
          () => wrapShader(
            backend: name,
            name: name,
            release: (ShaderHandle h) => forgetShader(_handles, h),
          ),
        )
      : null;

  /// Takes [bytes] in place of the bundle, unless it drops a stage already
  /// handed out, which is refused naming it.
  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final names = _namesIn(bundle);
    final dropped = _handles.keys.where((n) => !names.contains(n));
    if (dropped.isNotEmpty) {
      throw ShaderBundleException(
        name: bundle.name,
        reason: 'it no longer has ${dropped.join(', ')}, already in use',
      );
    }
    _bundle = bundle;
    _names = names;
  }
}

/// The id of the {{label}} backend's section of a shader bundle.
const String {{lowerStem}}Section = '{{label}}';
''';

const String _backendPass = r'''
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '{{label}}_device.dart';

/// A render pass of the {{label}} backend: it takes every state a pass takes,
/// refuses by name what the device does not report, and skips each draw,
/// reporting its pipeline as refused once.
///
/// **Only the members without a body are here.** Every feature-gated member
/// of [PassEncoder] (indirect draws, storage buffers, the blend constant,
/// bundles) has a default that refuses with the feature named, which is
/// this device's answer; a backend that has the feature overrides it.
final class {{stem}}Pass extends PassEncoder with CommandEncoder {
  {{stem}}Pass(this.device);

  final {{stem}}Device device;

  PipelineHandle? _pipeline;
  bool _submitted = false;

  void _open(String operation) {
    if (_submitted) {
      throw StateError('$operation: the pass was already submitted');
    }
  }

  /// Refuses with [feature] named, unless the device reports it.
  void _need(DeviceFeature feature) =>
      device.features.require(feature, backend: {{stem}}Device.name);

  /// Any depth range; a rectangle off whole pixels is refused, since this
  /// device reports no fractional viewport. The viewport answers which.
  @override
  void setViewport(PassViewport viewport) {
    _open('setViewport');
    viewport.checkFeatures(device.features, backend: {{stem}}Device.name);
  }

  @override
  void setScissor(ScreenRect rect) => _open('setScissor');

  /// Triangle and line lists; strips and points are refused by the feature
  /// each needs, none of which this device reports. The topology answers
  /// which, so one a later release adds is refused here too.
  @override
  void setPrimitiveType(PrimitiveType type) {
    _open('setPrimitiveType');
    type.checkFeatures(device.features, backend: {{stem}}Device.name);
  }

  /// A fill is taken; edges are refused, since this device reports no
  /// wireframe and a refused line mode is never quietly filled.
  @override
  void setPolygonMode(PolygonMode mode) {
    _open('setPolygonMode');
    if (mode == PolygonMode.line) _need(DeviceFeature.wireframe);
  }

  @override
  void setCullMode(CullMode mode) => _open('setCullMode');

  @override
  void setWindingOrder(WindingOrder order) => _open('setWindingOrder');

  @override
  void setDepthWrite({required bool enabled}) => _open('setDepthWrite');

  @override
  void setDepthCompare(CompareFunction compare) => _open('setDepthCompare');

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      _need(DeviceFeature.stencil);

  @override
  void setStencilReference(int value) => _need(DeviceFeature.stencil);

  /// A blend that reads the constant or a second output, or takes a minimum
  /// or a maximum, is refused by the feature it needs: the state answers
  /// which, so a blend a later release adds is refused here too.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    _open('setBlend');
    state?.checkFeatures(device.features, backend: {{stem}}Device.name);
  }

  @override
  void bindPipeline(PipelineHandle pipeline) {
    _open('bindPipeline');
    debugCheckLive(pipeline, 'bindPipeline');
    _pipeline = pipeline;
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    _open('bindVertexBuffer');
    debugCheckLive(buffer, 'bindVertexBuffer');
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _open('bindVertexData');

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _open('bindIndexBuffer');
    debugCheckLive(buffer, 'bindIndexBuffer');
    type.checkFeatures(device.features, backend: {{stem}}Device.name);
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _open('bindIndexData');
    type.checkFeatures(device.features, backend: {{stem}}Device.name);
  }

  /// True: with no compiled stage there is nothing to reflect, so every
  /// block is taken, as a backend without reflection takes it.
  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    _open('bindUniformBlock');
    return true;
  }

  /// True, for the reason [bindUniformBlock] gives. A sampler asking for a
  /// comparison, a level clamp or a border is refused by the feature it
  /// needs, none of which this device reports; the sampler answers which,
  /// so a comparison alone is refused by the comparison.
  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    _open('bindTexture');
    debugCheckLive(texture, 'bindTexture');
    sampler?.checkFeatures(device.features, backend: {{stem}}Device.name);
    return true;
  }

  @override
  void clearBindings() => _open('clearBindings');

  /// Skipped, and the pipeline reported refused the first time it draws:
  /// this device rasterises nothing, and no rebuild changes that.
  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    _open('draw');
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('draw: no pipeline is bound');
    }
    if (device.pipelineRefusals.isRefused(pipeline)) return;
    device.pipelineRefusals.report(
      pipeline,
      PipelineRefusedException(
        pipeline: pipeline.name,
        backend: {{stem}}Device.name,
        reason: PipelineRefusalReason.other,
        detail: 'this backend rasterises nothing',
      ),
      retry: false,
    );
  }

  @override
  void submit() {
    _open('submit');
    _submitted = true;
  }
}

/// The {{label}} backend's copies: texture to texture, which it does at once,
/// and the rest refused by their features through [TransferEncoder]'s own
/// defaults, since it has no buffers.
final class {{stem}}Transfer extends TransferEncoder {
  {{stem}}Transfer(this.device);

  final {{stem}}Device device;

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    if (source.texture.format != destination.texture.format) {
      throw ArgumentError(
        'copyTextureToTexture: ${source.texture.format.name} into '
        '${destination.texture.format.name}; a copy keeps its format',
      );
    }
    for (var layer = 0; layer < depthOrArrayLayers; layer++) {
      device
          .texelsOf(destination.texture)
          .copyFrom(
            device.texelsOf(source.texture),
            from: TextureCopyLocation(
              source.texture,
              mipLevel: source.mipLevel,
              x: source.x,
              y: source.y,
              z: source.z + layer,
            ),
            to: TextureCopyLocation(
              destination.texture,
              mipLevel: destination.mipLevel,
              x: destination.x,
              y: destination.y,
              z: destination.z + layer,
            ),
            width: width,
            height: height,
          );
    }
  }

  @override
  void submit() {}
}
''';

const String _backendTexels = r'''
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// What a texture of the {{label}} backend holds: four floats a texel, for each
/// layer and level, whatever its format.
///
/// One representation for every format the device holds, so a clear, an
/// upload and a readback are each written once. A backend over a real API
/// keeps its texture in that API instead; this is the part of a backend
/// such an API does for it.
final class {{stem}}Texels {
  {{stem}}Texels({
    required this.width,
    required this.height,
    required int layers,
    required int levels,
  }) : _levels = <List<Float32List>>[
         for (var layer = 0; layer < layers; layer++)
           <Float32List>[
             for (var level = 0; level < levels; level++)
               Float32List(_side(width, level) * _side(height, level) * 4),
           ],
       ];

  final int width;
  final int height;
  final List<List<Float32List>> _levels;

  /// The width of [level].
  int widthAt(int level) => _side(width, level);

  /// A side of [level], halved per level and never below one texel.
  static int _side(int base, int level) =>
      base >> level < 1 ? 1 : base >> level;

  Float32List _at(int layer, int level) {
    RangeError.checkValidIndex(layer, _levels, 'layer');
    RangeError.checkValidIndex(level, _levels[layer], 'level');
    return _levels[layer][level];
  }

  /// Every texel of [layer] at [level] set to one colour: what a clear does,
  /// whatever the scissor says.
  void fill({
    required int layer,
    required int level,
    required double r,
    required double g,
    required double b,
    required double a,
  }) {
    final texels = _at(layer, level);
    for (var i = 0; i < texels.length; i += 4) {
      texels
        ..[i] = r
        ..[i + 1] = g
        ..[i + 2] = b
        ..[i + 3] = a;
    }
  }

  /// [bytes], laid out as [format], into the whole of [layer] at [level].
  void decode(
    TextureFormat format,
    ByteData bytes, {
    required int layer,
    required int level,
  }) {
    final w = widthAt(level);
    _decodeInto(
      format,
      bytes,
      ScreenRect(width: w, height: _at(layer, level).length ~/ 4 ~/ w),
      _at(layer, level),
      w,
    );
  }

  /// [bytes], eight-bit [format], into [rect] of the base level.
  void decodeRegion(TextureFormat format, ByteData bytes, ScreenRect rect) =>
      _decodeInto(format, bytes, rect, _at(0, 0), width);

  void _decodeInto(
    TextureFormat format,
    ByteData bytes,
    ScreenRect rect,
    Float32List into,
    int rowLength,
  ) {
    final size = format.bytesPerTexel;
    for (var y = 0; y < rect.height; y++) {
      for (var x = 0; x < rect.width; x++) {
        final from = (y * rect.width + x) * size;
        final to = ((rect.y + y) * rowLength + rect.x + x) * 4;
        final rgba = _read(format, bytes, from);
        into.setRange(to, to + 4, rgba);
      }
    }
  }

  /// A [width] by [height] box of [source], from [from], written at [to]:
  /// what a texture-to-texture copy does.
  void copyFrom(
    {{stem}}Texels source, {
    required TextureCopyLocation from,
    required TextureCopyLocation to,
    required int width,
    required int height,
  }) {
    final reading = source._at(from.z, from.mipLevel);
    final writing = _at(to.z, to.mipLevel);
    final readRow = source.widthAt(from.mipLevel);
    final writeRow = widthAt(to.mipLevel);
    for (var y = 0; y < height; y++) {
      final at = ((from.y + y) * readRow + from.x) * 4;
      writing.setRange(
        ((to.y + y) * writeRow + to.x) * 4,
        ((to.y + y) * writeRow + to.x + width) * 4,
        reading,
        at,
      );
    }
  }

  /// [rect] of the base level of the first layer, laid out as [format]:
  /// eight-bit RGBA or BGRA, row zero at the top.
  ByteData encode(TextureFormat format, ScreenRect rect) {
    final texels = _at(0, 0);
    final out = Uint8List(rect.width * rect.height * 4);
    final swap = format == TextureFormat.b8g8r8a8UNormInt;
    int byte(double v) => (v.clamp(0.0, 1.0) * 255.0).round();
    for (var y = 0; y < rect.height; y++) {
      for (var x = 0; x < rect.width; x++) {
        final from = ((rect.y + y) * width + rect.x + x) * 4;
        final to = (y * rect.width + x) * 4;
        out
          ..[to] = byte(texels[from + (swap ? 2 : 0)])
          ..[to + 1] = byte(texels[from + 1])
          ..[to + 2] = byte(texels[from + (swap ? 0 : 2)])
          ..[to + 3] = byte(texels[from + 3]);
      }
    }
    return out.buffer.asByteData();
  }
}

/// One texel of [format] at [at] in [bytes], as four floats.
List<double> _read(TextureFormat format, ByteData bytes, int at) {
  double unorm(int i) => bytes.getUint8(at + i) / 255.0;
  double half(int i) =>
      _halfToDouble(bytes.getUint16(at + i * 2, Endian.little));
  double single(int i) => bytes.getFloat32(at + i * 4, Endian.little);
  return switch (format) {
    TextureFormat.r8g8b8a8UNormInt => <double>[
      unorm(0),
      unorm(1),
      unorm(2),
      unorm(3),
    ],
    TextureFormat.b8g8r8a8UNormInt => <double>[
      unorm(2),
      unorm(1),
      unorm(0),
      unorm(3),
    ],
    TextureFormat.r16g16b16a16Float => <double>[
      half(0),
      half(1),
      half(2),
      half(3),
    ],
    TextureFormat.r32g32b32a32Float => <double>[
      single(0),
      single(1),
      single(2),
      single(3),
    ],
    TextureFormat.r32Float ||
    TextureFormat.d32Float => <double>[single(0), 0.0, 0.0, 1.0],
    _ => throw ArgumentError.value(format, 'format', 'is not held here'),
  };
}

/// An IEEE half-precision float, from its sixteen bits.
double _halfToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >> 10) & 0x1f;
  final mantissa = bits & 0x3ff;
  return switch (exponent) {
    0 => sign * mantissa * math.pow(2, -24),
    0x1f => mantissa == 0 ? sign * double.infinity : double.nan,
    _ => sign * (1 + mantissa / 1024) * math.pow(2, exponent - 15),
  };
}
''';

const String _backendConformance = r'''
/// The {{label}} backend, held to what `flutter3d_hardware` requires.
///
///     dart test test/conformance_test.dart
///
/// **Every check but the shader tier.** This device draws nothing, so the
/// checks that read back a drawn picture are a backend's next step, not
/// this one's: everything else (clears, uploads, readback, copies, the
/// capability report held true both ways, and every refusal) passes or
/// declines saying why.
library;

import 'package:{{name}}/{{name}}.dart';
import 'package:flutter3d_conformance/flutter3d_conformance.dart';

void main() => runDeviceConformance(
  backend: {{stem}}Device.name,
  makeDevice: {{stem}}Device.open,
  checks: conformanceChecks.where((c) => !shaderChecks.contains(c)).toList(),
);
''';

const String _backendDeviceTest = r'''
/// The {{label}} backend from the engine's side: opened through a registry, a
/// material compiled for it, a bundle loaded on it, and the renderer
/// drawing a frame there.
///
///     dart test test/{{label}}_device_test.dart
library;

import 'dart:typed_data';

import 'package:{{name}}/{{name}}.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a registry opens it, and the registration takes it out', () async {
    final registry = DeviceRegistry<Object>();
    final compilers = MaterialCompilerRegistry();
    final registration = register{{stem}}Backend(registry, compilers: compilers);
    expect(registry.backendNames, <String>[{{stem}}Device.name]);
    expect(compilers.forBackend({{stem}}Device.name), isA<{{stem}}MaterialCompiler>());
    final device = await registry.open(width: 8, height: 8);
    expect(device, isA<{{stem}}Device>());
    // The compiler is found by the id the device gives, exactly.
    // Mutation: name the compiler "Null".
    expect(
      compilers.forBackend((device as {{stem}}Device).backendId),
      isA<{{stem}}MaterialCompiler>(),
    );

    registration.cancel();
    expect(registry.backendNames, isEmpty);
    expect(compilers.forBackend({{stem}}Device.name), isNull);
  });

  test(
    'a material its compiler wrote is answered by a bundle it loads',
    () async {
      // Mutation: answer only the bundle's stage list, and the material the
      // section carries is not found.
      final compiled = const {{stem}}MaterialCompiler().compile(
        const MaterialCompileRequest(
          name: 'glow',
          from: 'glow.f3dmat',
          source: 'material glow {}',
          stages: <MaterialStageSource>[
            MaterialStageSource(name: 'glow', fragment: true, glsl: ''),
          ],
        ),
      );
      final bundle = ShaderBundle(
        name: 'plugin',
        sdk: '',
        stages: const <ShaderBundleStage>[
          ShaderBundleStage('PlainVertex', fragment: false),
        ],
        sections: <String, ByteData>{{{lowerStem}}Section: compiled.section},
      );
      final device = await {{stem}}Device.open(width: 8, height: 8);
      final library = await device.loadShaders(bundle.encode());
      expect(library['PlainVertex'], isNotNull);
      expect(library['glow'], isNotNull);
      expect(library['missing'], isNull);
    },
  );

  test('the engine draws a frame on it, and each pipeline it draws with is '
      'told refused once', () async {
    // Mutation: report a refusal at every draw rather than once, and the
    // second frame tells the same pipelines again.
    final device = await {{stem}}Device.open(width: 32, height: 24);
    final renderer = Renderer.create(device: device);
    final camera = CameraNode()..lookAt(Vector3(0.0, 0.0, -1.0));
    final scene = Scene()
      ..add(camera)
      ..add(
        MeshNode(
          DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1)).build()),
          RenderMaterial(name: 'box'),
        )..setPosition(0.0, 0.0, -4.0),
      );
    FrameResult frame() => renderer.render(
      width: 32,
      height: 24,
      scene: scene,
      views: <CameraView>[CameraView(camera: camera)],
    );

    final first = frame();
    expect(first.pipelineRefusals, isNotEmpty);
    expect(first.pipelineRefusals.map((r) => r.backend).toSet(), <String>{
      {{stem}}Device.name,
    });
    final pixels = await device.readback(first.frame);
    expect(pixels.lengthInBytes, 32 * 24 * 4);

    expect(frame().pipelineRefusals, isEmpty);
    renderer.dispose();
    device.dispose();
  });

  test('dispose is told on lost, once, as the device it destroyed', () async {
    // Mutation: dispose without a word on `lost`, as this device did, and a
    // caller listening for the loss never learns the device is gone.
    final device = await {{stem}}Device.open(width: 4, height: 4);
    final losses = <DeviceLoss>[];
    device.lost.listen(losses.add);
    device
      ..dispose()
      ..dispose();
    await Future<void>.delayed(Duration.zero);
    expect(losses.map((DeviceLoss l) => l.reason), <DeviceLossReason>[
      DeviceLossReason.destroyed,
    ]);
    expect(device.isLost, isTrue);
  });
}
''';
