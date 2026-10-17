import 'dart:io';

import 'package:api_snapshot/schema_snapshot.dart';
import 'package:test/test.dart';

import '../../structure/api.dart';
import '../../structure/schema.dart';

/// A throwaway package with the given files under `lib/`.
Directory _package(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('schema_snapshot');
  addTearDown(() => root.deleteSync(recursive: true));
  File('${root.path}/pubspec.yaml').writeAsStringSync('name: p\n');
  for (final file in files.entries) {
    File('${root.path}/lib/${file.key}')
      ..createSync(recursive: true)
      ..writeAsStringSync(file.value);
  }
  return root;
}

ServerSurface _server(List<Map<String, Object?>> tools) => <String, Object?>{
  'name': 's',
  'schemaVersion': '1.0.0',
  'aliases': const <String, String>{},
  'tools': tools,
};

void main() {
  test('a tool is its name, its first sentence and its arguments, with the '
      'prose taken out and the required set sorted', () {
    final text = renderMcp('p', <ServerSurface>[
      _server(<Map<String, Object?>>[
        <String, Object?>{
          'name': 'go',
          'description': 'Goes somewhere. Then says where it went.',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'to': <String, Object?>{
                'type': 'string',
                'description': 'hint-text',
              },
              // A field *named* description is an argument, not prose.
              'description': <String, Object?>{'type': 'string'},
            },
            'required': <String>['to', 'description'],
          },
        },
      ]),
    ]);
    // Mutation: keep `description` inside a schema. Every reworded hint
    // becomes a snapshot change somebody has to classify.
    expect(text, contains('tool go\n  says Goes somewhere.\n'));
    expect(text, contains('  arg description required {"type":"string"}\n'));
    expect(text, contains('  arg to required {"type":"string"}\n'));
    expect(text, isNot(contains('hint-text')));
  });

  test('a snapshot rendered here reads back as no change at all', () {
    final text = renderMcp('p', <ServerSurface>[
      _server(<Map<String, Object?>>[
        <String, Object?>{
          'name': 'go',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'mode': <String, Object?>{
                'type': 'string',
                'enum': <String>['walk', 'run'],
              },
            },
          },
        },
      ]),
    ]);
    // Mutation: write `arg` lines the parser cannot split. The classifier
    // would call every tool changed.
    expect(classifySchema(text, text), isEmpty);
    expect(
      requiredBump(
        classifySchema(text, text.replaceFirst('["walk","run"]', '["walk"]')),
      ),
      Bump.major,
    );
  });

  test('the VM scan reads each extension\'s keys, through the functions its '
      'parameters are handed to and a local helper\'s bound verbs', () {
    final package = _package(<String, String>{
      'src/a.dart': '''
import 'dart:developer' as developer;

void register() {
  developer.registerExtension('ext.p.go', (method, parameters) async {
    final step = parameters['step'];
    return answer(parameters);
  });

  void verb(String name, {required Object Function(Map<String, String>) ask}) {
    developer.registerExtension('ext.p.\$name', (method, parameters) async {
      final fresh = parameters['fresh'];
      return ask(parameters);
    });
  }

  verb('draws', ask: readDraws);
  verb('stats', ask: (p) => p['only'] ?? '');
}

void after() => postToolEvent('run.done', const <String, Object?>{});
''',
      'src/b.dart': '''
Object answer(Map<String, String> asked) => asked['why'] ?? '';
Object readDraws(Map<String, String> p) => p['limit'] ?? '';
''',
    });
    final surface = scanVm(package);
    // Mutation: stop following `parameters` into `answer`. `why` drops out,
    // and so does every key `level.apply` reads in `flutter3d_game`.
    expect(
      <String, Set<String>>{
        for (final MapEntry(:key, :value) in surface.extensions.entries)
          key: value.parameters.keys.toSet(),
      },
      <String, Set<String>>{
        'ext.p.go': <String>{'step', 'why'},
        'ext.p.draws': <String>{'fresh', 'limit'},
        'ext.p.stats': <String>{'fresh', 'only'},
      },
    );
    expect(surface.events, <String>{'flutter3d.run.done'});
  });

  test('the VM scan records how each parameter is parsed and the keys the '
      'answer carries', () {
    final package = _package(<String, String>{
      'a.dart': '''
import 'dart:convert';
import 'dart:developer' as developer;

void register() {
  registerFlutter3dExtension('ext.p.scrub', (method, parameters) async {
    final step = int.tryParse(parameters['step'] ?? '');
    final loud = parameters['loud'] == 'true';
    return developer.ServiceExtensionResponse.result(
      jsonEncode(step == null
          ? <String, Object?>{'found': false}
          : <String, Object?>{'found': true, 'step': step}),
    );
  });
}
''',
    });
    final scrub = scanVm(package).extensions['ext.p.scrub']!;
    // Mutation: record every parameter as a string. A handler that started
    // parsing `step` as a number would then look unchanged.
    expect(scrub.parameters, <String, String>{'step': 'int', 'loud': 'bool'});
    expect(scrub.result, <String>{'found', 'step'});
  });

  test('declared answers replace what the handler hides, and aliases are '
      'listed', () {
    final package = _package(<String, String>{
      'a.dart': '''
import 'dart:convert';
import 'dart:developer' as developer;

void register() {
  registerFlutter3dExtension(
    'ext.p.swap',
    (method, parameters) async =>
        developer.ServiceExtensionResponse.result(jsonEncode(report())),
    answers: const <String>{'models', 'refused'},
    aliases: const <String>['ext.p.hotSwap'],
  );
  void answer(String verb, {required Set<String> answers}) {
    registerFlutter3dExtension('ext.p.render.\$verb', (method, parameters) async {
      return developer.ServiceExtensionResponse.result(jsonEncode(ask()));
    }, answers: <String>{'frame', ...answers});
  }
  answer('stats', answers: const <String>{'width'});
}
''',
    });
    final surface = scanVm(package);
    // Mutation: ignore `answers:` and both read `*`, which is what every
    // answer built by a `toJson()` snapshotted as before.
    expect(surface.extensions['ext.p.swap']!.result, <String>{
      'models',
      'refused',
    });
    expect(surface.extensions['ext.p.swap']!.aliases, <String>[
      'ext.p.hotSwap',
    ]);
    expect(surface.extensions['ext.p.render.stats']!.result, <String>{
      'frame',
      'width',
    });
    expect(
      renderVm('p', surface),
      contains(
        'extension ext.p.swap\n  alias ext.p.hotSwap\n  -> models refused',
      ),
    );
  });

  test('an extension name built some other way is refused, not guessed', () {
    final package = _package(<String, String>{
      'a.dart': '''
import 'dart:developer' as developer;
void register(String name) =>
    developer.registerExtension('ext.p.\$name', (m, p) async => null);
''',
    });
    expect(() => scanVm(package), throwsStateError);
  });

  test('the first sentence stops at the first full stop that ends one', () {
    expect(firstSentence('Moves it. Then stops.'), 'Moves it.');
    expect(firstSentence('Reads 1.5 metres'), 'Reads 1.5 metres');
    expect(firstSentence('One line\nand another.'), 'One line');
  });
}
