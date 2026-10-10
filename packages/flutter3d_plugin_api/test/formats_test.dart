/// The format envelope and the registry that knows the formats.
///
///     dart test test/formats_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

const FormatSpec _level = FormatSpec(
  id: 'f3d.level',
  version: 2,
  suffixes: <String>['.level.json'],
  fixture: 'test/fixtures/v<N>/first.level.json',
  aliases: <String>['flutter3d.level'],
);

final class _Scope extends PluginScope {
  _Scope(String id)
    : manifest = PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  final PluginManifest manifest;

  @override
  int get rank => 0;

  final List<Registration> tracked = <Registration>[];

  @override
  void track(Registration registration) => tracked.add(registration);
}

void main() {
  group('the envelope', () {
    test('an older document is lifted, a newer one refused naming both', () {
      final lifted = _level.open(<String, Object?>{
        'version': 1,
        'name': 'first',
      }, refuse: DocumentFormatException.new);
      expect(lifted['name'], 'first');

      // Mutation: drop the upper bound and the newer document is read.
      expect(
        () => _level.open(<String, Object?>{
          'format': 'f3d.level',
          'version': 3,
        }, refuse: DocumentFormatException.new),
        throwsA(
          isA<DocumentFormatException>().having(
            (DocumentFormatException e) => e.message,
            'message',
            allOf(contains('3'), contains('2')),
          ),
        ),
      );
      expect(
        () => _level.open(<String, Object?>{
          'format': 'f3d.save',
        }, refuse: DocumentFormatException.new),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('a JSON format is enveloped unless it says otherwise', () {
      expect(_level.enveloped, isTrue);
      const model = FormatSpec(
        id: 'f3d.model',
        version: 1,
        enveloped: false,
        magic: <int>[0x46, 0x33, 0x44, 0x0A],
      );
      expect(model.enveloped, isFalse);
      expect(
        FormatRegistry(<FormatSpec>[
          model,
        ]).sniff(<int>[0x46, 0x33, 0x44, 0x0A]),
        model,
      );
    });
  });

  group('the registry', () {
    test('a clash is a FormatRegistrationException, a PluginException', () {
      final registry = FormatRegistry(<FormatSpec>[_level]);

      // Mutation: throw a StateError again, and a plugin manager reporting
      // install failures as PluginExceptions misses this one.
      expect(
        () => registry.add(
          const FormatSpec(
            id: 'f3d.other',
            version: 1,
            aliases: <String>['flutter3d.level'],
          ),
        ),
        throwsA(isA<FormatRegistrationException>()),
      );
      expect(
        () => registry.add(
          const FormatSpec(
            id: 'f3d.other',
            version: 1,
            suffixes: <String>['.level.json'],
          ),
        ),
        throwsA(isA<PluginException>()),
      );
      expect(registry.byId('flutter3d.level'), _level);
    });

    test('a plugin\'s id and its aliases stay in its namespace', () {
      final registry = FormatRegistry();
      final scope = _Scope('trails');
      final view = registry.forPlugin(scope);

      view.add(
        const FormatSpec(
          id: 'trails.path',
          version: 1,
          fixture: 'test/fixtures/v<N>/one.path.json',
          aliases: <String>['trails.route'],
        ),
      );
      expect(registry.byId('trails.route')?.id, 'trails.path');
      expect(scope.tracked, hasLength(1));

      // Mutation: check only the id. A plugin would claim `f3d.path` through
      // an alias, a name the engine may want in a later minor.
      expect(
        () => view.add(
          const FormatSpec(
            id: 'trails.other',
            version: 1,
            fixture: 'test/fixtures/v<N>/other.json',
            aliases: <String>['f3d.path'],
          ),
        ),
        throwsA(
          isA<FormatRegistrationException>().having(
            (FormatRegistrationException e) => e.message,
            'message',
            contains('"f3d.path"'),
          ),
        ),
      );
      expect(registry.byId('f3d.path'), isNull);
    });
  });
}
