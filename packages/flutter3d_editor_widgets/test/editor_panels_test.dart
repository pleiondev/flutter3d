/// What a plugin docks into an editor: [EditorPanels], its panels published
/// under the plugin's id, and the [EditorPanelContext] they are built with.
///
///     flutter test test/editor_panels_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

EditorPanel _tide({DockSide? dock = DockSide.right}) => EditorPanel(
  id: 'tide',
  title: 'Tide',
  dock: dock,
  builder: (EditorPanelContext panel) => TextButton(
    onPressed: () => panel.run(<String, Object?>{'command': 'boats.sink'}),
    child: Text('${panel.selection.length} selected in ${panel.path}'),
  ),
);

void main() {
  test('a plugin\'s panel is published under its namespace and withdrawn '
      'with it', () {
    final panels = EditorPanels();
    var heard = 0;
    panels.listen(() => heard++);
    final scope = _Scope('boats.editor', 0);
    panels.forPlugin(scope).addPanel(_tide());
    // Mutation: publish the id as written, or under the whole plugin id
    // (`boats.editor.tide`), a namespace of its own beside the package's.
    expect(panels.panels.single.id, 'boats.tide');
    expect(heard, 1);
    // Mutation: refuse a dotted id with an ArgumentError, or take it as
    // given. Another package's panel is refused as its other names are.
    expect(
      () => panels
          .forPlugin(_Scope('ships', 1))
          .addPanel(
            EditorPanel(
              id: 'boats.tide',
              title: 'Tide',
              builder: (EditorPanelContext panel) => const SizedBox(),
            ),
          ),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          contains('the panel "boats.tide"'),
        ),
      ),
    );
    // The same package's runtime half, naming the panel whole, meets the
    // one already there.
    expect(
      () => panels
          .forPlugin(_Scope('boats', 1))
          .addPanel(
            EditorPanel(
              id: 'boats.tide',
              title: 'Tide',
              builder: (EditorPanelContext panel) => const SizedBox(),
            ),
          ),
      throwsArgumentError,
    );
    for (final registration in scope.registrations) {
      registration.cancel();
    }
    expect(panels.panels, isEmpty);
    expect(heard, 2);
  });

  test('a docked panel and a main-screen panel are told apart', () {
    final panels = EditorPanels()
      ..addPanel(_tide())
      ..addPanel(
        EditorPanel(
          id: 'chart',
          title: 'Chart',
          builder: (EditorPanelContext panel) => const SizedBox(),
        ),
      );
    // Mutation: dock a panel with no side to the right.
    expect(panels.docked.map((p) => p.id), <String>['tide']);
    expect(panels.mainScreen.map((p) => p.id), <String>['chart']);
  });

  testWidgets('a docked panel is built with the editor\'s context', (
    WidgetTester tester,
  ) async {
    final ran = <Map<String, Object?>>[];
    final panels = EditorPanels()..addPanel(_tide());
    final docked = panels.dockPanels(
      (BuildContext context) => EditorPanelContext(
        context: context,
        path: 'levels/one.json',
        document: const <String, Object?>{'entities': <Object?>[]},
        selection: const <PanelSelection>[
          PanelSelection(piece: 'entity', index: 0),
        ],
        run: (Map<String, Object?> command) {
          ran.add(command);
          return true;
        },
      ),
    );
    // Mutation: hand `DockLayout` the plugin's builder unwrapped.
    expect(docked.single.side, DockSide.right);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: docked.single.builder)),
      ),
    );
    expect(find.text('1 selected in levels/one.json'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(ran.single['command'], 'boats.sink');
  });

  testWidgets('a panel that throws shows why, not a red screen', (
    WidgetTester tester,
  ) async {
    final panels = EditorPanels()
      ..forPlugin(_Scope('boats', 0)).addPanel(
        EditorPanel(
          id: 'broken',
          title: 'Broken',
          dock: DockSide.left,
          builder: (EditorPanelContext panel) => throw StateError('no tide'),
        ),
      );
    final docked = panels.dockPanels(
      (BuildContext context) => EditorPanelContext(
        context: context,
        document: const <String, Object?>{},
        run: (Map<String, Object?> command) => false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: docked.single.builder)),
      ),
    );
    // Mutation: call the builder without a guard.
    expect(find.textContaining('no tide'), findsOneWidget);
  });
}
