/// Every name a plugin registers is in its namespace, and a registry brings
/// the registries that come with it (D23, D43).
///
///     dart test test/namespace_test.dart
///
/// Mutation: drop the length check from `nameProblem` and `acme.` alone
/// passes; drop the reserved check and a plugin called `f3d.x` claims the
/// engine's namespace; look up registries without their companions and the
/// last test finds no `_Lights`.
library;

import 'dart:io';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

PluginManifest _manifest(String id) =>
    PluginManifest(id: id, apiVersion: PluginApiVersion.current);

final class _Lights extends PluginRegistry {
  _Lights([this.scope]);

  final PluginScope? scope;

  @override
  _Lights forPlugin(PluginScope scope) => _Lights(scope);
}

final class _Steps extends PluginRegistry {
  _Steps(this.lights);

  final _Lights lights;

  @override
  _Steps forPlugin(PluginScope scope) => this;

  @override
  Iterable<PluginRegistry> get companions => <PluginRegistry>[lights];
}

final class _Asks extends Flutter3dPlugin {
  _Asks();

  _Lights? found;

  @override
  PluginManifest get manifest => PluginManifest(
    id: 'acme_lamps.flicker',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) => found = host.registry<_Lights>();
}

final class _Loop extends LoopRegistry {
  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  LoopRegistry forPlugin(PluginScope scope) => this;
}

final class _Events extends EventRegistry {
  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}

void main() {
  test('a plugin id names its namespace, up to the first dot', () {
    expect(_manifest('acme_frost.frost').namespace, 'acme_frost');
    expect(_manifest('trails').namespace, 'trails');
  });

  test('a name in the namespace passes; one outside is refused by name', () {
    final frost = _manifest('acme_frost.frost');
    expect(frost.nameProblem('acme_frost.haze', what: 'a step'), isNull);
    expect(frost.nameProblem('acme_frost.', what: 'a step'), isNotNull);
    final outside = frost.nameProblem('frost', what: 'a render step');
    expect(outside, contains('"frost"'));
    expect(outside, contains('acme_frost.<name>'));
    // Case-sensitive, like every name the engine compares.
    expect(frost.nameProblem('Acme_frost.haze', what: 'a step'), isNotNull);
  });

  test('a name is qualified into the namespace, or refused outside it', () {
    final editor = _manifest('acme_frost.editor');
    // Mutation: prefix a bare name with the whole id. The editor half of a
    // package would publish `acme_frost.editor.stoke` beside its runtime
    // half's `acme_frost.haze`, two namespaces for one package.
    expect(editor.qualify('stoke', what: 'the command'), 'acme_frost.stoke');
    expect(
      editor.qualify('acme_frost.stoke', what: 'the command'),
      'acme_frost.stoke',
    );
    // Mutation: accept any dotted name as given. A plugin could publish a
    // command under another package's namespace.
    expect(
      () => editor.qualify('acme_lamps.stoke', what: 'the command'),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"acme_lamps.stoke"'), contains('the command')),
        ),
      ),
    );
    expect(
      () => _manifest('f3d.lamps').qualify('lamp', what: 'the gizmo'),
      throwsA(isA<PluginException>()),
    );
    expect(
      () => editor.qualify('', what: 'the command'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('the engine\'s own packages register the engine\'s names', () {
    final sky = _manifest('flutter3d_addon_atmosphere.sky');
    expect(sky.isEngine, isTrue);
    expect(sky.nameProblem('sky', what: 'a render step'), isNull);
  });

  test('a package named like the engine\'s is a plugin from outside', () {
    // Mutation: decide engine-ness by the `flutter3d_` prefix again. pub.dev
    // reserves no prefix, so `flutter3d_fake` registers bare names that a
    // name the engine adds later collides with.
    for (final id in <String>['flutter3d_fake', 'flutter3d_fake.frost']) {
      final fake = _manifest(id);
      expect(fake.isEngine, isFalse, reason: id);
      expect(fake.nameProblem('frost', what: 'a render step'), isNotNull);
    }
    expect(_manifest('flame_flutter3d_fake').isEngine, isFalse);
    expect(_manifest('flutter3d_core').isEngine, isTrue);
  });

  test('the engine\'s namespaces are the packages it publishes and '
      'published', () {
    // Mutation: leave a package out of the list — its plugin is refused its
    // own bare names; add one that is not the engine's — somebody else's
    // package is let through.
    final published = <String>{
      for (final file in Directory('../../packages').listSync())
        if (file is Directory)
          for (final api in file.listSync())
            if (api is Directory && api.path.endsWith('/api'))
              for (final snapshot in api.listSync())
                if (snapshot.path.endsWith('.api'))
                  snapshot.uri.pathSegments.last.replaceAll('.api', ''),
    };
    final table = File(
      '../../packages/flutter3d_build/lib/migrations/0.8_to_1.0.yaml',
    ).readAsLinesSync();
    final renamed = <String>{
      for (final line
          in table
              .skipWhile((l) => l != '  renamed:')
              .skip(1)
              .takeWhile((l) => l.startsWith('    ')))
        line.trim().split(':').first,
    };
    expect(published, isNotEmpty);
    expect(renamed, contains('flutter3d_addon_camera'));
    expect(
      PluginManifest.engineNamespaces,
      unorderedEquals(<String>{...published, ...renamed}),
    );
  });

  test('a plugin may not take an area of the engine as its namespace', () {
    // Mutation: drop the reserved check from `idProblem` — a plugin called
    // `light` loses its MCP tools to the editor's when a minor adds one.
    for (final id in <String>['light', 'render.glow', 'physics']) {
      expect(_manifest(id).idProblem, contains('"${id.split('.').first}"'));
    }
    expect(_manifest('lighting').idProblem, isNull);
    expect(_manifest('acme_light').idProblem, isNull);
  });

  test('the reserved areas hold every area the engine names', () {
    // Mutation: add a tool area to a server and not to the list — a plugin
    // of that name is shadowed. Read from the snapshots and the sources.
    final areas = <String>{};
    final files = <FileSystemEntity>[
      for (final package in Directory('../../packages').listSync())
        for (final part in <String>['api', 'lib'])
          if (Directory('${package.path}/$part') case final dir
              when dir.existsSync())
            ...dir.listSync(recursive: true),
    ];
    for (final file in files) {
      final path = file.path;
      if (file is! File) continue;
      if (path.endsWith('.mcp')) {
        for (final line in file.readAsLinesSync()) {
          final words = line.trim().split(' ');
          if (words.first != 'tool' && words.first != 'alias') continue;
          areas.addAll(<String>[
            for (final name in <String>[
              words[1],
              if (words.length > 3) words[3],
            ])
              if (name.contains('.')) name.split('.').first,
          ]);
        }
      } else if (path.endsWith('.vm')) {
        for (final match in RegExp(
          r'ext\.flutter3d\.([A-Za-z_]+)\.',
        ).allMatches(file.readAsStringSync())) {
          areas.add(match[1]!);
        }
      } else if (path.endsWith('.dart')) {
        for (final match in RegExp(
          r"eventName = '([A-Za-z_]+)\.",
        ).allMatches(file.readAsStringSync())) {
          areas.add(match[1]!);
        }
      }
    }
    // The engine's own servers answer `flutter3d.schema`, under a package's
    // namespace, which no plugin from outside has.
    areas.remove('flutter3d');
    expect(areas, contains('light'));
    expect(areas, contains('physics'));
    expect(areas.difference(PluginManifest.reservedAreas), isEmpty);
  });

  test('no plugin from outside takes the engine\'s namespace', () {
    final squatter = _manifest('f3d.lamps');
    expect(squatter.isEngine, isFalse);
    expect(
      squatter.nameProblem('f3d.lamp', what: 'a light type'),
      contains('engine'),
    );
  });

  test('a registry\'s companions are found as if handed in', () {
    final lights = _Lights();
    final plugin = _Asks();
    PluginManager(
      loop: _Loop(),
      events: _Events(),
      registries: <PluginRegistry>[_Steps(lights)],
    ).installAll(<Flutter3dPlugin>[plugin]);
    expect(plugin.found, isNotNull);
    expect(plugin.found!.scope?.manifest.id, 'acme_lamps.flicker');
  });
}
