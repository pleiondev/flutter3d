import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/run_info_screen.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

Demo _run() => Demo(
  level: 'assets/levels/crypt.json',
  levelHash: 'deadbeef',
  start: const Snapshot(<String, Object?>{}),
  tape: InputTape(
    seed: 7,
    frames: <InputFrame>[for (var i = 0; i < 40; i++) const InputFrame()],
  ),
  buildStamp: 'test-build',
  checkpoints: DigestTrace(every: 25),
  platform: 'macos',
);

void main() {
  testWidgets('shows what the run file actually says', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RunInfoScreen(run: _run())));

    expect(find.text('assets/levels/crypt.json'), findsOneWidget);
    expect(find.text('deadbeef'), findsOneWidget);
    expect(find.text('test-build'), findsOneWidget);
    expect(find.text('macos'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('(not recorded)'), findsOneWidget);
  });

  testWidgets('names where the run came from when the caller knows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RunInfoScreen(
          run: _run(),
          sourceDescription: 'dropped file: bug.f3drun',
        ),
      ),
    );

    expect(find.text('dropped file: bug.f3drun'), findsOneWidget);
  });
}
