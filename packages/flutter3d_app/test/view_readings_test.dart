/// What a widget beside a view reads of the simulation: the published state
/// (`Flutter3dEngine.published`) and one probe's reading of it
/// (`ProbeBuilder`), the same inline and with the simulation in an isolate.
///
///     flutter test test/view_readings_test.dart
@TestOn('vm')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LoopContext, LoopPhase, Quantity, Unit;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

/// A plate at 300 K that warms by a kelvin a step, with a probe on it.
void _addPlate(EngineLoop loop) {
  final plate = loop.world.spawn();
  loop.world
    ..set<MaterialStateComponent>(
      plate,
      MaterialStateComponent(MatterState.at(temperature: 300)),
    )
    ..set<Probe>(
      plate,
      Probe(
        id: 'plate.t',
        quantity: MatterState.temperatureId,
        unit: Unit.kelvin,
      ),
    );
  loop.addSystem('test.warm', LoopPhase.fields, (LoopContext context) {
    final state = loop.world.get<MaterialStateComponent>(plate)!.state;
    loop.world.set<MaterialStateComponent>(
      plate,
      MaterialStateComponent(
        state.withQuantity(
          MatterState.temperatureId,
          Quantity(state.temperature + 1, Unit.kelvin),
        ),
      ),
    );
  });
}

/// What the isolate builds: the plate, in a loop of its own.
SimulationSetup _plate(Object? _) {
  final loop = EngineLoop(input: InputState());
  _addPlate(loop);
  return SimulationSetup(loop: loop, applyInput: (_) {});
}

/// The view, and under it what [ProbeBuilder] makes of the plate's probe
/// once the engine is there.
final class _Gauge extends StatefulWidget {
  const _Gauge({required this.simulation});

  final SimulationPlacement simulation;

  @override
  State<_Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<_Gauge> {
  Flutter3dEngine? engine;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: <Widget>[
        SizedBox(
          width: 32,
          height: 24,
          child: Flutter3dView(
            device: DeviceSettings(
              device: FakeBackend(),
              presenter: _noPresenter,
            ),
            view: const ViewSettings(warmUp: false),
            loop: LoopSettings(simulation: widget.simulation),
            onCreated: (Flutter3dEngine made) {
              if (widget.simulation.factory == null) _addPlate(made.loop);
              setState(() => engine = made);
            },
          ),
        ),
        if (engine case final engine?)
          ProbeBuilder(
            published: engine.published,
            probe: 'plate.t',
            builder: (context, reading) => Text(
              reading == null
                  ? 'no reading'
                  : '${reading.value.single.round()} K',
            ),
          ),
      ],
    ),
  );
}

/// Pumps [count] refreshes of a 60 Hz display.
Future<void> _refreshes(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

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
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// The kelvins the gauge shows, or null while it shows none.
int? _shown(WidgetTester tester) {
  final texts = find.byType(Text).evaluate();
  if (texts.isEmpty) return null;
  final words = (texts.single.widget as Text).data!;
  return words.endsWith(' K') ? int.parse(words.split(' ').first) : null;
}

void main() {
  testWidgets('a probe in the view\'s loop reaches a widget beside it', (
    tester,
  ) async {
    // Mutation: leave `engine._republish()` out of the tick. The engine's
    // published state stays the one it was made with, and the gauge says
    // "no reading" however long the plate warms.
    await tester.pumpWidget(
      const _Gauge(simulation: SimulationPlacement.inline()),
    );
    await tester.pump();
    await _refreshes(tester, 2);
    final first = _shown(tester);
    expect(first, isNotNull);
    await _refreshes(tester, 10);
    final later = _shown(tester)!;
    // A kelvin a step: ten frames at 60 Hz are about ten steps.
    expect(later - first!, inInclusiveRange(9, 11));
    final state = tester.state<_GaugeState>(find.byType(_Gauge));
    final reading = state.engine!.published.value.probe('plate.t')!;
    expect(reading.step, state.engine!.published.value.step);
    expect(reading.value.single, 300 + reading.step);
  });

  testWidgets('and the same probe reaches it from an isolate', (tester) async {
    // Mutation: build `Flutter3dEngine.published` from the view's own loop
    // rather than from `engine.simulation`. With the simulation in an
    // isolate the view's loop has no plate, and the gauge never reads.
    await tester.pumpWidget(
      const _Gauge(simulation: SimulationPlacement.isolate(_plate)),
    );
    final state = tester.state<_GaugeState>(find.byType(_Gauge));
    await _settle(tester, () => state.engine != null);
    expect(state.engine!.simulation, isA<IsolateSimulation>());
    await _settle(tester, () => (_shown(tester) ?? 0) >= 303);
    final reading = state.engine!.published.value.probe('plate.t')!;
    expect(reading.value.single, 300 + reading.step);
    expect(_shown(tester), reading.value.single.round());
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester, () => false, tries: 5);
  });
}
