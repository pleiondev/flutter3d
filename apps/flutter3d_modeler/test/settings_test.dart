/// `ux-09`: the settings document, and the screen that edits it.
///
///     flutter test test/settings_test.dart
///
/// **The round trip is the point.** Seven rows of the usability plan each say
/// "a setting", and what every one of them actually needs is that the value a
/// person picked is the value the next launch reads — including when the
/// document on disk was written by a build that did not have that setting
/// yet, or by one that had a different spelling for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_modeler/main.dart' show ModelerScreen;
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage kept in a map, so a round trip can be driven without a disk.
final class FakeStorage implements Storage {
  final Map<String, String> documents = <String, String>{};
  bool refuse = false;

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    if (refuse) return false;
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

void main() {
  group('the document', () {
    test('a first launch is the defaults, not a failure', () {
      final store = SettingsStore(storage: FakeStorage());

      // Mutation: treat a missing document as an error and refuse to start.
      // A first launch is exactly the case there is nothing to read.
      expect(store.read(), const ModelerSettings());
      expect(store.read().workspace, Workspace.essential);
      expect(store.read().showHomeAtLaunch, isTrue);
      expect(store.read().quickSetupDone, isFalse);
    });

    test('every field survives a write and a read', () {
      final storage = FakeStorage();
      const chosen = ModelerSettings(
        navigation: NavigationScheme.leftDragOrbit,
        keymap: KeymapPreset.toolKeys,
        transformStart: TransformStart.modalOnPress,
        workspace: Workspace.full,
        language: 'ru',
        showHomeAtLaunch: false,
        saveWithHistory: false,
        quickSetupDone: true,
      );

      expect(SettingsStore(storage: storage).write(chosen), isTrue);

      // A second store over the same storage, which is what a restart is.
      // Mutation: write the enum's own `toString` and parse it back by name.
      // The document then changes meaning the day a member is renamed, and a
      // person's navigation scheme silently goes back to the default.
      expect(SettingsStore(storage: storage).read(), chosen);
    });

    test('a document that will not parse reads as the defaults', () {
      final storage = FakeStorage();
      storage.documents[SettingsStore.name] = 'not json at all';

      // Mutation: let the decode throw. One hand-edited file, one truncated
      // write, and the application will not start at all.
      expect(SettingsStore(storage: storage).read(), const ModelerSettings());
    });

    test('and one full of values this build does not know does too', () {
      final storage = FakeStorage();
      storage.documents[SettingsStore.name] =
          '{"navigation":"eye-tracking","keymap":7,'
          '"workspace":"everything","showHomeAtLaunch":"yes",'
          '"language":""}';

      final settings = SettingsStore(storage: storage).read();

      // Per field rather than all-or-nothing: a newer build's own value for
      // one setting should not throw away the six beside it.
      expect(settings.navigation, NavigationScheme.middleMouseOrbit);
      expect(settings.keymap, KeymapPreset.standard);
      expect(settings.workspace, Workspace.essential);
      expect(settings.showHomeAtLaunch, isTrue);
      // An empty string is not a language, and storing one would leave the
      // interface asking for a locale called "".
      expect(settings.language, isNull);
    });

    test('a write that fails says so rather than being swallowed', () {
      final storage = FakeStorage()..refuse = true;

      // Mutation: answer `true` regardless. The Settings screen then closes
      // on a preference that was never written, and the person finds out next
      // launch.
      expect(
        SettingsStore(storage: storage).write(const ModelerSettings()),
        isFalse,
      );
    });

    test('a language of null is left out rather than written as null', () {
      const settings = ModelerSettings();

      // "System" is the absence of a choice, and a document that spells it
      // `"language": null` is one where a later reader has to know that null
      // and missing mean the same thing.
      expect(settings.toJson().containsKey('language'), isFalse);
      expect(settings.copyWith(language: 'en').toJson()['language'], 'en');
      expect(
        settings
            .copyWith(language: 'en')
            .copyWith(clearLanguage: true)
            .language,
        isNull,
      );
    });
  });

  group('the screen', () {
    Future<ModelerSettings?> open(
      WidgetTester tester,
      ModelerSettings from,
    ) async {
      ModelerSettings? answer;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                if (!opened) {
                  opened = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    answer = await showSettingsScreen(context, from);
                  });
                }
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('Cancel answers with nothing at all', (
      WidgetTester tester,
    ) async {
      final answer = await open(tester, const ModelerSettings());

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Mutation: write on every change and close on Cancel with what is in
      // the draft. Backing out of a settings screen would then apply the very
      // change somebody was backing out of.
      expect(answer, isNull);
    });

    testWidgets('a changed dropdown reaches Save', (WidgetTester tester) async {
      await open(tester, const ModelerSettings());

      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Workspace.full.label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The dialog is gone and it did not throw on the way out; what it
      // answered is checked in the round-trip test above, through the store.
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('every control on the screen can be reached by keyboard', (
      WidgetTester tester,
    ) async {
      await open(tester, const ModelerSettings());

      // Five dropdowns, two switches, two buttons: `ux-09`'s own acceptance
      // asks that each is focusable rather than a tappable picture.
      // Mutation: build the choices as rows of `GestureDetector` chips. They
      // look identical and none of them takes focus.
      expect(find.byType(DropdownButtonFormField<NavigationScheme>), findsOne);
      expect(find.byType(DropdownButtonFormField<KeymapPreset>), findsOne);
      expect(find.byType(DropdownButtonFormField<TransformStart>), findsOne);
      expect(find.byType(DropdownButtonFormField<Workspace>), findsOne);
      expect(find.byType(DropdownButtonFormField<String>), findsOne);
      expect(find.byType(SwitchListTile), findsNWidgets(2));

      final focusable = tester
          .widgetList<Focus>(find.byType(Focus))
          .where((Focus it) => it.canRequestFocus)
          .length;
      expect(focusable, greaterThanOrEqualTo(7));
    });
  });

  group('in the application', () {
    // **`pump` with a duration, never `pumpAndSettle`.** The viewport asks
    // for a frame from inside its own frame, so the tree never goes quiet and
    // `pumpAndSettle` waits out its whole timeout — the same reason every
    // other whole-screen test in this application pumps by hand.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> launch(WidgetTester tester, FakeStorage storage) async {
      await tester.pumpWidget(
        MaterialApp(home: ModelerScreen(settingsStorage: storage)),
      );
      // Opening a device is genuine async work — the software-rasteriser
      // fallback a headless `flutter test` takes.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    testWidgets('a setting chosen on the screen survives a restart', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = FakeStorage();

      await launch(tester, storage);

      await tester.tap(find.byTooltip(_settingsTooltip));
      await settle(tester);
      await tester.tap(find.text('Workspace'));
      await settle(tester);
      await tester.tap(find.text(Workspace.full.label).last);
      await settle(tester);
      // The dialog's own Save: the top bar behind it has one too, and a
      // finder that matched both would be a test that cannot tell the
      // document being written from the settings being written.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Save'),
        ),
      );
      await settle(tester);

      // Mutation: hold the settings in the state and never write them, which
      // is what "a setting" meant before this row. The screen behaves
      // correctly for the rest of the session and forgets everything on quit.
      expect(SettingsStore(storage: storage).read().workspace, Workspace.full);

      // What a restart is: a second screen over the same storage.
      await launch(tester, storage);
      await tester.tap(find.byTooltip(_settingsTooltip));
      await settle(tester);

      expect(
        tester
            .widget<DropdownButtonFormField<Workspace>>(
              find.byType(DropdownButtonFormField<Workspace>),
            )
            .initialValue,
        Workspace.full,
      );
    });
  });
}

/// The top bar's own settings button, by the tooltip it carries.
const String _settingsTooltip =
    'Settings — navigation, keys, workspace, language';
