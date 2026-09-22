import 'package:flutter3d_showcase/src/docs/regions.dart';
import 'package:flutter_test/flutter_test.dart';

const String _source = '''
class A {
  void run() {
    // #region first  The first thing
    final a = 1;
    // #region inner
    final b = 2;
    // #endregion inner
    // #endregion first

    // #region second
    print(a);
    // #endregion second
  }
}
''';

void main() {
  group('extractRegion', () {
    test('quotes the lines of a region without any marker line', () {
      // Mutation: leave the marker lines in the quote, so the guide shows
      // `// #region` comments the reader never wrote.
      expect(extractRegion(_source, 'first'), 'final a = 1;\nfinal b = 2;');
    });

    test('takes the indentation the lines share off', () {
      expect(extractRegion(_source, 'second'), 'print(a);');
    });

    test('a nested region is quoted on its own', () {
      expect(extractRegion(_source, 'inner'), 'final b = 2;');
    });

    test('a region that is not there names the ones that are', () {
      expect(
        () => extractRegion(_source, 'third'),
        throwsA(
          isA<RegionError>().having(
            (RegionError e) => e.message,
            'message',
            allOf(contains('third'), contains('first'), contains('second')),
          ),
        ),
      );
    });
  });

  group('markers that do not pair', () {
    test('a region never closed is an error', () {
      expect(
        () => parseRegions('// #region a\nx\n'),
        throwsA(isA<RegionError>()),
      );
    });

    test('a close with nothing open is an error', () {
      expect(
        () => parseRegions('x\n// #endregion\n'),
        throwsA(isA<RegionError>()),
      );
    });

    test('a close naming another region is an error', () {
      expect(
        () => parseRegions('// #region a\n// #region b\n// #endregion a\n'),
        throwsA(isA<RegionError>()),
      );
    });

    test('the same name twice is an error', () {
      expect(
        () => parseRegions(
          '// #region a\n// #endregion a\n// #region a\n// #endregion a\n',
        ),
        throwsA(isA<RegionError>()),
      );
    });
  });

  test('listRegions gives the names in the order they open', () {
    expect(listRegions(_source), <String>['first', 'inner', 'second']);
  });

  test('stripMarkers removes only the marker lines', () {
    final String stripped = stripMarkers(_source);
    expect(stripped, isNot(contains('#region')));
    expect(stripped, contains('final b = 2;'));
  });

  test('strippedLineOf counts lines with the markers taken out', () {
    // `final a = 1;` is the third line of the stripped file.
    expect(strippedLineOf(_source, 'first'), 2);
  });

  group('expandDirectives', () {
    test('replaces a {{code}} line with a fenced block of the region', () {
      final String out = expandDirectives(
        'Intro\n{{code second}}\nOutro',
        own: _source,
      );
      expect(out, 'Intro\n```dart\nprint(a);\n```\nOutro');
    });

    test('{{source}} quotes the whole file without markers', () {
      final String out = expandDirectives('{{source}}', own: _source);
      expect(out, startsWith('```dart\nclass A {'));
      expect(out, isNot(contains('#region')));
    });

    test('{{code other#region}} reads another page', () {
      final String out = expandDirectives(
        '{{code other#inner}}',
        own: '',
        sourceOf: (String id) => id == 'other' ? _source : '',
      );
      expect(out, contains('final b = 2;'));
    });

    test('leaves {{demo}} and {{shot}} for the caller', () {
      expect(
        expandDirectives('{{demo}}\n{{shot}}', own: ''),
        '{{demo}}\n{{shot}}',
      );
    });

    test('a pointer at nothing stops rather than showing an empty block', () {
      expect(
        () => expandDirectives('{{code nope}}', own: _source),
        throwsA(isA<RegionError>()),
      );
    });
  });
}
