import 'package:flutter3d_showcase/src/docs/tutorial.dart';
import 'package:flutter_test/flutter_test.dart';

const String _good = '''
# A guide

Some words with **bold**, *italic*, `code` and a [link](https://example.com).

## Step 1: One
{{code a}}

## Step 2: Two
{{code b}}

## Step 3: Three
{{code c}}
''';

void main() {
  group('parseTutorial', () {
    test('reads headings, paragraphs, lists and code into blocks', () {
      final List<Block> blocks = parseTutorial(
        '# T\n\nHello there.\n\n- one\n- two\n\n1. a\n2. b\n\n```dart\nvar x;\n```\n',
      );
      expect(
        blocks[0],
        isA<Heading>().having((Heading h) => h.level, 'level', 1),
      );
      expect(blocks[1], isA<Paragraph>());
      expect(
        blocks[2],
        isA<ListBlock>().having((ListBlock l) => l.items.length, 'items', 2),
      );
      expect(
        blocks[3],
        isA<ListBlock>().having((ListBlock l) => l.ordered, 'ordered', isTrue),
      );
      expect(
        blocks[4],
        isA<CodeBlock>().having((CodeBlock c) => c.code, 'code', 'var x;'),
      );
    });

    test('a > block with a leading **Warning** is a warning callout', () {
      final Block block = parseTutorial('> **Warning.** Careful.').single;
      expect(
        block,
        isA<Callout>().having((Callout c) => c.kind, 'kind', 'warning'),
      );
    });

    test('inline runs keep their kind', () {
      final List<Inline> runs = parseInlines('a **b** `c` *d* [e](u)');
      expect(runs.map((Inline r) => r.runtimeType), <Type>[
        Plain,
        Bold,
        Plain,
        CodeSpan,
        Plain,
        Italic,
        Plain,
        Link,
      ]);
    });

    test('{{demo}} and {{shot}} become directive blocks', () {
      expect(
        parseTutorial(
          '{{demo}}\n\n{{shot}}',
        ).map((Block b) => (b as DirectiveBlock).name),
        <String>['demo', 'shot'],
      );
    });
  });

  group('lintTutorial', () {
    test('a guide with a title and three coded steps passes', () {
      expect(lintTutorial(_good), isEmpty);
    });

    test('refuses a table, an image and raw HTML', () {
      // Mutation: drop the table check. The app has no table widget and would
      // show the pipes as text while the site drew a table.
      final List<String> problems = lintTutorial(
        '$_good\n| a | b |\n![x](y.png)\n<div>hi</div>\n',
      );
      expect(problems.where((String p) => p.contains('table')), isNotEmpty);
      expect(problems.where((String p) => p.contains('image')), isNotEmpty);
      expect(problems.where((String p) => p.contains('HTML')), isNotEmpty);
    });

    test('HTML inside backticks is not HTML', () {
      expect(lintTutorial('$_good\nUse `<div>` sparingly.\n'), isEmpty);
    });

    test('fewer than three steps is refused', () {
      expect(
        lintTutorial('# T\n\n## Step 1: A\n{{code a}}\n'),
        contains(contains('at least three')),
      );
    });

    test('steps must be numbered from 1 without a gap', () {
      expect(
        lintTutorial(
          '# T\n## Step 1: A\n{{code a}}\n## Step 3: C\n{{code c}}\n## Step 4: D\n{{code d}}\n',
        ),
        contains(contains('numbered')),
      );
    });

    test('a step that quotes no code is refused', () {
      expect(
        lintTutorial(
          '# T\n## Step 1: A\n{{code a}}\n## Step 2: B\nwords\n## Step 3: C\n{{code c}}\n',
        ),
        contains(contains('Step 2 quotes no code')),
      );
    });

    test('the first line has to be the title', () {
      expect(lintTutorial('words\n$_good'), contains(contains('Title')));
    });
  });

  test('stepsOf lists the step numbers', () {
    expect(stepsOf(_good), <int>[1, 2, 3]);
  });
}
