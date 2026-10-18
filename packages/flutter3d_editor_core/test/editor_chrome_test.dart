/// What a plugin adds to an editor's chrome through [EditorPieces]: menu
/// entries with their keys, toolbar buttons, and tool modes that take the
/// viewport's pointer while they are on.
///
///     dart test test/editor_chrome_test.dart
///
/// Against a plugin scope that keeps what it was handed, so a test switches
/// a plugin off the way the plugin host does. Each test names the mutation
/// that would defeat it.
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/editor.dart' show EditorCommandValue;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _Scope extends PluginScope {
  _Scope(String id)
    : manifest = PluginManifest(
        id: id,
        apiVersion: const PluginApiVersion(1, 0),
      );

  @override
  final PluginManifest manifest;

  @override
  int get rank => 0;

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

/// A plugin's command: sinks a boat by [depth] metres.
final class _Sink extends PluginCommand {
  const _Sink(this.depth);

  static _Sink? read(Map<String, Object?> arguments) =>
      switch (arguments['depth']) {
        final num depth => _Sink(depth.toDouble()),
        _ => null,
      };

  final double depth;

  @override
  String get name => 'boats.sink';

  @override
  String get says => 'sink by $depth';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'depth': depth};

  @override
  bool apply(Editing editing) => true;
}

/// A tool mode that sinks where it is pressed, and throws on a release.
final class _Plumb extends EditorToolMode {
  const _Plumb();

  @override
  String get label => 'Plumb';

  @override
  DocumentCommand? pressed(ToolModeInput input) => _Sink(input.point.y);

  @override
  DocumentCommand? released(ToolModeInput input) =>
      throw StateError('a plugin\'s mistake');

  @override
  List<GizmoMark> preview(ToolModeInput input) => <GizmoMark>[
    GizmoMark.ball(input.point, radius: 0.5),
  ];
}

Level _level() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'test',
    'brushes': <Object?>[],
    'lights': <Object?>[],
    'entities': <Object?>[],
  }),
  path: '/levels/test.json',
).level;

/// The pieces with the boats plugin's command added through its view.
({EditorPieces root, EditorPieces boats, _Scope scope}) _pieces() {
  final root = EditorPieces();
  final scope = _Scope('boats');
  final boats = root.forPlugin(scope)..addCommand('sink', _Sink.read);
  return (root: root, boats: boats, scope: scope);
}

void main() {
  group('a menu entry', () {
    test('is filed under the plugin, runs its command, and goes with it', () {
      // Mutation: file the entry as written. Two plugins' `sink` entries
      // would collide, and one the editor adds in a minor would take one.
      final (:root, :boats, :scope) = _pieces();
      boats.addMenuItem(
        EditorMenuItem(
          name: 'sink',
          label: 'Sink a little',
          command: 'sink',
          menu: 'Tools/Boats',
          arguments: const <String, Object?>{'depth': 0.5},
          shortcut: EditorShortcut.parse('ctrl+shift+k'),
        ),
      );
      final item = root.menuItems.single;
      expect(item.name, 'boats.sink');
      expect(item.command, 'boats.sink');
      expect(item.menu, 'Tools/Boats');
      final command = root.commandOf(item);
      expect(command, isA<_Sink>());
      expect((command! as _Sink).depth, 0.5);
      expect(
        root.menuItemFor(const EditorShortcut('k', control: true, shift: true)),
        same(item),
      );

      scope.switchOff();
      expect(root.menuItems, isEmpty);
    });

    test('runs one of the editor\'s own commands as it is named', () {
      // Mutation: publish every command name. `moveBy` would become
      // `boats.moveBy`, which nobody added.
      final (:root, :boats, scope: _) = _pieces();
      boats.addMenuItem(
        const EditorMenuItem(
          name: 'raise',
          label: 'Raise',
          command: 'moveBy',
          arguments: <String, Object?>{
            'by': <double>[0.0, 1.0, 0.0],
          },
        ),
      );
      expect(root.menuItems.single.command, 'moveBy');
      expect(root.menuItems.single.menu, EditorMenuItem.pluginsMenu);
    });

    test('naming a command nobody added, a taken name or a taken key is '
        'refused', () {
      // Mutation: take a second entry with the same key. The key would run
      // whichever the editor found first.
      final (:root, :boats, scope: _) = _pieces();
      expect(
        () => boats.addMenuItem(
          const EditorMenuItem(name: 'float', label: 'Float', command: 'float'),
        ),
        throwsA(isA<PluginException>()),
      );
      final key = EditorShortcut.parse('ctrl+k');
      boats.addMenuItem(
        EditorMenuItem(
          name: 'sink',
          label: 'Sink',
          command: 'sink',
          shortcut: key,
        ),
      );
      expect(
        () => boats.addMenuItem(
          const EditorMenuItem(name: 'sink', label: 'Again', command: 'sink'),
        ),
        throwsA(isA<NameTakenException>()),
      );
      expect(
        () => root.addMenuItem(
          EditorMenuItem(
            name: 'mine',
            label: 'Mine',
            command: 'moveBy',
            shortcut: key,
          ),
        ),
        throwsA(
          isA<NameTakenException>().having(
            (e) => e.message,
            'message',
            contains('boats.sink'),
          ),
        ),
      );
    });

    test('a shortcut is written and read in one form', () {
      // Mutation: accept a modifier twice, or one that is not a modifier,
      // or answer a misspelled shortcut with no key at all.
      expect(EditorShortcut.parse('Ctrl+Shift+F5').toString(), 'ctrl+shift+f5');
      expect(EditorShortcut.parse('k'), const EditorShortcut('k'));
      for (final written in <String>['ctrl+ctrl+k', 'hyper+k', 'ctrl+']) {
        expect(
          () => EditorShortcut.parse(written),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.invalidValue,
              'invalidValue',
              written,
            ),
          ),
          reason: written,
        );
      }
    });
  });

  group('a toolbar button', () {
    test('runs a command or switches a tool mode, both filed under the '
        'plugin', () {
      // Mutation: check the tool mode's name as written. A button of the
      // boats plugin naming `plumb` would find nobody's mode.
      final (:root, :boats, :scope) = _pieces();
      boats
        ..addToolMode('plumb', const _Plumb())
        ..addToolbarItem(
          const EditorToolbarItem.toolMode(
            name: 'plumb',
            label: 'Plumb',
            icon: 'straighten',
            toolMode: 'plumb',
          ),
        )
        ..addToolbarItem(
          const EditorToolbarItem.command(
            name: 'sink',
            label: 'Sink',
            command: 'sink',
            arguments: <String, Object?>{'depth': 1.0},
          ),
        );
      expect(root.toolbarItems.map((b) => b.name), <String>[
        'boats.plumb',
        'boats.sink',
      ]);
      expect(root.toolbarItems.first.toolMode, 'boats.plumb');
      expect(root.toolbarItems.last.command, 'boats.sink');
      expect(
        () => boats.addToolbarItem(
          const EditorToolbarItem.toolMode(
            name: 'measure',
            label: 'Measure',
            toolMode: 'measure',
          ),
        ),
        throwsA(isA<PluginException>()),
      );
      scope.switchOff();
      expect(root.toolbarItems, isEmpty);
      expect(root.toolModeNames, isEmpty);
    });
  });

  group('a tool mode', () {
    test('answers the pointer with a command, and a throw with nothing', () {
      // Mutation: let the mode's throw out. A plugin's mistake would take
      // the viewport with it.
      final (:root, :boats, scope: _) = _pieces();
      boats.addToolMode('plumb', const _Plumb());
      final mode = root.toolModeNamed('boats.plumb')!;
      final input = ToolModeInput(level: _level(), point: Vector3(1, 2, 3));
      final pressed = EditorPieces.askToolMode(
        mode,
        ToolModeEvent.press,
        input,
      );
      expect(pressed, isA<_Sink>());
      expect(
        EditorPieces.askToolMode(mode, ToolModeEvent.release, input),
        isNull,
      );
      expect(EditorPieces.askToolMode(mode, ToolModeEvent.drag, input), isNull);
      expect(EditorPieces.previewOf(mode, input).single.shape, GizmoShape.ball);
      expect(
        () => boats.addToolMode('plumb', const _Plumb()),
        throwsA(isA<NameTakenException>()),
      );
    });
  });

  test('every document command is a typed command value a panel can run', () {
    // Mutation: make DocumentCommand stand alone again. A panel would have
    // to spell a plugin's command as a map by hand.
    const EditorCommandValue command = _Sink(2.0);
    expect(command.toJson(), <String, Object?>{
      'command': 'boats.sink',
      'depth': 2.0,
    });
  });
}
