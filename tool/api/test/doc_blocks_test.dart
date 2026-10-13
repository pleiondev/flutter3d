import 'package:api_snapshot/doc_blocks.dart';
import 'package:test/test.dart';

void main() {
  const page = '''
# A page

```yaml
dependencies:
  flutter3d: ^1.0.0
  flutter3d_game: ^1.0.0
  http: ^1.2.0
```

```dart
final scene = Scene();
```

```dart
import 'package:flutter3d/flutter3d.dart';

class Spinner {
  void spin() {}
}
```

```dart
scene.add(Spinner());
```

```dart fragment
scene.add(...);
```
''';

  test('a page\'s blocks keep their imports, and a fragment says so', () {
    // Mutation: forget the imports an earlier block showed, and the third
    // block is analyzed with the fallback alone; read the fence's first word
    // only, and the fragment is checked like the rest.
    final blocks = docBlocksOf(
      page,
      fallback: <String>[
        "import 'package:flutter3d_game/flutter3d_game.dart';",
      ],
    );
    expect(blocks, hasLength(4));
    expect(blocks[0].line, 11);
    expect(blocks[0].imports, <String>[
      "import 'package:flutter3d_game/flutter3d_game.dart';",
    ]);
    expect(blocks[1].imports, <String>[
      "import 'package:flutter3d/flutter3d.dart';",
      "import 'package:flutter3d_game/flutter3d_game.dart';",
    ]);
    expect(blocks[1].source, isNot(contains('import ')));
    expect(blocks[2].imports, blocks[1].imports);
    expect(blocks[3].fragment, isTrue);
    expect(blocks.take(3).every((DocBlock b) => !b.fragment), isTrue);
  });

  test('the dependencies a page lists are the ones it is read with', () {
    expect(declaredDependencies(page), <String>[
      'flutter3d',
      'flutter3d_game',
      'http',
    ]);
    expect(declaredDependencies('no yaml here'), isEmpty);
  });

  test('a block is wrapped the way it parses best', () {
    // Mutation: always analyze a block as top-level code, and statements
    // read as syntax errors and their names are never resolved.
    String shape(String source) => snippetFor(
      DocBlock(
        line: 1,
        source: source,
        imports: const <String>[],
        fragment: false,
      ),
    ).source;
    expect(shape('class A {}\n'), isNot(contains('_snippet')));
    expect(shape('final a = 1;\nprint(a);\n'), contains('_snippet() async'));
    expect(
      shape('@override\nvoid run() {}\nstatic const size = 1;\n'),
      contains('abstract class _Snippet'),
    );
  });

  test('only what resolves wrong in our API is a finding', () {
    // Mutation: report every undefined name, and each variable an earlier
    // block of the page made fails the page; report none of the lowercase
    // ones, and a renamed top-level function slips through.
    final block = DocBlock(
      line: 40,
      source: '',
      imports: const <String>[],
      fragment: false,
    );
    const output = '''
ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|/x/b0001.dart|12|1|5|Undefined name 'scene'.
ERROR|COMPILE_TIME_ERROR|UNDEFINED_FUNCTION|/x/b0001.dart|13|1|5|The function 'lowerThing' isn't defined.
ERROR|COMPILE_TIME_ERROR|UNDEFINED_CLASS|/x/b0001.dart|14|1|5|Undefined class 'Spinner'.
ERROR|COMPILE_TIME_ERROR|UNDEFINED_CLASS|/x/b0001.dart|15|1|5|Undefined class 'Material'.
ERROR|COMPILE_TIME_ERROR|UNDEFINED_METHOD|/x/b0001.dart|16|1|5|The method 'go' isn't defined for the type '_Snippet'.
ERROR|COMPILE_TIME_ERROR|UNDEFINED_NAMED_PARAMETER|/x/b0001.dart|17|1|5|The named parameter 'size' isn't defined.
WARNING|STATIC_WARNING|UNUSED_IMPORT|/x/b0001.dart|1|1|5|Unused import.
ERROR|SYNTACTIC_ERROR|EXPECTED_TOKEN|/x/b0001.dart|18|1|5|Expected ';'.
''';
    final found = findingsIn(
      output,
      <String, DocSnippet>{
        '/x/b0001.dart': (block: block, doc: 'site/content/a.md', offset: 10),
      },
      apiFunctions: <String>{'lowerThing'},
      pageTypes: <String, Set<String>>{
        'site/content/a.md': <String>{'Spinner'},
      },
    );
    expect(found.map((DocFinding f) => f.code), <String>[
      'UNDEFINED_FUNCTION',
      'UNDEFINED_CLASS',
      'UNDEFINED_NAMED_PARAMETER',
    ]);
    expect(found.first.doc, 'site/content/a.md');
    expect(found.first.line, 42);
  });
}
