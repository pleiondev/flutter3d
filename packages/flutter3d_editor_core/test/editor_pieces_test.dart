/// What a plugin brings to the editor: commands, inspector components and
/// palette entries, through [EditorPieces].
///
///     dart test test/editor_pieces_test.dart
///
/// Against a plugin scope that keeps what it was handed, so a test cancels a
/// plugin's registrations the way the plugin host does when it switches one
/// off. Each test was written by breaking what it covers; the mutation is
/// named.
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A plugin as the host sees it: a manifest, a place in the install order,
/// and the registrations to cancel when it is switched off.
final class _Scope extends PluginScope {
  _Scope(String id, this.rank)
    : manifest = PluginManifest(
        id: id,
        apiVersion: const PluginApiVersion(1, 0),
      );

  @override
  final PluginManifest manifest;

  @override
  int rank;

  final List<Registration> registrations = <Registration>[];

  @override
  void track(Registration registration) => registrations.add(registration);

  void switchOff() {
    for (final registration in registrations.reversed) {
      registration.cancel();
    }
    registrations.clear();
  }
}

/// A plugin's command: lifts the selection by [by] metres.
final class _Lift extends PluginCommand {
  const _Lift(this.by);

  static _Lift? read(Map<String, Object?> arguments) =>
      switch (arguments['by']) {
        final num by => _Lift(by.toDouble()),
        _ => null,
      };

  final double by;

  @override
  String get name => 'boats.lift';

  @override
  String get says => 'lift by $by';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'by': by};

  @override
  bool apply(Editing editing) {
    if (editing.where == null) return false;
    editing.nudgeAll(Vector3(0.0, by, 0.0));
    return true;
  }
}

Editing _open() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'test',
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, 0.0, 0.0],
        'size': <double>[2.0, 2.0, 2.0],
        'material': 'stone',
      },
    ],
    'lights': <Object?>[],
    'entities': <Object?>[
      <String, Object?>{
        'type': 'boat',
        'at': <double>[1.0, 0.0, 0.0],
      },
    ],
  }),
  path: '/levels/test.json',
);

const EditorComponent _buoyancy = EditorComponent(
  kind: 'buoyancy',
  title: 'Buoyancy',
  defaults: <String, Object?>{'buoyancy': 1.0, 'drag': 0.4},
  types: <String>{'boat'},
);

/// Sections equal to [expected], title by title and key by key. A record
/// that holds a `List` compares it by identity, so the records are taken
/// apart before `equals` sees them.
Matcher _sections(List<(String, List<String>)> expected) {
  List<Object> flat(List<(String, List<String>)> sections) => <Object>[
    for (final (title, keys) in sections) <Object>[title, keys],
  ];
  return isA<List<(String, List<String>)>>().having(
    flat,
    'sections',
    flat(expected),
  );
}

void main() {
  group('commands', () {
    test('a plugin command is read back by name and runs as a step', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addCommand('lift', _Lift.read);
      final editing = _open()
        ..kind = Piece.brush
        ..selected = 0;

      final command = pieces.readCommand(<String, Object?>{
        'command': 'boats.lift',
        'by': 1.0,
      });
      // Mutation: hand the reader the whole map, `command` included. The
      // reader still works here, so the next line is what holds it: the
      // arguments the command writes back are its own and nothing else.
      expect(command, isA<_Lift>());
      expect(command!.toJson(), <String, Object?>{
        'command': 'boats.lift',
        'by': 1.0,
      });
      // Mutation: keep `EditorHistory.run` taking an `EditorCommand`. This
      // does not compile.
      expect(editing.history.run(command), isTrue);
      expect(editing.level.brushes.single.center.y, 1.0);
      expect(editing.history.undoSays, 'lift by 1.0');
    });

    test('the editor\'s own commands still read through the same door', () {
      final pieces = EditorPieces();
      // Mutation: look plugin readers up first and fall through to the
      // built-ins only when none matches. The answer is the same here; the
      // refusal below is what catches a plugin shadowing `moveBy`.
      expect(
        pieces.readCommand(<String, Object?>{
          'command': 'moveBy',
          'by': <double>[1.0, 0.0, 0.0],
        }),
        isA<MoveSelectionBy>(),
      );
      expect(pieces.readCommand(<String, Object?>{'command': 'fly'}), isNull);
      expect(pieces.commandNames, editorCommandNames);
    });

    test('a name taken is refused, naming who took it', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addCommand('lift', _Lift.read);
      // Mutation: drop the check against `editorCommandNames`. A plugin could
      // then register `moveBy`, and the editor's own would answer anyway.
      expect(
        () => pieces.addCommand('moveBy', _Lift.read),
        throwsA(isA<ArgumentError>()),
      );
      // Mutation: drop the duplicate check. Two readers for one name, and
      // whichever was added first answers for both. Another plugin's `lift`
      // is its own (`cranes.lift`), so the clash is a second plugin under
      // the id `boats`.
      expect(
        () =>
            pieces.forPlugin(_Scope('boats', 1)).addCommand('lift', _Lift.read),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('plugin "boats"'),
          ),
        ),
      );
    });

    test('switching the plugin off withdraws its command', () {
      final pieces = EditorPieces();
      final boats = _Scope('boats', 0);
      pieces.forPlugin(boats).addCommand('lift', _Lift.read);
      expect(pieces.commandNames, contains('boats.lift'));
      // Mutation: skip `scope.track` in the store. Nothing is cancelled, and
      // the command outlives its plugin.
      boats.switchOff();
      expect(pieces.commandNames, isNot(contains('boats.lift')));
      expect(
        pieces.readCommand(<String, Object?>{
          'command': 'boats.lift',
          'by': 1.0,
        }),
        isNull,
      );
    });
  });

  group('components', () {
    test('a plugin component is a section before the catch-all', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addComponent(_buoyancy);
      // Mutation: append plugin components after the editor's last one. The
      // catch-all "Properties" would then come before "Buoyancy", and take
      // `buoyancy` for itself.
      expect(
        inspectorSections(
          Piece.entity,
          <String>['type', 'at', 'buoyancy', 'colour'],
          type: 'boat',
          pieces: pieces,
        ),
        _sections(<(String, List<String>)>[
          ('Entity', <String>['type']),
          ('Transform', <String>['at']),
          ('Buoyancy', <String>['buoyancy']),
          ('Properties', <String>['colour']),
        ]),
      );
    });

    test('a component for boats is not shown on a torch', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addComponent(_buoyancy);
      // Mutation: ignore `types` in `appliesTo`. Every entity grows a
      // buoyancy section and is offered a drag it has no use for.
      expect(
        inspectorSections(
          Piece.entity,
          <String>['type', 'buoyancy'],
          type: 'torch',
          pieces: pieces,
        ),
        _sections(<(String, List<String>)>[
          ('Entity', <String>['type']),
          ('Properties', <String>['buoyancy']),
        ]),
      );
      expect(
        pieces.offersFor(Piece.entity, <String>['type'], 'torch'),
        isEmpty,
      );
      // Mutation: offer every default, set or not. `buoyancy` is set here and
      // must not be offered again under "not set".
      expect(
        pieces.offersFor(Piece.entity, <String>['type', 'buoyancy'], 'boat'),
        <String, Object?>{'drag': 0.4},
      );
    });

    test('the editor\'s own sections are unchanged without plugins', () {
      // Mutation: drop a key from `builtInComponents`' brush collision. The
      // key would land under "Other", which is what the panel showed before
      // the sections moved here only for keys nobody names.
      expect(
        inspectorSections(Piece.brush, <String>[
          'at',
          'solid',
          'material',
          'rain',
        ]),
        _sections(<(String, List<String>)>[
          ('Transform', <String>['at']),
          ('Rendering', <String>['material']),
          ('Collision', <String>['solid']),
          ('Other', <String>['rain']),
        ]),
      );
    });

    test('a kind is unique, and the editor\'s own are taken', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addComponent(_buoyancy);
      // Mutation: drop the built-in check. A plugin could add a second
      // "brush.collision", and two sections would claim the same keys.
      expect(
        () => pieces.addComponent(
          const EditorComponent(kind: 'brush.collision', title: 'Collision'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      // Mutation: drop the duplicate check, and two sections are
      // `boats.buoyancy`. A plugin under another id has its own kind.
      expect(
        () => pieces.forPlugin(_Scope('boats', 1)).addComponent(_buoyancy),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('plugin "boats"'),
          ),
        ),
      );
    });

    test('components come back by install order, not by when they arrived', () {
      final pieces = EditorPieces();
      final second = _Scope('second', 1);
      final first = _Scope('first', 0);
      pieces
          .forPlugin(second)
          .addComponent(const EditorComponent(kind: 'b', title: 'B'));
      pieces
          .forPlugin(first)
          .addComponent(const EditorComponent(kind: 'a', title: 'A'));
      pieces.addComponent(const EditorComponent(kind: 'app', title: 'App'));
      // Mutation: sort by sequence alone. "B" would come first, because it
      // was added first, though its plugin installs after "A"'s.
      expect(
        <String>[for (final c in pieces.components) c.kind],
        <String>['app', 'first.a', 'second.b'],
      );
      // Mutation: read the rank when added rather than when sorting. A
      // reorder of the plugins would not reorder what they brought.
      second.rank = -2;
      expect(
        <String>[for (final c in pieces.components) c.kind],
        <String>['second.b', 'app', 'first.a'],
      );
    });
  });

  test('a plugin\'s pieces are published under its id, so a later '
      'built-in of the same name cannot collide', () {
    final pieces = EditorPieces();
    // Mutation: register a plugin's command under its bare name. A command
    // the editor adds in a minor release would then refuse the plugin.
    pieces.forPlugin(_Scope('boats', 0)).addCommand('lift', _Lift.read);
    pieces.forPlugin(_Scope('cranes', 1)).addCommand('lift', _Lift.read);
    expect(
      pieces.commandNames,
      containsAll(<String>['boats.lift', 'cranes.lift']),
    );
    expect(
      () => pieces.forPlugin(_Scope('boats', 0)).addCommand('a.b', _Lift.read),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('palette', () {
    test('a plugin entry is a row whether the level has one or not', () {
      final pieces = EditorPieces();
      final boats = _Scope('boats', 0);
      pieces
          .forPlugin(boats)
          .addPaletteEntry(
            PaletteEntry(
              'raft',
              label: 'Raft',
              tint: Vector3(0.2, 0.4, 0.8),
              properties: const <String, Object?>{'buoyancy': 2.0},
            ),
          );
      final editing = _open();
      // Mutation: leave `pieces` out of `paletteOf`'s counts. A level with no
      // raft has no raft row, which is the case an entry exists for.
      final raft = paletteOf(
        editing.level,
        pieces: pieces,
      ).singleWhere((Placeable it) => it.what == 'raft');
      expect(raft.count, 0);
      expect(raft.label, 'Raft');
      // `Vector3` is float32, so 0.8 comes back to float32's precision.
      expect(raft.tint.z, closeTo(0.8, 1e-7));

      // Mutation: drop `it.properties` from `Editing.place`. The raft lands
      // with no buoyancy, and the plugin's defaults reach nothing.
      editing.place(raft, Vector3(2.0, 0.0, 0.0));
      expect(editing.level.entities.last.type, 'raft');
      expect(editing.level.entities.last.properties['buoyancy'], 2.0);

      // Switched off, a level with no raft in it offers none: the row came
      // from the plugin, and went with it.
      boats.switchOff();
      expect(pieces.paletteEntries, isEmpty);
      expect(
        paletteOf(_open().level, pieces: pieces).map((Placeable p) => p.what),
        isNot(contains('raft')),
      );
    });

    test('a type offered twice is refused, naming who offered it', () {
      final pieces = EditorPieces();
      pieces
          .forPlugin(_Scope('boats', 0))
          .addPaletteEntry(const PaletteEntry('raft'));
      // Mutation: drop the check. Two rows for one type, one of them dead.
      expect(
        () => pieces.addPaletteEntry(const PaletteEntry('raft')),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('plugin "boats"'),
          ),
        ),
      );
    });
  });

  test('the slot is filled by this type, scoped per plugin', () {
    final pieces = EditorPieces();
    // Mutation: return a plain `EditorRegistry` from `forPlugin`. The plugin
    // host refuses it, since a registry must return the type it is looked up
    // by.
    expect(pieces, isA<EditorRegistry>());
    expect(pieces.forPlugin(_Scope('boats', 0)), isA<EditorPieces>());
  });
}
