/// `net-03`'s screen: the create/join door into `NetRaceSession`.
///
/// **What this file proves, and what it deliberately does not.** The whole
/// connection mechanism — deciding who is car 0, the real relay round
/// trip, the ghost flag flipping once a real peer sends a frame, and each
/// side writing its own readable `.f3drun` — is proved end to end, with a
/// real relay subprocess and real sockets, in `net_race_session_test.dart`
/// at the `NetRaceSession` level this screen calls into unchanged. Trying
/// to reproduce that same real-socket round trip *from inside a
/// `testWidgets` test* was tried here first and abandoned: a real
/// `WebSocketTransport.connect` awaited inside a widget's own tap handler
/// never resolved under `flutter_test`'s pump cycle in this sandbox — not
/// a timing issue `pump(duration)` could fix (a bare `Future.delayed`
/// triggered the same way resolves fine with `pump(duration)`, proved
/// separately), and `tester.runAsync` did not unblock it either, only
/// killing the process after 45 real seconds settled the question rather
/// than a further guess. So this file tests what a widget test safely
/// can: the presentation the screen is actually responsible for.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_racing/src/net_race_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers create and join before anything is connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetRaceScreen(relayBase: Uri.parse('ws://127.0.0.1:1/')),
      ),
    );

    expect(find.text('Create room'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tapping create room shows a connecting state immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetRaceScreen(relayBase: Uri.parse('ws://127.0.0.1:1/')),
      ),
    );

    await tester.tap(find.text('Create room'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Create room'), findsNothing);
  });
}
