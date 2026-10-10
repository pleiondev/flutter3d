/// The envelope's version: what a document says it is, and what is refused
/// — readiness review §2.2.7.
///
///     dart test test/formats_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

const FormatSpec _spec = FormatSpec(id: 'f3d.test', version: 3);

Map<String, Object?> _open(Map<String, Object?> document) =>
    _spec.open(document, refuse: DocumentFormatException.new);

void main() {
  test('a document without a version is the first version', () {
    expect(_spec.versionOf(const <String, Object?>{}), 1);
    expect(_spec.versionOf(const <String, Object?>{'version': 2}), 2);
    expect(() => _open(const <String, Object?>{}), returnsNormally);
  });

  test('version 0 and below are refused, not read as 1', () {
    // Mutation: clamp `versionOf` to 1 again (`said >= 1 ? … : 1`) and drop
    // the refusal in `open` — both documents open as version 1.
    for (final said in <int>[0, -1, -7]) {
      expect(_spec.versionOf(<String, Object?>{'version': said}), said);
      expect(
        () => _open(<String, Object?>{'format': 'f3d.test', 'version': said}),
        throwsA(
          isA<DocumentFormatException>().having(
            (DocumentFormatException e) => e.message,
            'message',
            contains('counts from 1'),
          ),
        ),
      );
    }
  });

  group('FormatSpecs', () {
    const level = FormatSpec(
      id: 'f3d.level',
      version: 4,
      suffixes: <String>['.level.json'],
    );
    const tape = FormatSpec(
      id: 'f3d.inputTape',
      version: 2,
      aliases: <String>['f3d.input-tape'],
      suffixes: <String>['.tape.json'],
    );
    const match = FormatSpec(
      id: 'f3d.match',
      version: 2,
      suffixes: <String>['.match.f3drun'],
    );
    const run = FormatSpec(
      id: 'f3d.run',
      version: 5,
      suffixes: <String>['.f3drun'],
    );

    test('finds a format by id, alias and the longest suffix', () {
      // Mutation: take the first suffix that matches instead of the longest,
      // and a strategy match is read as a run.
      final specs = FormatSpecs()
        ..add(level)
        ..addAll(<FormatSpec>[tape, run, match]);
      expect(specs.all, <FormatSpec>[level, tape, run, match]);
      expect(specs.byId('f3d.input-tape'), same(tape));
      expect(specs.byId('f3d.nothing'), isNull);
      expect(specs.forPath('levels/First.LEVEL.json'), same(level));
      expect(specs.forPath('runs/skirmish.match.f3drun'), same(match));
      expect(specs.forPath('runs/crypt.f3drun'), same(run));
      expect(specs.forPath('notes.json'), isNull);
    });

    test('a package adding its formats twice is one registration', () {
      final specs = FormatSpecs(<FormatSpec>[level, tape])
        ..addAll(<FormatSpec>[level, tape]);
      expect(specs.all, hasLength(2));
    });

    test('two formats under one id or alias are refused', () {
      // Mutation: let `add` overwrite, and the second package's reader
      // quietly takes the first one's files.
      final specs = FormatSpecs(<FormatSpec>[tape]);
      expect(
        () => specs.add(const FormatSpec(id: 'f3d.inputTape', version: 1)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('f3d.inputTape'),
          ),
        ),
      );
      expect(
        () => specs.add(const FormatSpec(id: 'f3d.input-tape', version: 1)),
        throwsArgumentError,
      );
    });
  });
}
