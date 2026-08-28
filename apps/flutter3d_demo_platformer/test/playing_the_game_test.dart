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
import 'package:flutter3d_demo_platformer/main.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // **The window, and this is the number the file used to be wrong about.**
  // `SceneSurface` renders at the size it is laid out at, not at the size the
  // device was made with — so a test window of the default 800 × 600 drew
  // 480,000 software pixels a frame however small `CpuDevice` was told to be.
  // That is four and a half seconds a pump. Ninety-six by fifty-four is nine
  // milliseconds, and nothing here looks at the picture.
  tester.view.physicalSize = const Size(96, 54);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const PlatformerApp(openGraphics: _cpuDevice));

  // **Waited for in real time, once, rather than pumped at.** Opening the
  // device and reading a level are asynchronous and resolve on the clock the
  // machine has, not on the fake one a test drives — so pumping advances frames
  // and never the load. `runAsync` is the only way to hand over real
  // milliseconds.
  //
  // One long wait rather than a loop of short ones because each pump draws a
  // frame in software, and frames are the expensive thing here: this costs two
  // of them instead of twenty.
  // Real milliseconds and a frame, alternately: the load resolves on the
  // machine's clock and the widget only notices on a frame, so neither alone
  // gets there. Two rounds is enough for the title card, which does not wait
  // for the level.
  await _realTime(tester, rounds: 2);
}

/// Hands the machine's clock back, [rounds] times, drawing a frame between.
///
/// **This is what unskipped the play-through.** Opening a device, reading a
/// level and decoding its textures all complete on the real clock, and a
/// `testWidgets` body runs on a fake one — so pumping advanced frames past a
/// load that had not moved, for ever. `runAsync` alone does not do it either:
/// the widget only sees the result on its next frame.
Future<void> _realTime(
  WidgetTester tester, {
  required int rounds,
  bool Function()? until,
}) async {
  for (var round = 0; round < rounds; round++) {
    if (until != null && until()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(_tick);
  }
}

/// Touches the screen where the title card is, which is what begins a run.
///
/// Anywhere will do: the `Listener` that calls `_begin` wraps the whole stack,
/// so it sees the press whatever the card above it does with it. Near the top,
/// away from the gear on the right and the controls along the bottom.
Future<void> _touchToBegin(WidgetTester tester) async {
  // Near the top of a window that is ninety-six by fifty-four: away from the
  // gear on the right and the touch controls along the bottom.
  await tester.tapAt(const Offset(48, 8));
  // Then wait for the level, which is still arriving: textures decode on the
  // real clock. Bounded, so a level that never loads fails the assertion below
  // rather than hanging the suite — and it does not arrive, see the note above
  // this test.
  await _realTime(tester, rounds: 200, until: () => _clock(tester) != null);
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
    // A real millisecond between frames, because the game keeps loading while
    // it plays — a model arrives from an isolate, a texture from a codec — and
    // both resolve on the machine's clock rather than on the fake one.
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
    expect(
      find.textContaining('The stick walks'),
      findsOneWidget,
      reason: 'a phone was told about the keyboard',
    );
    // Not running yet: there is no HUD behind the card to count a run nobody
    // has started.
    expect(_clock(tester), isNull);
  });

  // **Still skipped, and two of the guesses in the previous note were wrong.**
  //
  // Everything up to the level loads: the application mounts, the device opens,
  // the title card comes up, a touch takes it down, and the touch controls
  // appear. Then the level's textures stop arriving — the third one, every
  // time.
  //
  // **What was wrong before.** The old note said a frame here is expensive
  // because the game draws three shadow cascades at 2048, and that whoever got
  // past the zone would want that number down first. Measured: a pump costs 4.2
  // seconds with a 96 × 54 `CpuDevice`, 4.2 seconds with an 8 × 8 one, and 4.2
  // seconds with a single 128-pixel cascade. The size the device was made with
  // is not the size anything draws at — `SceneSurface` renders at the size it
  // is *laid out* at, and a test window is 800 × 600, so every pump was
  // rasterising 480,000 pixels in software.
  //
  // `tester.view.physicalSize` fixes it, in this file, with no production
  // change: 4.2 seconds a pump became **nine milliseconds**. That is worth
  // knowing for every widget test of every game here, and it is why the two
  // tests below now run in seven seconds rather than half a minute.
  //
  // **What is actually in the way.** With frames that cheap, the load can be
  // fed real milliseconds in slices — `runAsync` twenty at a time, a frame
  // between — and it *does* progress: two textures, sometimes four, then
  // nothing. Eight uninterrupted seconds of the machine's clock gets no
  // further than slices do, which rules out "it needs more time". The stall is
  // inside `ui.instantiateImageCodec` / `Image.toByteData` under
  // `flutter_tester`, where each decode is started from inside the last one's
  // continuation. So it is not the fake-async zone alone, and it is not the
  // shadow atlas: it is fifteen PNG decodes through the test engine's image
  // pipeline.
  //
  // **Routes already tried, so nobody tries them twice.** Mounting inside
  // `runAsync` — works, and took twenty-one minutes before the window was
  // shrunk. Loading the level outside the zone and handing it in through a seam
  // like `openGraphics` — gets past the load and still does not finish, and the
  // seam was reverted because a seam that buys a skipped test is production
  // surface for nothing. A `ShadowSettings` seam for the same purpose — reverted
  // for the same reason, and the measurement above says it would not have
  // helped anyway.
  //
  // Pre-decoding the textures in a `setUpAll` inside `runAsync`, so a cache
  // serves them synchronously later — the same route as "load the level
  // outside the zone", by another name, and it fails for the reason the
  // paragraph above gives rather than the reason that one did: the stall is
  // *inside* the decode chain, so a warm-up loop hits it at the third texture
  // exactly as the load does. Recorded because it is the obvious next idea and
  // it has now been the obvious next idea twice.
  //
  // What the move to `PlatformerRun` did buy is `run_test.dart` beside this
  // file: the same sequence — begin, resume, restart, move on, save — from a
  // plain `test()` with a `CpuDevice`, where the loader completes perfectly
  // well. The dungeon proved that route first and this game now has it.
  //
  // So what is left here is only what genuinely needs a widget: the pause gate
  // seen through a real settings panel, and a touch drag reaching the runner.
  // Left rather than deleted because it names those, and whoever gets the
  // decodes to land inherits the assertions.
  playing('and a run goes: begin, play, pause, come back, walk', (
    WidgetTester tester,
  ) async {
    await _launch(tester);

    // **Begin.** A touch anywhere takes the card down.
    await _touchToBegin(tester);
    await _play(tester, seconds: 0.5);

    expect(find.text('Ascent'), findsNothing, reason: 'the card stayed up');
    expect(
      find.byType(TouchStick),
      findsOneWidget,
      reason: 'a phone with no stick has no way to walk',
    );

    // **Play.** The clock advancing is the whole of "the simulation is
    // stepping", and nothing before today could say it.
    final started = _clock(tester);
    expect(
      started,
      isNotNull,
      reason: 'no HUD, so no run — on screen: ${_onScreen(tester)}',
    );
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
    expect(
      _clock(tester),
      stopped,
      reason: 'the game kept running behind the settings',
    );

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
  }, skip: 'the level\'s textures stop decoding at the third — see above');
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
