/// A plugin written as data: the `.f3dplugin` document, the permissions its
/// loader holds it to, and what it installs into an engine.
///
///     dart test test/data_plugin_test.dart
///
/// The v1 fixture is `test/fixtures/v1/glow.f3dplugin`, the file the format
/// policy's structure rule counts. Modules are assembled by hand in
/// `wasm/assemble.dart`. Each test names the mutation that would defeat it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart'
    show RuntimeBackends, renderDataSections;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart'
    show effectsSection;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        DataSection,
        EventDeclaration,
        Flutter3dPlugin,
        LoopPhase,
        PhaseKind,
        PluginPermission,
        PluginRegistry,
        RenderAnchor;
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/data_plugins.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

import 'support/install_refusal.dart';

import 'wasm/assemble.dart';

/// A document around [manifest] and [rest], as text.
String _document(
  Map<String, Object?> rest, {
  Map<String, Object?> manifest = const <String, Object?>{},
}) => jsonEncode(<String, Object?>{
  'f3dplugin': 1,
  'manifest': <String, Object?>{
    'id': 'gusts',
    'apiVersion': '1.0',
    ...manifest,
  },
  ...rest,
});

/// A source that fails the test if it is read: what a refused plugin must
/// never reach.
final class _Untouchable extends PluginSource {
  @override
  Future<Uint8List> read(String path) =>
      fail('the source was read for $path after the plugin was refused');
}

MemoryPluginSource _files(Map<String, String> files) =>
    MemoryPluginSource(<String, Uint8List>{
      for (final MapEntry(:key, :value) in files.entries)
        key: Uint8List.fromList(utf8.encode(value)),
    });

/// A module that writes step × one into wind[0] and publishes "gust".
Uint8List _gusts() {
  final m = ModuleBuilder();
  final set = m.import('field_set', 3, 0);
  final publish = m.import('publish', 3, 0);
  m.abi(
    step: <int>[
      ...konst(0), ...konst(0), localGet, 0, //
      call, set,
      ...konst(0), localGet, 0, localGet, 1,
      call, publish,
    ],
  );
  return m.build();
}

/// Every section the fixtures have, each from the package that reads it:
/// the simulation's `entityKinds`, the core's `materials` and
/// `renderSteps`, the particles' `effects`.
final DataSections _sections = DataSections(<DataSection>[
  entityKindsSection,
  ...renderDataSections,
  effectsSection,
]);

/// The section [name] of [document] as it writes it back.
List<Map<String, Object?>> _written(DataPluginDocument document, String name) =>
    <Map<String, Object?>>[
      for (final entry in document.toJson()[name]! as List<Object?>)
        entry! as Map<String, Object?>,
    ];

void main() {
  group('the document', () {
    test('keys a later minor put inside its entries are kept', () {
      // Mutation: build a phase, an event or a system without `unknown`,
      // and a tool of this build saving a 1.1 plugin drops what 1.1 said
      // inside each entry.
      final json =
          jsonDecode(File('test/fixtures/v4/glow.f3dplugin').readAsStringSync())
              as Map<String, Object?>;
      Map<String, Object?> later(Object? entry) => <String, Object?>{
        ...(entry! as Map<String, Object?>),
        'later': <String, Object?>{'minor': 1},
      };
      for (final key in <String>['phases', 'events', 'wasm']) {
        final list = json[key]! as List<Object?>;
        list[0] = later(list[0]);
      }
      final document = DataPluginDocument.fromJson(json, sections: _sections);
      const kept = <String, Object?>{
        'later': <String, Object?>{'minor': 1},
      };
      expect(document.phases.first.unknown, kept);
      expect(document.events.first.unknown, kept);
      expect(document.wasm.first.unknown, kept);
      final written = document.toJson();
      for (final key in <String>['phases', 'events', 'wasm']) {
        expect(
          (written[key]! as List<Object?>).first,
          containsPair('later', kept['later']),
          reason: key,
        );
      }
    });

    for (final version in <int>[1, 2, 3, 4]) {
      test('the v$version fixture reads, every key in its place', () {
        // Mutation: drop a key from `_read` or a section's `read`, or read
        // `present` as false. The fixture holds every key its version has,
        // so each is asked here.
        final document = DataPluginDocument.parse(
          File('test/fixtures/v$version/glow.f3dplugin').readAsStringSync(),
          sections: _sections,
        );
        expect(document.manifest.id, 'glow');
        expect(document.manifest.backends, <String>{'webgl', 'cpu'});
        expect(document.phases.map((p) => '${p.kind.name} ${p.name}'), <String>[
          'step weather',
          'frame shimmer',
        ]);
        expect(document.events.single.name, 'gust');
        // A class, not a record, so a later minor can say more of a section
        // read than its reader and its value.
        final read = document.sections['entityKinds']!;
        expect(read, isA<DataPluginSection>());
        expect(read.reader, same(entityKindsSection));
        final kinds = read.section as List<DataEntityKind>;
        // From version 4 a plugin's entity types are in its namespace, as
        // its install refuses any other.
        expect(
          kinds.map((k) => k.type),
          version < 4
              ? <String>['vent', 'wind_marker']
              : <String>['glow.vent', 'glow.wind_marker'],
        );
        expect(kinds.first.requires, <String>['size', 'strength']);
        expect(kinds.first.collider, ColliderKind.trigger);
        expect(
          _written(document, 'materials').single['text'],
          contains('material Glow'),
        );
        final haze = _written(document, 'renderSteps').single;
        expect(haze['anchor'], RenderAnchor.afterTonemap.name);
        expect(haze['present'], isTrue);
        expect(haze['shaders'], <String, String>{'webgl': 'haze.frag'});
        final blow = document.wasm.single;
        expect(blow.phase, 'weather');
        expect(
          blow.fields.take(2).map((f) => '${f.name}:${f.writable}'),
          <String>['wind:true', 'heat:false'],
        );
        expect(blow.limits.memoryPages, 1);
        expect(document.sections.keys, <String>[
          'entityKinds',
          'materials',
          'renderSteps',
          'effects',
        ]);
        expect(document.resources, <String>['gusts.wasm', 'haze.frag']);
      });
    }

    test('the runtime reads none of a subsystem\'s sections itself', () {
      // Mutation: put `materials` back among the runtime's keys. The
      // document would be read with the render core's types, and the
      // package would need the render core on a replaying server again.
      final document = DataPluginDocument.parse(
        File('test/fixtures/v3/glow.f3dplugin').readAsStringSync(),
      );
      expect(document.sections, isEmpty);
      expect(document.extra.keys, <String>[
        'entityKinds',
        'materials',
        'renderSteps',
        'effects',
        'catalogue',
      ]);
      expect(DataSections.runtimeKeys, <String>{
        'f3dplugin',
        'manifest',
        'phases',
        'events',
        'wasm',
        // The render modules are the runtime's to decode and instantiate;
        // the render step each drives stays a section a reader reads.
        'wasmRender',
        'expressions',
      });
      // Written back as read, so a tool on a server loses nothing.
      expect(document.toJson()['materials'], isA<List<Object?>>());
    });

    test('the package depends on the plugin API alone', () {
      // Mutation: import the core or the simulation from `lib/` again. The
      // pubspec would have to name it, and this says which one came back.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final dependencies = RegExp(
        r'^dependencies:\n((?:  .*\n|\s*\n|  #.*\n)*)',
        multiLine: true,
      ).firstMatch(pubspec)![1]!;
      expect(
        RegExp(
          r'^  (\w+):',
          multiLine: true,
        ).allMatches(dependencies).map((m) => m[1]),
        <String>['flutter3d_plugin_api'],
      );
    });

    test('what this build does not know is kept and written back', () {
      // Mutation: build `toJson` from the known keys alone. A tool that
      // reads a document and writes it back strips a later minor's keys.
      final text = File('test/fixtures/v1/glow.f3dplugin').readAsStringSync();
      final document = DataPluginDocument.parse(text, sections: _sections);
      expect(document.extra.keys, <String>['catalogue']);
      expect(document.manifest.extra['homepage'], 'https://example.com/glow');
      final again = DataPluginDocument.fromJson(
        document.toJson(),
        sections: _sections,
      );
      expect(jsonEncode(again.toJson()), jsonEncode(document.toJson()));
      expect(again.toJson()['catalogue'], <String, Object?>{
        'demo': 'https://example.com/glow/play',
      });
    });

    test('a document from a newer engine is refused, saying which', () {
      // Mutation: gate on `version != formatVersion`. Every older document
      // would be refused too; this one must be refused for being newer.
      expect(
        () => DataPluginDocument.fromJson(<String, Object?>{
          'f3dplugin': DataPluginDocument.formatVersion + 1,
        }),
        throwsA(
          isA<DataPluginFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer than this build'),
          ),
        ),
      );
      expect(
        () => DataPluginDocument.parse('{"manifest": {}}'),
        throwsA(isA<DataPluginFormatException>()),
        reason: 'a document with no version is not one',
      );
    });

    test('an event a system publishes must be declared', () {
      // Mutation: skip the check against "events". Two plugins publishing
      // one undeclared name would collide on the bus with nobody told.
      expect(
        () => DataPluginDocument.parse(
          _document(<String, Object?>{
            'wasm': <Object?>[
              <String, Object?>{
                'module': 'g.wasm',
                'system': 'blow',
                'phase': 'rules',
                'events': <String>['gust'],
              },
            ],
          }),
        ),
        throwsA(
          isA<DataPluginFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"gust"'), contains('blow')),
          ),
        ),
      );
    });

    test('a render step sits on the side of tone mapping it reads', () {
      // Mutation: drop the anchor checks. A stage over the finished picture
      // placed before tone mapping reads a frame that does not exist yet.
      String step(String anchor, {bool present = false}) =>
          _document(<String, Object?>{
            'renderSteps': <Object?>[
              <String, Object?>{
                'name': 'haze',
                'anchor': anchor,
                'present': present,
                'shaders': <String, String>{'webgl': 'haze.frag'},
              },
            ],
          });
      DataPluginDocument parse(String text) =>
          DataPluginDocument.parse(text, sections: _sections);
      expect(
        () => parse(step('afterBloom', present: true)),
        throwsA(isA<DataPluginFormatException>()),
      );
      expect(
        () => parse(step('beforePresent')),
        throwsA(isA<DataPluginFormatException>()),
      );
      expect(
        _written(parse(step('afterBloom')), 'renderSteps').single['anchor'],
        RenderAnchor.afterBloom.name,
        reason: 'an engine anchor is accepted as Dart spells it',
      );
      // Mutation: refuse a name the engine does not have. Another plugin
      // may add that anchor to the renderer (`RendererSteps.addAnchor`), so
      // the name is kept and resolved through the renderer at install.
      expect(
        _written(
          parse(step('after everything')),
          'renderSteps',
        ).single['anchor'],
        'after everything',
        reason: 'a plugin\'s anchor is resolved by the renderer, not here',
      );
    });

    test('a version-2 script is read as an expression system', () {
      // Mutation: drop the 2 → 3 step. The script's declaration is kept as
      // an unknown key, and the system is lost without a word.
      final document = DataPluginDocument.fromJson(<String, Object?>{
        'format': 'f3d.plugin',
        'version': 2,
        'manifest': <String, Object?>{'id': 'gusts', 'apiVersion': '1.0'},
        'events': <Object?>[
          <String, Object?>{'name': 'gust'},
        ],
        'scripts': <Object?>[
          <String, Object?>{
            'source': 'blow.dart',
            'system': 'blow',
            'phase': 'rules',
            'writes': <String>['wind'],
            'events': <String>['gust'],
          },
        ],
      });
      final blow = document.expressions.single;
      expect(blow.source, 'blow.dart');
      expect(blow.system, 'blow');
      expect(blow.writes, <String>['wind']);
      expect(document.extra, isEmpty);
      final written = document.toJson();
      expect(written['version'], DataPluginDocument.formatVersion);
      expect(written.containsKey('scripts'), isFalse);
      expect(written['expressions'], hasLength(1));
      expect(document.resources, <String>['blow.dart']);
    });

    test('an expression system is a file or its text', () {
      expect(
        () => DataPluginDocument.parse(
          _document(<String, Object?>{
            'expressions': <Object?>[
              <String, Object?>{'system': 'blow', 'phase': 'rules'},
            ],
          }),
        ),
        throwsA(
          isA<DataPluginFormatException>().having(
            (e) => e.message,
            'message',
            contains('"source" file or its "text"'),
          ),
        ),
      );
    });

    test('a material is a file or its text, and an id is well formed', () {
      // Mutation: accept both keys and read one. The other is silently not
      // the material that draws.
      expect(
        () => DataPluginDocument.parse(
          _document(<String, Object?>{
            'materials': <Object?>[
              <String, Object?>{'source': 'a.f3dmat', 'text': 'material A {}'},
            ],
          }),
          sections: _sections,
        ),
        throwsA(isA<DataPluginFormatException>()),
      );
      expect(
        () => DataPluginDocument.parse(
          _document(
            const <String, Object?>{},
            manifest: <String, Object?>{'id': 'Gusts!'},
          ),
        ),
        throwsA(isA<DataPluginFormatException>()),
      );
    });

    test('a data plugin is never the engine\'s, whatever id it says', () {
      // A `.f3dplugin` from a mod folder says what it likes about itself.
      // Mutation: check only `idProblem` — a document that says
      // `flutter3d_post.glow` installs with the engine's rights.
      for (final id in <String>['flutter3d_post.glow', 'flutter3d_core']) {
        expect(
          () => DataPluginDocument.parse(
            _document(
              const <String, Object?>{},
              manifest: <String, Object?>{'id': id},
            ),
          ),
          throwsA(
            isA<DataPluginFormatException>().having(
              (e) => e.message,
              'message',
              contains('"$id"'),
            ),
          ),
          reason: id,
        );
      }
    });
  });

  group('permissions', () {
    test('a permission declared and not granted refuses the whole plugin', () {
      // Mutation: check grants only when a door is used. A plugin that asks
      // for the network up front would load, and be refused mid-game.
      expect(
        () => const DataPluginLoader().load(
          _document(
            const <String, Object?>{},
            manifest: <String, Object?>{
              'permissions': <String>['network'],
            },
          ),
          _Untouchable(),
        ),
        throwsA(
          isA<PermissionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"gusts"'), contains('network')),
          ),
        ),
      );
    });

    test('a URL needs network, declared and granted', () async {
      // Mutation: fetch whatever is a URL. A data plugin would reach the
      // network without anyone having granted it.
      final material = _document(<String, Object?>{
        'materials': <Object?>[
          <String, Object?>{'source': 'https://example.com/glow.f3dmat'},
        ],
      });
      await expectLater(
        DataPluginLoader(
          grants: PluginGrants(<PluginPermission>[PluginPermission.network]),
          sections: _sections,
        ).load(material, _Untouchable()),
        throwsA(
          isA<PermissionException>().having(
            (e) => e.message,
            'message',
            contains('does not declare it'),
          ),
        ),
      );
      final fetched = <Uri>[];
      final plugin =
          await DataPluginLoader(
            grants: PluginGrants(<PluginPermission>[PluginPermission.network]),
            sections: _sections,
            fetch: (url) async {
              fetched.add(url);
              return Uint8List.fromList(
                utf8.encode(
                  'material Glow { fragment { return vec4(albedo, '
                  'alpha); } }',
                ),
              );
            },
          ).load(
            _document(
              <String, Object?>{
                'materials': <Object?>[
                  <String, Object?>{
                    'source': 'https://example.com/glow.f3dmat',
                  },
                ],
              },
              manifest: <String, Object?>{
                'permissions': <String>['network'],
              },
            ),
            _Untouchable(),
          );
      expect(fetched, <Uri>[Uri.parse('https://example.com/glow.f3dmat')]);
      expect(plugin.manifest.id, 'gusts');
    });

    test('a path out of the plugin\'s directory needs files', () async {
      // Mutation: read `../` through the plugin's own source. A plugin would
      // read whatever sits beside its folder.
      final escaping = _document(
        <String, Object?>{
          'materials': <Object?>[
            <String, Object?>{'source': '../shared/glow.f3dmat'},
          ],
        },
        manifest: <String, Object?>{
          'permissions': <String>['files'],
        },
      );
      await expectLater(
        DataPluginLoader(sections: _sections).load(escaping, _Untouchable()),
        throwsA(isA<PermissionException>()),
        reason: 'declared, and not granted',
      );
      final read = <String>[];
      await DataPluginLoader(
        grants: PluginGrants(<PluginPermission>[PluginPermission.files]),
        sections: _sections,
        readFile: (path) async {
          read.add(path);
          return Uint8List.fromList(
            utf8.encode(
              'material Glow { fragment { return vec4(albedo, '
              'alpha); } }',
            ),
          );
        },
      ).load(escaping, _Untouchable());
      expect(read, <String>['../shared/glow.f3dmat']);
    });

    test(
      'its own files need nothing, and a stranger scheme is refused',
      () async {
        // Mutation: treat any scheme as a path. `ftp:` would reach the
        // plugin's source, which knows nothing about it.
        final plugin = await DataPluginLoader(sections: _sections).load(
          _document(<String, Object?>{
            'materials': <Object?>[
              <String, Object?>{'source': 'glow.f3dmat'},
            ],
          }),
          _files(<String, String>{
            'glow.f3dmat':
                'material Glow { fragment { return vec4(albedo, alpha); } }',
          }),
        );
        expect(
          _written(plugin.document, 'materials').single['source'],
          'glow.f3dmat',
        );
        await expectLater(
          DataPluginLoader(sections: _sections).load(
            _document(<String, Object?>{
              'materials': <Object?>[
                <String, Object?>{'source': 'ftp://example.com/glow.f3dmat'},
              ],
            }),
            _Untouchable(),
          ),
          throwsA(isA<DataPluginFormatException>()),
        );
      },
    );
  });

  group('installed', () {
    test(
      'phases, events and kinds arrive, and leave when switched off',
      () async {
        // Mutation: register the kinds outside the host's scoped registry.
        // Switching the plugin off would leave a kind a level may still name.
        final plugin = await DataPluginLoader(sections: _sections).load(
          _document(<String, Object?>{
            'phases': <Object?>[
              <String, Object?>{
                'name': 'weather',
                'after': <String>['physics'],
                'before': <String>['elements'],
              },
            ],
            'events': <Object?>[
              <String, Object?>{'name': 'gust'},
            ],
            'entityKinds': <Object?>[
              <String, Object?>{'type': 'gusts.vent', 'collider': 'trigger'},
            ],
          }),
          _files(const <String, String>{}),
        );
        final kinds = EntityKinds();
        final loop = EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[kinds],
          plugins: <Flutter3dPlugin>[plugin],
        );
        expect(loop.phases(PhaseKind.step).map((p) => p.name), <String>[
          'input',
          'movers',
          'physics',
          'gusts.weather',
          'fields',
          'rules',
          'publish',
        ]);
        // The engine's own (the floating origin) is the application's.
        bool ours(EventDeclaration d) => d.declaredBy != 'app';
        expect(loop.events.declared.where(ours).map((d) => d.name), <String>[
          'gusts.gust',
        ]);
        expect(kinds.registry()['gusts.vent'], isA<DataEntityKind>());

        loop.plugins.disable('gusts');
        loop.runSteps(1);
        expect(
          loop.phases(PhaseKind.step).map((p) => p.name),
          isNot(contains('gusts.weather')),
        );
        expect(loop.events.declared.where(ours), isEmpty);
        expect(kinds.registry()['gusts.vent'], isNull);
      },
    );

    test('a phase is filed under the plugin, and so is every reference '
        'to it', () async {
      // Mutation: add the phase under the name the document gives it, or
      // prefix the Wasm system's phase but not the phase itself. The loop
      // then holds a bare `weather` (refused: it is outside the namespace)
      // or a system in a phase that is not there.
      final plugin = await const DataPluginLoader().load(
        jsonEncode(<String, Object?>{
          'format': 'f3d.plugin',
          'version': DataPluginDocument.formatVersion,
          'manifest': <String, Object?>{'id': 'gusts', 'apiVersion': '1.0'},
          'phases': <Object?>[
            <String, Object?>{
              'name': 'weather',
              'after': <String>['physics'],
            },
            <String, Object?>{
              'name': 'calm',
              'after': <String>['weather'],
              'before': <String>['fields'],
            },
          ],
          'wasm': <Object?>[
            <String, Object?>{
              'module': 'gusts.wasm',
              'system': 'blow',
              'phase': 'calm',
              'fields': <Object?>[
                <String, Object?>{'name': 'wind', 'write': true},
              ],
            },
          ],
        }),
        MemoryPluginSource(<String, Uint8List>{'gusts.wasm': _gusts()}),
      );
      final wind = Float64List(1);
      final loop = EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[
          WorldFields(<WorldField>[ListWorldField('wind', wind)]),
        ],
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(loop.phases(PhaseKind.step).map((p) => p.name), <String>[
        'input',
        'movers',
        'physics',
        'gusts.weather',
        'gusts.calm',
        'fields',
        'rules',
        'publish',
      ]);
      expect(loop.systemsIn(const LoopPhase.step('gusts.calm')), <String>[
        'gusts.blow',
      ]);
      // Written back as the author wrote it: the prefix is the install's.
      expect(
        (plugin.document.toJson()['phases']! as List<Object?>).map(
          (p) => (p! as Map<String, Object?>)['name'],
        ),
        <String>['weather', 'calm'],
      );
    });

    test('a Wasm system ordered against another of its own finds it under '
        'the plugin', () async {
      // Mutation: hand `after` to the loop as written. `settle` then waits
      // on a bare `blow`, which no system in the loop is called, and runs
      // in no order the document asked for.
      final plugin = await const DataPluginLoader().load(
        jsonEncode(<String, Object?>{
          'format': 'f3d.plugin',
          'version': DataPluginDocument.formatVersion,
          'manifest': <String, Object?>{'id': 'gusts', 'apiVersion': '1.0'},
          'phases': <Object?>[
            <String, Object?>{
              'name': 'weather',
              'after': <String>['physics'],
            },
          ],
          'wasm': <Object?>[
            for (final (system, after) in <(String, List<String>)>[
              ('settle', <String>['blow']),
              ('blow', <String>[]),
            ])
              <String, Object?>{
                'module': 'gusts.wasm',
                'system': system,
                'phase': 'weather',
                'after': after,
                'fields': <Object?>[
                  <String, Object?>{'name': 'wind', 'write': true},
                ],
              },
          ],
        }),
        MemoryPluginSource(<String, Uint8List>{'gusts.wasm': _gusts()}),
      );
      final loop = EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[
          WorldFields(<WorldField>[ListWorldField('wind', Float64List(1))]),
        ],
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(loop.systemsIn(const LoopPhase.step('gusts.weather')), <String>[
        'gusts.blow',
        'gusts.settle',
      ]);
    });

    test('a version 3 phase already in the namespace is not filed twice', () {
      // Mutation: lift 3 → 4 by the identity. A version 3 document that
      // named its phase `gusts.weather` to pass the namespace check would
      // install `gusts.gusts.weather`, and its Wasm system would land in a
      // phase no other plugin can order against by the name it wrote.
      final document = DataPluginDocument.fromJson(<String, Object?>{
        'format': 'f3d.plugin',
        'version': 3,
        'manifest': <String, Object?>{'id': 'gusts', 'apiVersion': '1.0'},
        'phases': <Object?>[
          <String, Object?>{
            'name': 'gusts.weather',
            'after': <String>['physics'],
          },
          <String, Object?>{
            'name': 'still',
            'after': <String>['gusts.weather'],
            'before': <String>['other.phase'],
          },
        ],
        'wasm': <Object?>[
          <String, Object?>{
            'module': 'gusts.wasm',
            'system': 'blow',
            'phase': 'gusts.weather',
          },
        ],
        'expressions': <Object?>[
          <String, Object?>{
            'system': 'sway',
            'phase': 'gusts.weather',
            'text': 'wind[0] = 1',
          },
        ],
      });
      expect(document.phases.map((p) => p.name), <String>['weather', 'still']);
      expect(document.phases.last.after, <String>['weather']);
      // Another plugin's phase, and the engine's, are named as written.
      expect(document.phases.last.before, <String>['other.phase']);
      expect(document.phases.first.after, <String>['physics']);
      expect(document.wasm.single.phase, 'weather');
      expect(document.expressions.single.phase, 'weather');
    });

    test('a Wasm system from the document steps the world', () async {
      // Mutation: decode the module at install rather than at load. A module
      // that is not ABI 1 would be found at a step boundary mid-game rather
      // than when the plugin was read.
      final plugin = await const DataPluginLoader().load(
        _document(<String, Object?>{
          'events': <Object?>[
            <String, Object?>{'name': 'gust'},
          ],
          'wasm': <Object?>[
            <String, Object?>{
              'module': 'gusts.wasm',
              'system': 'blow',
              'phase': 'elements',
              'fields': <Object?>[
                <String, Object?>{'name': 'wind', 'write': true},
              ],
              'events': <String>['gust'],
            },
          ],
        }),
        MemoryPluginSource(<String, Uint8List>{'gusts.wasm': _gusts()}),
      );
      final wind = Float64List(1);
      final heard = <List<int>>[];
      final loop = EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[
          WorldFields(<WorldField>[ListWorldField('wind', wind)]),
        ],
        plugins: <Flutter3dPlugin>[plugin],
      );
      loop.events.onStep<PluginDataEvent>('heard', (d) {
        if (d.event.name == 'gusts.gust') heard.add(d.event.values);
      });
      loop.runSteps(3);
      expect(loop.systemsIn(LoopPhase.fields), <String>['gusts.blow']);
      expect(wind[0], Fixed16.toDouble(2));
      expect(heard.map((v) => v.first), <int>[0, 1, 2]);
      expect(plugin.save().keys, <String>['gusts.blow']);

      await expectLater(
        const DataPluginLoader().load(
          _document(<String, Object?>{
            'wasm': <Object?>[
              <String, Object?>{
                'module': 'broken.wasm',
                'system': 'blow',
                'phase': 'elements',
              },
            ],
          }),
          MemoryPluginSource(<String, Uint8List>{
            'broken.wasm': Uint8List.fromList(<int>[0, 1, 2, 3]),
          }),
        ),
        throwsA(isA<WasmException>()),
      );
    });

    test('kinds with no EntityKinds, or shaders with no RuntimeShaders, are '
        'refused by name', () async {
      // Mutation: skip a part the engine cannot take. The plugin would be
      // on, and a level naming its kind would fail as an unknown type.
      final withKinds = await DataPluginLoader(sections: _sections).load(
        _document(<String, Object?>{
          'entityKinds': <Object?>[
            <String, Object?>{'type': 'vent'},
          ],
        }),
        _files(const <String, String>{}),
      );
      expect(
        installRefusal(
          EngineLoop(
            input: InputState(),
            plugins: <Flutter3dPlugin>[withKinds],
          ).plugins,
        ),
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          allOf(contains('vent'), contains('EntityKinds')),
        ),
      );
      final withMaterial = await DataPluginLoader(sections: _sections).load(
        _document(<String, Object?>{
          'materials': <Object?>[
            <String, Object?>{
              'text':
                  'material Glow { fragment { return vec4(albedo, alpha); } }',
            },
          ],
          'effects': <Object?>[
            <String, Object?>{'name': 'embers'},
          ],
        }),
        _files(const <String, String>{}),
      );
      expect(
        installRefusal(
          EngineLoop(
            input: InputState(),
            backend: RuntimeBackends.cpu,
            plugins: <Flutter3dPlugin>[withMaterial],
          ).plugins,
        ),
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          contains('RuntimeShaders'),
        ),
      );
      // An engine that draws nothing installs it and says what it left out.
      EngineLoop(input: InputState(), plugins: <Flutter3dPlugin>[withMaterial]);
      expect(withMaterial.notes, hasLength(2));
      expect(withMaterial.notes.first, contains('draws nothing'));
      expect(withMaterial.notes.last, contains('effect description'));
    });

    test('an expression system is refused at install, by name', () async {
      // Mutation: install the rest and skip the system. The simulation would
      // run without one of its rules and replay as another simulation.
      final plugin = await const DataPluginLoader().load(
        _document(<String, Object?>{
          'phases': <Object?>[
            <String, Object?>{'name': 'weather'},
          ],
          'expressions': <Object?>[
            <String, Object?>{
              'system': 'settle',
              'phase': 'weather',
              'text': 'heat = heat * 0.99',
            },
          ],
        }),
        _files(const <String, String>{}),
      );
      expect(plugin.document.expressions.single.text, 'heat = heat * 0.99');
      expect(
        installRefusal(
          EngineLoop(
            input: InputState(),
            plugins: <Flutter3dPlugin>[plugin],
          ).plugins,
        ),
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"gusts"'), contains('settle')),
        ),
      );
    });

    test('a view plugin adding a step phase is refused by the loop', () async {
      // Mutation: install phases outside the host's scoped loop. A view
      // plugin would add to the step, which its switches promise not to.
      final plugin = await const DataPluginLoader().load(
        _document(
          <String, Object?>{
            'phases': <Object?>[
              <String, Object?>{'name': 'weather', 'kind': 'step'},
            ],
          },
          manifest: <String, Object?>{'touches': 'view'},
        ),
        _files(const <String, String>{}),
      );
      expect(
        installRefusal(
          EngineLoop(
            input: InputState(),
            plugins: <Flutter3dPlugin>[plugin],
          ).plugins,
        ),
        isA<PluginException>(),
      );
    });
  });

  test('an entity kind reads and writes its declaration', () {
    // Mutation: write the collider under another name. A tool that rewrites
    // a document would turn every trigger into a marker.
    final kind = DataEntityKind.fromJson(<String, Object?>{
      'type': 'vent',
      'requires': <String>['size'],
      'collider': 'static',
    }, owner: 'gusts');
    expect(kind.toJson(), <String, Object?>{
      'type': 'vent',
      'requires': <String>['size'],
      'collider': 'static',
    });
    expect(
      () => DataEntityKind.fromJson(<String, Object?>{
        'type': 'vent',
        'collider': 'wobbly',
      }, owner: 'gusts'),
      throwsA(isA<Flutter3dFormatException>()),
    );
  });
}
