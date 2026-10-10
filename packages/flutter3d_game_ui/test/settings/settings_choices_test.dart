/// The choices a player makes in the settings panel, written where the
/// settings keep them: the colour roles, the colour vision, and the two
/// questions asked before anything of the player's leaves the device.
///
///     flutter test test/settings/settings_choices_test.dart
///
/// The widget halves of `color_roles_test.dart`,
/// `color_vision_setting_test.dart` and `consents_test.dart` in
/// `flutter3d_game`, which test the settings and the consents themselves.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_ui/settings.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  Future<String?> read(String name) async => documents[name];
  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

/// A store that only counts what is asked of it.
final class _Counted extends CloudSaveStore {
  final List<String> calls = <String>[];
  @override
  String get name => 'the test cloud';
  @override
  Future<CloudFetch> fetch(String slot) async {
    calls.add('fetch');
    return const CloudEmpty();
  }

  @override
  Future<CloudPut> put(
    String slot,
    String document, {
    String? replacing,
  }) async {
    calls.add('put');
    return const CloudStored(version: '1');
  }
}

/// Two marks a deutan cannot tell apart as the game has them: a red and a
/// green of nearly one lightness.
final ColorRoles _marks = ColorRoles(const <ColorRole>[
  ColorRole('enemy', 'Enemies', Color.fromARGB(255, 204, 64, 51)),
  ColorRole('friend', 'Friends', Color.fromARGB(255, 115, 140, 51)),
]);

void main() {
  ({Consents consents, _Counted store}) fresh() {
    final storage = _Storage();
    final store = _Counted();
    final sync = SaveSync(
      saves: SaveFile(appName: 'test', storage: storage),
      store: store,
    );
    return (
      consents: Consents(
        storage: storage,
        policy: '2026-10',
        sync: sync,
        now: () => DateTime.utc(2026, 10, 6),
      ),
      store: store,
    );
  }

  testWidgets('the panel asks both, off until turned on', (tester) async {
    final it = fresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrivacySection(consents: it.consents)),
      ),
    );
    Switch switchIn(String key) => tester.widget<Switch>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Switch),
      ),
    );
    expect(switchIn('privacy:cloud').value, isFalse);
    expect(switchIn('privacy:telemetry').value, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('privacy:telemetry')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    expect(switchIn('privacy:telemetry').value, isTrue);
    expect(it.consents.sendsRuns, isTrue);
    expect(it.consents.hasCloudConsent, isFalse);
  });

  testWidgets('two runs equally far along: the player picks one', (
    tester,
  ) async {
    bool? kept;
    final asked = SyncReport(
      SyncOutcome.ask,
      'This device and the cloud each have a run.',
      local: SaveRecord(
        level: 'assets/levels/crypt.json',
        run: const Snapshot(<String, Object?>{}),
        step: 600,
      ),
      remote: SaveRecord(
        level: 'assets/levels/deep.json',
        run: const Snapshot(<String, Object?>{}),
        step: 4200,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => kept = await askWhichRun(context, asked),
            child: const Text('sync'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sync'));
    await tester.pumpAndSettle();
    expect(find.text('On this device: crypt.json, 10s in'), findsOneWidget);
    expect(find.text('In the cloud: deep.json, 1m10s in'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('run:remote')));
    await tester.pumpAndSettle();
    expect(kept, isFalse);
  });

  testWidgets('before a run begins, the cloud is asked only after a yes', (
    tester,
  ) async {
    final it = fresh();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // No cloud, nothing to say.
    expect(await syncBeforeBegin(context, null), isNull);
    // Mutation: syncing whether or not the player said yes.
    expect(await syncBeforeBegin(context, it.consents.sync), isNotNull);
    expect(it.store.calls, isEmpty);
    await it.consents.answerCloud(granted: true);
    await syncBeforeBegin(context, it.consents.sync);
    expect(it.store.calls, contains('fetch'));
  });

  testWidgets('the panel lists the roles and writes the choice', (
    WidgetTester tester,
  ) async {
    final settings = GameSettingsController(
      settings: const GameSettings(),
      file: SettingsFile(appName: 'test', storage: MemoryStorage()),
      apply: (_) {},
    );
    Widget panel(ColorRoles? colors) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          settings: settings,
          sections: SettingsSection.standard(
            colors: colors,
            padConnected: false,
          ),
        ),
      ),
    );
    await tester.pumpWidget(panel(null));
    expect(find.text('Colours'), findsNothing);

    await tester.pumpWidget(panel(_marks));
    final swatch = find.byKey(const ValueKey<String>('colour:Friends:3'));
    await tester.scrollUntilVisible(swatch, 100);
    await tester.tap(swatch);
    expect(find.text('Enemies'), findsOne);
    expect(settings.settings.valueOf(GameSettingKeys.colorRole('friend')), 3);
  });

  testWidgets('the settings panel offers it, and writes the choice', (
    WidgetTester tester,
  ) async {
    final settings = GameSettingsController(
      settings: const GameSettings(),
      file: SettingsFile(appName: 'test', storage: MemoryStorage()),
      apply: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            settings: settings,
            sections: const <SettingsSection>[AccessibilitySection()],
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Deutan'), 100);
    await tester.tap(find.text('Deutan'));
    expect(settings.settings.valueOf(GameSettingKeys.colorVision), 2);
  });
}
