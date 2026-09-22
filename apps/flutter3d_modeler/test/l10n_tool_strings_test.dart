/// `ux-22`: the rail's own forty-five tools, in both languages.
///
///     flutter test test/l10n_tool_strings_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/l10n/app_localizations_en.dart';
import 'package:flutter3d_modeler/l10n/app_localizations_ru.dart';
import 'package:flutter3d_modeler/src/ui/tool_strings.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every tool the rail offers, in every mode and sub-mode.
List<ModelerTool> _everyTool() {
  final seen = <String>{};
  final all = <ModelerTool>[];
  for (final ModelerMode mode in ModelerMode.values) {
    if (!mode.ready) continue;
    for (final AnimationSubmode submode in AnimationSubmode.values) {
      for (final ModelerTool tool in toolsFor(mode, animation: submode)) {
        if (seen.add(tool.id)) all.add(tool);
      }
    }
  }
  return all;
}

/// The message keys of one ARB file.
Set<String> _keys(String name) {
  final Map<String, Object?> json =
      jsonDecode(File('lib/l10n/$name').readAsStringSync())
          as Map<String, Object?>;
  return <String>{
    for (final String key in json.keys)
      if (!key.startsWith('@')) key,
  };
}

void main() {
  test('every tool has a name and a sentence in both files', () {
    final Set<String> ru = _keys('app_ru.arb');
    final Set<String> en = _keys('app_en.arb');
    final AppLocalizations english = AppLocalizationsEn();
    final AppLocalizations russian = AppLocalizationsRu();

    final untranslated = <String>[];
    for (final ModelerTool tool in _everyTool()) {
      // **Mutation: fall back to `tool.label` and call it done.** Every
      // tool then reads in English under a Russian interface and nothing
      // says so — which is the state `ui-22` left, with about a quarter of
      // the strings moved and the rail not among them.
      if (toolLabel(russian, tool) == tool.label &&
          toolLabel(english, tool) == tool.label &&
          tool.label.isNotEmpty) {
        // A label that is the same word in both languages is possible;
        // one that is the same *because nothing was written* is not, and
        // the ARB is where the difference shows.
        untranslated.add(tool.id);
      }
      expect(toolAbout(russian, tool), isNotEmpty, reason: tool.id);
    }
    expect(untranslated, isEmpty);
    expect(ru, en, reason: 'the two files name different keys');
  });

  testWidgets('the rail reads the language the app is in', (
    WidgetTester tester,
  ) async {
    final ModelerTool extrude = _everyTool().firstWhere(
      (ModelerTool it) => it.id == 'mesh.extrude',
    );

    Future<String> labelIn(Locale locale) async {
      late String said;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              said = toolLabelIn(context, extrude);
              return const SizedBox();
            },
          ),
        ),
      );
      return said;
    }

    expect(await labelIn(const Locale('en')), 'Extrude');
    expect(await labelIn(const Locale('ru')), 'Выдавливание');

    // And with no delegates at all — which is what a widget test pumping
    // one panel gets — the English the tool carries is what shows, rather
    // than an assertion in the middle of a test about something else.
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) => Text(
          toolLabelIn(context, extrude),
          textDirection: TextDirection.ltr,
        ),
      ),
    );
    expect(find.text('Extrude'), findsOneWidget);
  });
}
