/// Every widget around a game, held to WCAG 2.2 at level AA.
///
///     flutter test --tags accessibility
///
/// **The package's promise, checked where it is kept.** Each screen a game
/// takes from here is mounted the way a game mounts it, at the text size it
/// was written for and at twice that, over a white frame and over a black
/// one, because a game's picture can be either behind a HUD; and each is
/// asked what a player with low vision, a screen reader or a sensitivity to
/// flashes would ask of it:
///
/// - **every control says what it is** (4.1.2): a tap target has a label, and
///   so does anything a finger presses or drags;
/// - **every target can be hit** (2.5.8): 24 logical pixels a side at least;
/// - **the text can be read** (1.4.3): measured from the pixels drawn, with
///   the colours the theme's tokens give;
/// - **the text grows when the player asks** (1.4.4): every line takes the
///   platform's `textScaler` and nothing overflows at twice the size;
/// - **the tokens keep their contrast over any frame** (1.4.3, 1.4.11), the
///   pairs `GameUiTheme.contrastPairs` names;
/// - **the panel says what the game will do with reduced motion**;
/// - **nothing flashes more than three times a second** (2.3.1).
///
/// The same file, tagged `accessibility`, is what `tool/ci.sh` runs by tag in
/// every package and application that makes the promise, and the structure
/// rule `a package that promises WCAG AA keeps it` holds the list.
@Tags(<String>['accessibility'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_app/flutter3d_app.dart' show MemoryStorage;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_ui/flutter3d_game_ui.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2's minimum target, as Flutter's guideline checks it.
const AccessibilityGuideline _targetSize = MinimumTapTargetGuideline(
  size: Size.square(Wcag.targetSize),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum',
);

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _handbrake = GameAction('handbrake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');

const Credit _credit = Credit(
  file: 'models/car.glb',
  work: 'Car Kit, race car',
  author: 'Kenney',
  source: 'https://kenney.nl/assets/car-kit',
  license: 'CC BY 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
);

GameSettingsController _settings() => GameSettingsController(
  settings: const GameSettings(),
  file: SettingsFile(appName: 'a11y', storage: MemoryStorage()),
  apply: (_) {},
  actions: DesktopInput.addDefaultsTo(ActionMap(actions: ActionSet.common)),
);

/// Every screen this package draws, as a game mounts it.
final Map<String, Widget Function()> _gallery = <String, Widget Function()>{
  'the settings panel': () {
    final settings = _settings();
    return SettingsPanel(
      settings: settings,
      sections: SettingsSection.standard(
        buses: settableBuses,
        defaultActions: () => settings.actions.copy(),
        colors: ColorRoles(<ColorRole>[
          const ColorRole('ours', 'Our side', Color(0xFFD02020)),
        ]),
        padConnected: true,
        credits: const CreditsSection(credits: <Credit>[_credit]),
      ),
    );
  },
  'the settings gear': () => Stack(
    children: <Widget>[
      SettingsOverlay(
        settings: _settings(),
        sections: const <SettingsSection>[],
        opening: () {},
      ),
    ],
  ),
  'the title sheet': () => TitleSheet(
    title: 'SUMMIT',
    tagline: 'Climb to the top before the light goes.',
    lines: const <String>['Stick: walk', 'Jump: climb'],
    credits: const <Credit>[_credit],
    prompt: 'Tap to begin',
    notice: 'A saved run is waiting.',
    onBegin: () {},
  ),
  'the ending sheet': () => const EndingSheet(
    title: 'You reached the summit.',
    tallies: <EndingTally>[
      EndingTally('time', '3:41'),
      EndingTally('falls', '2'),
    ],
    credits: <Credit>[_credit],
    again: 'Tap to play again',
    aside: 'The machine lost 2 s and the game never ran them.',
  ),
  'tap to restart': () =>
      Stack(children: <Widget>[TapToRestart(onRestart: () {})]),
  'a cutscene': () => CutsceneOverlay(
    fade: 0.4,
    subtitle: 'The bridge is out. We go round.',
    skipHint: 'Tap to skip',
    onSkip: () {},
  ),
  'the heads-up display': () => Align(
    alignment: Alignment.topLeft,
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        const HudPanel(
          children: <Widget>[
            HudLine(label: 'LAP', value: '2/3'),
            HudLine(label: 'RECORD', value: '1:02.441', accent: true),
          ],
        ),
        const HudTally(label: 'coins', value: '12'),
        const HudBanner('Click to play'),
        const Speedometer(metersPerSecond: 27.0),
        MiniMap(
          outline: <Vector2>[Vector2(0, 0), Vector2(10, 0), Vector2(10, 6)],
          markers: <Vector2>[Vector2(2, 0), Vector2(8, 1)],
        ),
      ],
    ),
  ),
  'the touch controls': () {
    final input = InputState();
    return TouchControls(
      state: input,
      buttons: const <TouchAction>[
        TouchAction(GameAction.jump, 'jump'),
        TouchAction(GameAction.sprint, 'dash'),
      ],
      toggles: <TouchToggle>[
        TouchToggle(label: 'sprint', on: true, onTap: () {}),
      ],
      slots: const <TouchSlot>[
        TouchSlot('fists'),
        TouchSlot('rocket', owned: false),
      ],
      current: 0,
      corner: TouchToggle(label: 'map', on: false, onTap: () {}),
    );
  },
  'the wheel and pedals': () => TouchDrive(
    state: InputState(),
    steerLeft: _left,
    steerRight: _right,
    throttle: _throttle,
    brake: _brake,
    handbrake: _handbrake,
  ),
  'the photo bar': () => PhotoBar(
    mode: PhotoMode(
      controls: const KeyPhotoControls(
        up: LogicalKeyboardKey.space,
        down: LogicalKeyboardKey.keyC,
      ),
    )..said = 'Saved to Pictures.',
  ),
  'the share strip': () => Align(
    alignment: Alignment.topLeft,
    child: ShareStrip(onShare: () async => 'K3X9', onOpen: (_) async => ''),
  ),
};

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1.0,
  Color frame = const Color(0xFFFFFFFF),
  bool reducedMotion = false,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: Scaffold(
            backgroundColor: frame,
            body: SizedBox.expand(key: _stage, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const Key _stage = ValueKey<String>('stage');

/// What a finger can press or drag on the stage, found by the widgets that
/// take the pointer: a `Listener`, a `GestureDetector`.
///
/// Flutter's own controls are left to it: a `Slider`, a `Switch`, a button,
/// a chip, a text field and a scroll view each carry their own semantics,
/// and the guidelines above already hold their targets.
Iterable<RenderObject> _pointerTargets(WidgetTester tester) => <RenderObject>[
  for (final type in const <Type>[Listener, GestureDetector])
    for (final element
        in find
            .descendant(of: find.byKey(_stage), matching: find.byType(type))
            .evaluate())
      if (!_insideFlutterControl(element)) element.renderObject!,
];

bool _insideFlutterControl(Element element) {
  var inside = false;
  element.visitAncestorElements((Element ancestor) {
    final widget = ancestor.widget;
    inside =
        widget is Scrollable ||
        widget is Slider ||
        widget is Switch ||
        widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is InkWell ||
        widget is RawChip ||
        widget is ChoiceChip ||
        widget is EditableText ||
        widget is TextField ||
        widget is SelectableText;
    return !inside && ancestor.widget.key != _stage;
  });
  return inside;
}

void main() {
  for (final MapEntry(key: name, value: build) in _gallery.entries) {
    group(name, () {
      for (final scale in const <double>[1.0, Wcag.textScale]) {
        testWidgets('has labelled, reachable targets at ${scale}x', (
          WidgetTester tester,
        ) async {
          final handle = tester.ensureSemantics();
          await _mount(tester, build(), scale: scale);

          // 1.4.4: nothing overflows at twice the size, which Flutter reports
          // as an exception during layout.
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(_targetSize));
          handle.dispose();
        });

        for (final frame in const <Color>[
          Color(0xFFFFFFFF),
          Color(0xFF000000),
        ]) {
          testWidgets(
            'reads at ${scale}x over ${frame == const Color(0xFFFFFFFF) ? 'white' : 'black'}',
            (WidgetTester tester) async {
              final handle = tester.ensureSemantics();
              await _mount(tester, build(), scale: scale, frame: frame);
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              handle.dispose();
            },
          );
        }
      }

      testWidgets('takes the platform text size on every line', (
        WidgetTester tester,
      ) async {
        // A `TextScaler.noScaling`, a `textScaleFactor: 1` or a `TextPainter`
        // made without the context's scaler is a line that stays small while
        // the player's phone says otherwise.
        await _mount(tester, build(), scale: Wcag.textScale);
        // An `Icon` is drawn as a glyph of text that Flutter never scales
        // with the reading size, by design; it is a picture, not a line.
        final lines = <Element>[
          for (final element in find.byType(RichText).evaluate())
            if (!_inside<Icon>(element)) element,
        ];
        for (final element in lines) {
          final line = element.widget as RichText;
          final said = line.text.toPlainText();
          expect(
            line.textScaler,
            const TextScaler.linear(Wcag.textScale),
            reason: '"$said" ignores the text size',
          );
          // And it is all there: a glyph drawn past the box it was given is
          // a glyph cut off, which a fixed column does silently at twice the
          // size (`RECORD` read as `RECO`), and a line past its `maxLines` is
          // a line lost.
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '"$said" runs past its last line',
          );
          // Glyph by glyph, past the spaces: a space that ends a wrapped line
          // hangs past it by design and hides nothing.
          for (final box in <TextBox>[
            for (var i = 0; i < said.length; i++)
              if (said[i].trim().isNotEmpty)
                ...paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: i, extentOffset: i + 1),
                ),
          ]) {
            // The slack is a last letter's tracking, which its box carries
            // past the line's measured width: two points at twice the size.
            expect(
              box.right <= paragraph.size.width + 5.0 && box.left >= -0.5,
              isTrue,
              reason:
                  '"$said" is cut off by the width it was given: a glyph '
                  'at ${box.left}..${box.right} in ${paragraph.size.width}',
            );
          }
        }
      });

      testWidgets('names everything a finger presses or drags', (
        WidgetTester tester,
      ) async {
        // A stick, a pedal, a sheet that begins the game when touched: each
        // is something a screen reader meets, and each says what it is.
        final handle = tester.ensureSemantics();
        await _mount(tester, build());
        for (final target in _pointerTargets(tester)) {
          final node = _semanticsOf(target);
          final said = node == null
              ? ''
              : '${node.label}${node.value}${node.tooltip}'.trim();
          expect(
            said,
            isNotEmpty,
            reason: '${target.runtimeType} under ${target.parent} says nothing',
          );
        }
        handle.dispose();
      });
    });
  }

  group('the contrast tokens', () {
    test('every pair the fallback theme names holds over any frame', () {
      final pairs = GameUiTheme.fallback.contrastPairs;
      expect(pairs, isNotEmpty);
      for (final pair in pairs) {
        expect(
          pair.worstRatio,
          greaterThanOrEqualTo(pair.minimum),
          reason: '${pair.name} falls to ${pair.worstRatio.toStringAsFixed(2)}',
        );
        expect(pair.isMet, isTrue);
      }
    });

    test('the pairs fail a theme that would not read', () {
      // The check that the check can fail: white glyphs on the touch faces
      // the theme had before 1.0, a third of white over whatever is behind.
      const washedOut = GameUiTheme(
        touchFill: Color(0x33FFFFFF),
        touchGlyph: Color(0xCCFFFFFF),
      );
      final failing = <String>[
        for (final pair in washedOut.contrastPairs)
          if (!pair.isMet) pair.name,
      ];
      expect(failing, contains('touchGlyph on touchFill'));
    });

    test('the WCAG ratio is the one the specification gives', () {
      expect(
        Wcag.contrast(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21.0, 1e-9),
      );
      // #767676 on white is the classic 4.54:1, the lightest grey that
      // passes AA for body text.
      expect(
        Wcag.contrast(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        closeTo(4.54, 0.01),
      );
      expect(
        Wcag.contrast(const Color(0xFF777777), const Color(0xFFFFFFFF)),
        lessThan(Wcag.textContrast),
      );
    });
  });

  group('reduced motion', () {
    testWidgets('the camera-motion slider shows what the game will do', (
      WidgetTester tester,
    ) async {
      // The game keeps none of a camera's involuntary motion for a player
      // whose phone asks for less (`Accommodations.cameraMotion`), until the
      // player moves this slider; a slider that showed all of it in the
      // meantime would be the panel disagreeing with the screen behind it.
      final settings = _settings();
      await _mount(
        tester,
        SettingsPanel(
          settings: settings,
          sections: const <SettingsSection>[AccessibilitySection()],
        ),
        reducedMotion: true,
      );
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(slider.value, 0.0);

      // The player's own answer wins over the system's.
      settings.setValue(GameSettingKeys.cameraMotion, 0.5);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider).first).value, 0.5);
    });
  });

  group('the flash limit', () {
    /// Whether [shown] reverses direction by [Wcag.flashLuminanceChange] or
    /// more, at each of [times]: the edges of the flashes a viewer sees.
    List<Duration> edges(List<double> shown, List<Duration> times) {
      final found = <Duration>[];
      var direction = 0;
      var extreme = shown.first;
      for (var i = 1; i < shown.length; i++) {
        final value = shown[i];
        final moved = value - extreme;
        if (direction != 0 && moved * direction > 0) {
          extreme = value;
        } else if (moved.abs() >= Wcag.flashLuminanceChange) {
          found.add(times[i]);
          direction = moved > 0 ? 1 : -1;
          extreme = value;
        }
      }
      return found;
    }

    test('holds a strobe to three flashes in any second', () {
      // Black and clear ten times a second, for two seconds: twenty flashes
      // asked for, at sixty frames a second.
      final limit = FlashLimit();
      final times = <Duration>[
        for (var frame = 0; frame < 120; frame++)
          Duration(microseconds: frame * 1000000 ~/ 60),
      ];
      final shown = <double>[
        for (final time in times)
          limit.limit((time.inMilliseconds ~/ 50).isEven ? 1.0 : 0.0, at: time),
      ];
      final seen = edges(shown, times);
      // A flash is a pair of opposing changes (2.3.1), so three flashes are
      // six edges in any second.
      for (var i = 0; i + 2 * Wcag.flashesPerSecond < seen.length; i++) {
        expect(
          seen[i + 2 * Wcag.flashesPerSecond] - seen[i],
          greaterThanOrEqualTo(const Duration(seconds: 1)),
          reason:
              'more than three flashes between ${seen[i]} and '
              '${seen[i + 2 * Wcag.flashesPerSecond]}',
        );
      }
      expect(seen, isNotEmpty);
    });

    test('lets a fade through untouched', () {
      final limit = FlashLimit();
      for (var frame = 0; frame <= 60; frame++) {
        final time = Duration(microseconds: frame * 1000000 ~/ 60);
        final wanted = frame <= 30 ? frame / 30 : (60 - frame) / 30;
        expect(limit.limit(wanted, at: time), wanted);
      }
    });

    testWidgets('a cutscene that strobes its fade is held to the limit', (
      WidgetTester tester,
    ) async {
      var fade = 0.0;
      late StateSetter set;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            set = setState;
            return CutsceneOverlay(
              fade: fade,
              subtitle: null,
              skipHint: 'skip',
              onSkip: () {},
            );
          },
        ),
      );
      double shown() => tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey<String>('cutscene:fade')),
          )
          .color
          .a;
      final seen = <double>[];
      final times = <Duration>[];
      var at = Duration.zero;
      for (var frame = 0; frame < 60; frame++) {
        set(() => fade = (frame ~/ 3).isEven ? 1.0 : 0.0);
        await tester.pump(const Duration(microseconds: 16667));
        at += const Duration(microseconds: 16667);
        seen.add(shown());
        times.add(at);
      }
      expect(
        edges(seen, times).length,
        lessThanOrEqualTo(2 * Wcag.flashesPerSecond),
      );
    });
  });
}

/// Whether [element] is built by a [T].
bool _inside<T extends Widget>(Element element) {
  var inside = false;
  element.visitAncestorElements((Element ancestor) {
    inside = ancestor.widget is T;
    return !inside;
  });
  return inside;
}

/// The semantics node [target] is drawn into, merged as a reader hears it.
SemanticsNode? _semanticsOf(RenderObject target) {
  RenderObject? at = target;
  while (at != null) {
    final node = at.debugSemantics;
    if (node != null) {
      var merged = node;
      while (merged.isPartOfNodeMerging && merged.parent != null) {
        merged = merged.parent!;
      }
      return merged;
    }
    at = at.parent;
  }
  return null;
}
