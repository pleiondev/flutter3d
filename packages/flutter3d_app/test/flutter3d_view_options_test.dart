/// What a `Flutter3dView` does with its option groups beyond drawing: it
/// says when the GPU backend would not start, logs and reports what threw,
/// warms its pipelines up after the device opens, and puts the simulation
/// where `LoopSettings.simulation` says.
///
///     flutter test test/flutter3d_view_options_test.dart
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_app/src/view/simulation_placing.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

Widget _sized(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(width: 32, height: 24, child: child),
);

/// A registry whose preferred backend refuses to start, as Impeller does
/// when it is off, with [fallback] behind it.
DeviceRegistry _impellerOff(GraphicsDevice fallback) => DeviceRegistry()
  ..addBackend(
    'fake software',
    ({required int width, required int height}) async => fallback,
    asFallback: true,
  )
  ..addBackend(
    'fake impeller',
    ({required int width, required int height}) async =>
        throw StateError('Impeller is not enabled'),
  );

/// What the isolate builds: a loop counting its steps, and adding what was
/// submitted.
SimulationSetup _counting(Object? arguments) {
  final input = InputState();
  final loop = EngineLoop(input: input);
  var count = 0;
  loop.addSystem('test.count', LoopPhase.rules, (context) {
    count += 1 + (input.tunesThisStep['test.add'] ?? 0.0).round();
  });
  loop.queries.add('test.count', (_) => count);
  return SimulationSetup(
    loop: loop,
    applyInput: (SeatInput seated) =>
        input.tune('test.add', (seated.input! as num) * 1.0),
  );
}

/// One step's worth of real time and a little more.
const double _oneStep = 1.0 / 60.0 + 1e-6;

/// Lets real time pass — what an isolate's messages need — and the test's
/// own clock catch up, by turns, until [done] or [tries] turns are over.
Future<void> _settle(
  WidgetTester tester,
  bool Function() done, {
  int tries = 400,
}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Pumps [count] refreshes of a 60 Hz display.
Future<void> _refreshes(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

void main() {
  group('the GPU backend would not start', () {
    testWidgets('the view says so over the picture, and the banner closes', (
      tester,
    ) async {
      // Mutation: open the device without `onFallback`. The software
      // rasteriser then draws with nothing on screen to say why the game is
      // slow, and the engine has no refusals to show.
      final log = EngineLog();
      final warnings = <LogRecord>[];
      log.listen((r) {
        if (r.level == LogLevel.warning) warnings.add(r);
      });
      Flutter3dEngine? engine;
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(
              devices: _impellerOff(FakeBackend()),
              presenter: _noPresenter,
            ),
            view: const ViewSettings(continuous: false),
            log: log,
            onCreated: (e) => engine = e,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(engine!.backendRefusals, hasLength(1));
      expect(engine!.backendRefusals.single, contains('fake impeller'));
      expect(warnings, isNotEmpty);
      expect(find.textContaining('GPU backend would not start'), findsOne);

      await tester.tap(find.text('✕'));
      await tester.pump();
      expect(find.textContaining('GPU backend would not start'), findsNothing);
    });

    testWidgets('a view told not to shows no banner', (tester) async {
      // Mutation: show the banner whatever `fallbackBanner` says.
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(
              devices: _impellerOff(FakeBackend()),
              presenter: _noPresenter,
              fallbackBanner: false,
            ),
            view: const ViewSettings(continuous: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('GPU backend would not start'), findsNothing);
    });

    testWidgets('the first backend starting shows nothing', (tester) async {
      // Mutation: show the banner whenever a registry has a fallback.
      Flutter3dEngine? engine;
      final registry = DeviceRegistry()
        ..addBackend(
          'fake',
          ({required int width, required int height}) async => FakeBackend(),
        );
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(devices: registry, presenter: _noPresenter),
            view: const ViewSettings(continuous: false),
            onCreated: (e) => engine = e,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(engine!.backendRefusals, isEmpty);
      expect(find.textContaining('GPU backend would not start'), findsNothing);
    });
  });

  testWidgets('a frame callback that throws reaches the crash reporter', (
    tester,
  ) async {
    // Mutation: call `onFrame` outside `_guarded`. The error still reaches
    // Flutter, but a crash reporter hung on the engine's log never hears of
    // it, and a game in the field loses it.
    final log = EngineLog();
    final crashes = <Object>[];
    log.onCrash((crash) => crashes.add(crash.error));
    final thrown = StateError('a game bug');
    var threw = false;
    await tester.pumpWidget(
      _sized(
        Flutter3dView(
          device: DeviceSettings(
            device: FakeBackend(),
            presenter: _noPresenter,
          ),
          log: log,
          onFrame: (_) {
            if (threw) return;
            threw = true;
            throw thrown;
          },
        ),
      ),
    );
    await tester.pump();
    await _refreshes(tester, 2);
    expect(tester.takeException(), same(thrown));
    expect(crashes, contains(same(thrown)));
  });

  testWidgets('the engine has a log of its own when it was handed none', (
    tester,
  ) async {
    Flutter3dEngine? engine;
    await tester.pumpWidget(
      _sized(
        Flutter3dView(
          device: DeviceSettings(
            device: FakeBackend(),
            presenter: _noPresenter,
          ),
          view: const ViewSettings(continuous: false),
          onCreated: (e) => engine = e,
        ),
      ),
    );
    await tester.pump();
    expect(engine!.log, isA<EngineLog>());
  });

  group('the warm-up', () {
    testWidgets('runs once the view is laid out, to the end', (tester) async {
      // Mutation: leave `_warmUp` out of the post-frame callback. The
      // pipelines then link on each material's first draw, mid-game.
      final progress = <double>[];
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(
              device: FakeBackend(),
              presenter: _noPresenter,
            ),
            view: ViewSettings(onWarmUpProgress: progress.add),
            onCreated: (engine) => engine.scene.add(
              MeshNode(
                DeviceMesh.upload(engine.device, CuboidShape().build()),
                RenderMaterial(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await _refreshes(tester, 10);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    testWidgets('a view told not to warms nothing up', (tester) async {
      // Mutation: warm up whatever `ViewSettings.warmUp` says.
      final progress = <double>[];
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(
              device: FakeBackend(),
              presenter: _noPresenter,
            ),
            view: ViewSettings(warmUp: false, onWarmUpProgress: progress.add),
          ),
        ),
      );
      await tester.pump();
      await _refreshes(tester, 10);
      expect(progress, isEmpty);
    });
  });

  group('where the simulation runs', () {
    testWidgets('inline, it is a handle on the view\'s own loop', (
      tester,
    ) async {
      // Mutation: hand the inline handle an `applyInput` that drops what it
      // is given. A submission then never reaches the game.
      final applied = <Object?>[];
      Flutter3dEngine? engine;
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(
              device: FakeBackend(),
              presenter: _noPresenter,
            ),
            loop: LoopSettings(
              simulation: SimulationPlacement.inline(
                applyInput: (SeatInput seated) => applied.add(seated.input),
              ),
            ),
            onCreated: (e) => engine = e,
          ),
        ),
      );
      await tester.pump();
      expect(engine!.simulation, isA<LocalSimulation>());
      expect((engine!.simulation as LocalSimulation).loop, same(engine!.loop));
      engine!.simulation.submit('jump');
      await _refreshes(tester, 3);
      expect(applied, <Object?>['jump']);
    });

    testWidgets('inline, the view\'s loop runs the profile it is given', (
      tester,
    ) async {
      // Mutation: leave `profile:` out of the `EngineLoop` the view builds.
      // The loop then runs the deterministic profile whatever it was handed,
      // and a laboratory in the view gets `Portable` maths it did not ask for.
      Future<Flutter3dEngine> open(LoopSettings loop) async {
        Flutter3dEngine? engine;
        await tester.pumpWidget(
          _sized(
            Flutter3dView(
              key: UniqueKey(),
              device: DeviceSettings(
                device: FakeBackend(),
                presenter: _noPresenter,
              ),
              loop: loop,
              onCreated: (e) => engine = e,
            ),
          ),
        );
        await tester.pump();
        return engine!;
      }

      final game = await open(const LoopSettings());
      expect(game.loop.profile, SimulationProfile.deterministic);
      final lab = await open(
        const LoopSettings(profile: SimulationProfile.accurate),
      );
      expect(lab.loop.profile, SimulationProfile.accurate);
      expect(lab.loop.simulationVersion.profile, SimulationProfile.accurate);
      expect(
        const LoopSettings()
            .copyWith(profile: SimulationProfile.accurate)
            .profile,
        SimulationProfile.accurate,
      );
    });

    testWidgets('in an isolate, it steps with the view\'s frames', (
      tester,
    ) async {
      // Mutation: leave `_placed?.advance(seconds)` out of the tick. The
      // isolate opened with its clock off then never steps, and its
      // published step stays at nought.
      Flutter3dEngine? engine;
      await tester.pumpWidget(
        _sized(
          Flutter3dView(
            device: DeviceSettings(
              device: FakeBackend(),
              presenter: _noPresenter,
            ),
            loop: const LoopSettings(
              simulation: SimulationPlacement.isolate(_counting),
            ),
            onCreated: (e) => engine = e,
          ),
        ),
      );
      await _settle(tester, () => engine != null);
      expect(engine, isNotNull);
      final handle = engine!.simulation;
      expect(handle, isA<IsolateSimulation>());
      // Six refreshes of a 60 Hz display: about six steps advanced.
      await _refreshes(tester, 6);
      await _settle(tester, () => handle.published.step >= 3);
      expect(handle.published.step, greaterThanOrEqualTo(3));
      Object? answer;
      unawaited(handle.ask('test.count').then((a) => answer = a));
      await _settle(tester, () => answer != null);
      expect(answer, greaterThanOrEqualTo(3));
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester, () => false, tries: 5);
    });

    test('where no isolate can be spawned, the factory runs here', () async {
      // Mutation: refuse an isolate placement on a platform without
      // isolates, as `IsolateSimulation.open` does. A game written for both
      // places then does not start on the web.
      final placed = await placeSimulation(
        const SimulationPlacement.isolate(_counting),
        EngineLoop(input: InputState()),
        isolates: false,
      );
      addTearDown(placed.dispose);
      expect(placed.handle, isA<LocalSimulation>());
      final steps = <int>[];
      final Registration listening = placed.handle.onPublished(
        (state) => steps.add(state.step),
      );
      addTearDown(listening.cancel);
      placed.handle.submit(2);
      placed.advance(_oneStep);
      placed.advance(_oneStep);
      expect(placed.handle.published.step, 2);
      expect(await placed.handle.ask('test.count'), 1 + 2 + 1);
    });
  });
}
