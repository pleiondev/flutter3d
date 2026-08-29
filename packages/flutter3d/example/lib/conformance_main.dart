/// The conformance checks, run against Impeller.
///
///     flutter run -d macos -t lib/conformance_main.dart
///
/// The WebGL backend runs the same list under `flutter test --platform chrome`.
/// This one cannot: Flutter GPU needs Impeller enabled, which a headless test
/// does not provide. Same checks, two harnesses — which is why they are a list
/// of functions and not a file of `test()` calls.
library;

import 'dart:io';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

void main() => runApp(const ConformanceApp());

class ConformanceApp extends StatefulWidget {
  const ConformanceApp({super.key});

  @override
  State<ConformanceApp> createState() => _ConformanceAppState();
}

class _ConformanceAppState extends State<ConformanceApp> {
  String _report = 'running…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final log = StringBuffer();
    var failed = 0;
    for (final check in conformanceChecks) {
      // A device each, as the test wrapper does: a backend that leaves state
      // behind should fail on its own account rather than on the previous
      // check's.
      try {
        await check.run(await GpuRenderBackend.create());
        log.writeln('PASS  ${check.name}');
      } catch (error) {
        failed++;
        log.writeln('FAIL  ${check.name}');
        log.writeln('        $error');
      }
    }
    log.writeln(
      '=== ${conformanceChecks.length - failed} passed, '
      '$failed failed ===',
    );
    // ignore: avoid_print
    print(log);
    // Guarded: every check above awaited, and the page may be gone by now. The
    // print and the exit code below still run either way — they are the point
    // of this harness, the widget is only a courtesy.
    if (mounted) setState(() => _report = log.toString());

    // **And then leave, with a verdict a script can read.**
    //
    // Without this the app sat there being green at a person, which meant the
    // only way this backend's conformance was ever checked was somebody
    // remembering to look. It went unrun long enough for a check added *with*
    // a fix to have never been executed on the backend the fix was for.
    //
    // The same arrangement `tool/golden.sh` uses, for the same reason: Flutter
    // GPU needs Impeller, a headless `flutter test` does not enable it, so the
    // harness is an application and the exit code is how it reports. Held back
    // by `--dart-define=stay=true` when a person does want to read the list.
    if (const bool.fromEnvironment('stay')) return;
    // A frame first, so the report is on screen if anybody is watching, and so
    // the process does not exit from inside a post-frame callback.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(failed == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SingleChildScrollView(
        child: Text(
          _report,
          style: const TextStyle(
            color: Color(0xFFDDDDDD),
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      ),
    ),
  );
}
