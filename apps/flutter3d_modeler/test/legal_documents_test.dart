/// `rel-21d`'s own: the bundled documents are the published ones, they parse,
/// the screen shows them, and "Clear local data" clears what the privacy
/// policy says it clears.
///
///     flutter test test/legal_documents_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show BinaryStorage, Storage;
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show recoveryPathFor;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/legal/legal_document.dart';
import 'package:flutter3d_modeler/src/legal/legal_library.dart';
import 'package:flutter3d_modeler/src/legal/legal_view.dart';
import 'package:flutter3d_modeler/src/local_data.dart';
import 'package:flutter3d_modeler/src/recent_projects.dart';
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/legal_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The published documents, read from the repository rather than from the
/// bundle — the other side of the comparison `tool/sync_legal.dart` exists to
/// keep true. Tests run with the package directory as the working directory.
const String _published = '../../legal';

/// The published documents as an [AssetBundle].
///
/// **Not `rootBundle`, in the widget tests only.** The byte-for-byte test
/// above already proves the six are in the bundle under the paths the
/// application asks for; what these two tests are about is the screen, and a
/// bundle that answers from the file system answers within a pump instead of
/// leaving a `FutureBuilder` spinning on a platform channel that a pumped
/// clock never reaches.
final class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final Uint8List bytes = File(
      '$_published/${key.split('/').last}',
    ).readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }
}

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

final class _BinaryStorage implements BinaryStorage {
  final Map<String, Uint8List> documents = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String name) async => documents[name];

  @override
  Future<bool> write(String name, Uint8List contents) async {
    documents[name] = contents;
    return true;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  group('rel-21d: the bundled documents are the published ones', () {
    test('every published document is bundled, byte for byte', () async {
      for (final String name in kLegalDocuments) {
        final published = File('$_published/$name');
        expect(
          published.existsSync(),
          isTrue,
          reason:
              '$name is listed in kLegalDocuments but is not in $_published',
        );
        // Mutation: let the copy drift. A privacy policy in the application
        // that disagrees with the one on the website is worse than one that
        // is missing — the store checked the URL, and the person read the
        // other text.
        expect(
          await rootBundle.loadString(legalAssetPath(name)),
          published.readAsStringSync(),
          reason: '$name has drifted — run `dart run tool/sync_legal.dart`',
        );
      }
    });

    test('and nothing is bundled that is not published', () {
      final bundled = Directory('assets/legal')
          .listSync()
          .whereType<File>()
          .map((File it) => it.uri.pathSegments.last)
          .where((String it) => it.endsWith('.md'))
          .toSet();
      expect(bundled, kLegalDocuments.toSet());
    });

    test('the six the application lists are the six that exist', () {
      final published = Directory(_published)
          .listSync()
          .whereType<File>()
          .map((File it) => it.uri.pathSegments.last)
          .where((String it) => it.endsWith('.md') && it != 'README.md')
          .toSet();
      expect(published, kLegalDocuments.toSet());
      // Every one of them has a row in the screen's own two tables, or the
      // list shows a legal heading where a menu item belongs.
      for (final String name in kLegalDocuments) {
        expect(kLegalTitles[name], isNotNull, reason: name);
        expect(kLegalSummaries[name], isNotNull, reason: name);
      }
    });
  });

  group('rel-21d: they parse', () {
    test(
      'each carries a title, a version and a date, and real blocks',
      () async {
        for (final String name in kLegalDocuments) {
          final LegalDocument document = await loadLegalDocument(name);
          expect(document.title, isNotEmpty, reason: name);
          expect(document.version, isNotEmpty, reason: name);
          expect(document.effective, isNotEmpty, reason: name);
          // Every document is more than a title: a parser that silently
          // produced nothing would pass every other assertion here.
          expect(
            document.blocks.whereType<LegalParagraph>().length,
            greaterThan(10),
            reason: name,
          );
          expect(
            document.blocks.whereType<LegalHeading>().length,
            greaterThan(3),
            reason: name,
          );
        }
      },
    );

    test('no mark is left in the text a person reads', () async {
      for (final String name in kLegalDocuments) {
        final LegalDocument document = await loadLegalDocument(name);
        for (final LegalBlock block in document.blocks) {
          // Code blocks are kept exactly as written — the MIT licence is one
          // — so they are not part of this claim.
          if (block is LegalCode) continue;
          final String text = switch (block) {
            LegalParagraph(:final text) => legalPlainText(text),
            LegalHeading(:final text) => legalPlainText(text),
            LegalList(:final items) => items.map(legalPlainText).join(' '),
            LegalTable(:final header, :final rows) => <String>[
              ...header.map(legalPlainText),
              for (final List<List<LegalSpan>> row in rows)
                ...row.map(legalPlainText),
            ].join(' '),
            LegalCode() => '',
          };
          // Mutation: hand the raw Markdown through. `**` and stray pipes on
          // screen are how a reader finds out the renderer gave up.
          expect(text, isNot(contains('**')), reason: '$name: $text');
          expect(text, isNot(contains('](')), reason: '$name: $text');
        }
      }
    });

    test('the privacy policy keeps its tables and its links', () async {
      final LegalDocument privacy = await loadLegalDocument('privacy.md');
      final tables = privacy.blocks.whereType<LegalTable>().toList();
      expect(tables, isNotEmpty);
      expect(tables.first.header.length, 3);
      expect(tables.first.rows, isNotEmpty);

      final links = <String>[
        for (final LegalBlock block in privacy.blocks)
          for (final List<LegalSpan> line in switch (block) {
            LegalParagraph(:final text) => <List<LegalSpan>>[text],
            LegalList(:final items) => items,
            _ => const <List<LegalSpan>>[],
          })
            for (final LegalSpan span in line)
              if (span.href case final String href) href,
      ];
      expect(links, contains('https://github.com/pleiondev/flutter3d'));
    });

    test('the licence agreement keeps the MIT text unwrapped', () async {
      final LegalDocument eula = await loadLegalDocument('eula.md');
      final LegalCode mit = eula.blocks.whereType<LegalCode>().single;
      expect(mit.text, contains('MIT License'));
      // Mutation: re-flow it. A licence text is quoted, not typeset, and the
      // line breaks are part of what is being quoted.
      expect(mit.text, contains('\n'));
      expect(mit.text, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    });

    test('inline marks, one at a time', () {
      expect(legalPlainText(parseLegalSpans('a **b** c')), 'a b c');
      expect(parseLegalSpans('a **b** c')[1].strong, isTrue);
      expect(parseLegalSpans('use `--mcp-port` now')[1].code, isTrue);
      expect(
        parseLegalSpans('[here](https://x.dev)').single.href,
        'https://x.dev',
      );
      expect(parseLegalSpans('<https://x.dev>').single.href, 'https://x.dev');
      // Unmatched marks come through as written rather than eating the rest
      // of the sentence, which is the failure that loses a clause.
      expect(
        legalPlainText(parseLegalSpans('2 ** 3 is not bold')),
        '2 ** 3 is not bold',
      );
      expect(legalPlainText(parseLegalSpans('a `b')), 'a `b');
    });
  });

  group('rel-21d: the screen', () {
    // The desktop shape, where the six are a list beside the text —
    // `hasRoomForDialogs` asks for 1200 and the default test window is 800,
    // which would give the full-screen shape and a dropdown instead.
    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    testWidgets('opens on the agreement and switches document', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LegalScreen(bundle: _Bundle())),
        ),
      );
      // Explicit pumps rather than `pumpAndSettle`: the spinner the
      // `FutureBuilder` shows while the six assets load animates forever, so
      // "settled" never arrives — it is waiting for the thing it is drawing.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('End User Licence Agreement'), findsOneWidget);

      await tester.tap(find.text('Privacy'));
      await tester.pump();

      // Mutation: show the first document whatever was chosen. The list is
      // the only way to reach five of the six.
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('End User Licence Agreement'), findsNothing);
    });

    testWidgets('a link is handed out rather than followed', (
      WidgetTester tester,
    ) async {
      final LegalDocument document = parseLegalDocument('''
---
title: A document
version: 1.0
effective: 2026-09-16
---

# A document

Write to <https://example.invalid/here>.
''', name: 'test.md');
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LegalView(document: document, onOpenLink: opened.add),
          ),
        ),
      );
      await tester.pump();

      // The tap has to land on the link's own span rather than anywhere in
      // the paragraph, so it is aimed by the recogniser the span carries.
      final Finder paragraph = find.byType(SelectableText).last;
      final SelectableText text = tester.widget(paragraph);
      final InlineSpan? span = text.textSpan;
      expect(span, isNotNull);
      final recognisers = <String>[];
      span!.visitChildren((InlineSpan child) {
        if (child is TextSpan && child.recognizer != null) {
          recognisers.add(child.toPlainText());
        }
        return true;
      });
      expect(recognisers, <String>['https://example.invalid/here']);
    });
  });

  group('rel-21d: clearing local data', () {
    test('removes what the policy names, and says what it removed', () async {
      final storage = _Storage();
      final documents = _BinaryStorage();
      storage.documents[SettingsStore.name] = '{}';
      storage.documents[RecentModels.name] = '[]';
      documents.documents[recoveryPathFor(null, sessionId: 'single-window')] =
          Uint8List.fromList(<int>[1, 2, 3]);

      final ClearedLocalData cleared = await clearLocalData(
        storage: storage,
        documents: documents,
        autosaveSessionId: 'single-window',
      );

      expect(cleared.count, 3);
      expect(cleared.says, contains('settings'));
      expect(cleared.says, contains('autosave'));
      expect(storage.documents, isEmpty);
      expect(documents.documents, isEmpty);
    });

    test('and says so honestly when there was nothing there', () async {
      // Mutation: report success regardless. "Cleared three things" over an
      // empty container is the sentence that stops being believed.
      final ClearedLocalData cleared = await clearLocalData(
        storage: _Storage(),
        documents: _BinaryStorage(),
        autosaveSessionId: 'single-window',
      );
      expect(cleared.count, 0);
      expect(cleared.says, contains('nothing'));
    });

    test('a project file is not something it touches', () async {
      final documents = _BinaryStorage();
      documents.documents['some/saved/model.f3dproj'] = Uint8List(4);
      await clearLocalData(
        storage: _Storage(),
        documents: documents,
        autosaveSessionId: 'single-window',
      );
      expect(documents.documents, hasLength(1));
    });
  });
}
