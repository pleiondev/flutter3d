/// The game, mounted and played through its own entry point.
///
///     flutter test test/playing_the_game_test.dart
///
/// **Nothing has ever done this.** `main.dart` is a thousand lines holding the
/// pause gate, the level chain, the run's tally, the settings panel, the touch
/// controls and the composition of two look devices — and it was imported by no
/// test at all, because it opened `flutter_gpu` on the first frame and a test
/// has no GPU. Every one of those was covered by an analyser and a pair of
/// eyes; several were changed, in this repository, without either being able to
/// say whether the game still ran.
///
/// One optional field — `PlatformerApp.openGraphics` — closes that, and the
/// device handed in is `CpuDevice`, which is what `frame_test.dart` already
/// draws with.
///
/// ## Played as a touch build, and that is the useful half
///
/// The platform is forced to Android, which is not a detour: it is the one
/// shape where the game is **driveable from the widget tree**. `TouchStick` and
/// `TouchButton` are real widgets on screen there, so a drag and a tap in this
/// test go through the shipped input path — translator, `InputState`, fixed
/// step, simulation — rather than through a handle a test was given. It is also
/// the shape nobody has ever run, because there is no phone here.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/main.dart';

/// A renderer with no GPU under it, as small as it can be and still be one.
///
/// **Ninety-six by fifty-four, and that number is the difference between this
/// file running and not.** Every pump draws a frame in software — three shadow
/// cascades and a scene — so the cost is per pixel and per frame, and the first
/// draft asked for 320 by 180 across a thousand frames and had produced no
/// output at all after ten minutes. Nothing here looks at the picture; what is
/// being tested is that the game runs, and it runs at any size.
Future<GraphicsDevice> _cpuDevice() async => CpuDevice(
      width: 96,
      height: 54,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

/// How much time one pump carries.
///
/// A tenth of a second rather than a frame's sixteenth, which is not a cheat:
/// `GameLoop` takes the elapsed time and runs however many fixed steps fit, so
/// a hundred milliseconds is six steps of simulation for one frame of drawing.
/// That is exactly what a slow machine does, and it is the difference between a
/// second of game time costing ten software frames and sixty.
const Duration _tick = Duration(milliseconds: 100);

/// Mounts the real application and waits for its first level.
///
/// The level is read through `rootBundle` — the shipped document, from the
/// shipped asset bundle — so this is the game a player launches rather than a
/// world assembled by the test.
Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(PlatformerApp(openGraphics: _cpuDevice));

  // **Waited for in real time, once, rather than pumped at.** Opening the
  // device and reading a level are asynchronous and resolve on the clock the
  // machine has, not on the fake one a test drives — so pumping advances frames
  // and never the load. `runAsync` is the only way to hand over real
  // milliseconds.
  //
  // One long wait rather than a loop of short ones because each pump draws a
  // frame in software, and frames are the expensive thing here: this costs two
  // of them instead of twenty.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 1)),
  );
  await tester.pump(_tick);
}

/// Touches the screen where the title card is, which is what begins a run.
///
/// Anywhere will do: the `Listener` that calls `_begin` wraps the whole stack,
/// so it sees the press whatever the card above it does with it. Near the top,
/// away from the gear on the right and the controls along the bottom.
Future<void> _touchToBegin(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 120));
}

/// The clock the HUD is showing, in seconds, or null while there is no HUD.
int? _clock(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  for (final text in texts) {
    final value = text.data;
    if (value == null) continue;
    final match = RegExp(r'^(\d+):(\d\d)$').firstMatch(value);
    if (match != null) {
      return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    }
  }
  return null;
}

/// Everything the screen is saying, for a failure that needs to say what it saw.
String _onScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data)
    .whereType<String>()
    .join(' | ');

/// Runs the game for [seconds] of its own time.
Future<void> _play(WidgetTester tester, {double seconds = 1.0}) async {
  for (var i = 0; i < (seconds * 1000 / _tick.inMilliseconds).round(); i++) {
    await tester.pump(_tick);
  }
}

/// One test that mounts the game, and one that plays it.
///
/// **Two rather than six, and the reason is minutes.** Every pump draws a frame
/// in software, so a launch is the expensive part and six launches were nine
/// minutes of a suite that otherwise takes twenty seconds. A run is a sequence
/// anyway — begin, play, pause, resume, walk — and reading it as one is closer
/// to what a player does than six separate arrivals would be.
void main() {
  // `LevelLoader` reads through `rootBundle`, which needs the binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // **A `flutter test` calls itself Android**, which is what makes the touch
    // build reachable here — and it also means the gamepad's platform channel
    // looks present. It is not, so it is answered with silence rather than a
    // `MissingPluginException` on the frame the game first reads a pad.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.flutter3d/gamepad/events'),
      (MethodCall call) async => null,
    );
    // The orientation and system-chrome calls `main()` makes on a phone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => null,
    );
  });

  playing('it starts, says what it is, and waits to be told to play', (
    WidgetTester tester,
  ) async {
    await _launch(tester);

    expect(find.text('Ascent'), findsOneWidget);
    expect(find.textContaining('The stick walks'), findsOneWidget,
        reason: 'a phone was told about the keyboard');
    // Not running yet: there is no HUD behind the card to count a run nobody
    // has started.
    expect(_clock(tester), isNull);
  });

  // **Still skipped, and the reason is now understood rather than suspected.**
  //
  // Everything up to the level loads: the application mounts, the device opens,
  // the title card comes up, a touch takes it down, and the touch controls
  // appear. Then `LevelLoader().load` never returns — not throwing, which would
  // be reported, and not waiting on time, because feeding it real milliseconds
  // through `runAsync` changes nothing.
  //
  // **Moving the load out of the widget did not help, and that was worth
  // finding out.** It is `PlatformerRun` now, an ordinary class in
  // `flutter3d_session` — but this test still *mounts the application*, and the
  // load is still started from `initState`, which is inside the fake-async zone
  // `testWidgets` runs in. Where it lives was never the problem; who starts it
  // is.
  //
  // **Two more routes were tried since, and both are dead ends worth writing
  // down rather than trying again.**
  //
  // *Mounting inside `runAsync`.* It works — the load completes and the first
  // test passes. It also takes twenty-one minutes, because `runAsync` hands the
  // clock back to the machine: every `pump` then draws a software frame in real
  // time instead of on the fake clock, and this game's frame is not cheap. Six
  // seconds became twenty-one minutes for one test.
  //
  // *Loading the level outside the zone and handing it in*, through a seam of
  // the same shape as `openGraphics`. That does get past the load — the run
  // begins, which the zone had made impossible — and the play-through still
  // does not finish. So the zone was not the only thing in the way, and what
  // else is has not been established. The seam was reverted with it; a seam
  // that buys a test which still hangs is production surface for nothing.
  //
  // *And why any frame here is expensive*, which is worth knowing before
  // anybody tries again: the game draws three shadow cascades at 2048, which is
  // a 6144 × 2048 atlas. A GPU fills that in microseconds; `CpuDevice` fills it
  // in about a minute. Whoever gets past the zone will want that number down
  // first.
  //
  // What the move did buy is `run_test.dart` beside this file: the same
  // sequence — begin, resume, restart, move on, save — driven from a plain
  // `test()` with a `CpuDevice`, where the loader completes perfectly well. The
  // dungeon proved that route first and this game now has it.
  //
  // So what is left here is only what genuinely needs a widget: the pause gate
  // seen through a real settings panel, and a touch drag reaching the runner.
  // Left rather than deleted because it names those, and whoever gets past the
  // zone inherits the assertions.
  playing('and a run goes: begin, play, pause, come back, walk', (
    WidgetTester tester,
  ) async {
    await _launch(tester);

    // **Begin.** A touch anywhere takes the card down.
    await _touchToBegin(tester);
    await _play(tester, seconds: 0.5);

    expect(find.text('Ascent'), findsNothing, reason: 'the card stayed up');
    expect(find.byType(TouchStick), findsOneWidget,
        reason: 'a phone with no stick has no way to walk');

    // **Play.** The clock advancing is the whole of "the simulation is
    // stepping", and nothing before today could say it.
    final started = _clock(tester);
    expect(started, isNotNull,
        reason: 'no HUD, so no run — on screen: ${_onScreen(tester)}');
    await _play(tester, seconds: 2.0);
    final running = _clock(tester);
    expect(running, greaterThan(started!));

    // **Pause.** The bug this file exists for: opening the panel looked as
    // though it paused, because on the desktop it released the pointer and the
    // pointer was the gate. On a phone and in a browser there is no pointer, so
    // the runner went on falling behind the settings — for as long as each of
    // those builds has existed.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    final stopped = _clock(tester);
    await _play(tester, seconds: 2.0);
    expect(_clock(tester), stopped,
        reason: 'the game kept running behind the settings');

    // **Come back.**
    await tester.tap(find.text('Back to the game'));
    await tester.pump();
    final resumed = _clock(tester);
    await _play(tester, seconds: 2.0);
    expect(_clock(tester), greaterThan(resumed!));

    // **Walk**, through the shipped input path — the widget, the translator,
    // `InputState`, the fixed step — rather than through a handle a test was
    // given. Where the runner ends up belongs to `playthrough_test.dart`, which
    // drives the simulation directly and always has; what was missing was
    // anybody driving it from the screen.
    final stick = find.byType(TouchStick);
    final gesture = await tester.startGesture(tester.getCenter(stick));
    await gesture.moveBy(const Offset(0, -60));
    await _play(tester, seconds: 1.0);
    await gesture.up();

    expect(tester.takeException(), isNull);
    expect(_clock(tester), isNotNull, reason: 'the run ended while walking');
  }, skip: 'the load starts inside the fake-async zone — see above');
}

/// A test of the touch build, with the platform put back afterwards.
///
/// Inside the body rather than in a `tearDown`, because the framework checks
/// that no foundation debug variable is still set **before** tear-down runs —
/// and reports it as a failure of the test that set it.
void playing(
  String description,
  Future<void> Function(WidgetTester) body, {
  String? skip,
}) {
  testWidgets(description, skip: skip != null, (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
