/// The conformance checks, run against Impeller.
///
///     flutter run -d macos -t lib/conformance_main.dart
///
/// The WebGL backend runs the same list under `flutter test --platform chrome`.
/// This one cannot: Flutter GPU needs Impeller enabled, which a headless test
/// does not provide. Same checks, two harnesses — which is why they are a list
/// of functions and not a file of `test()` calls.
library;

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
        await check.run(GpuRenderBackend.create());
        log.writeln('PASS  ${check.name}');
      } catch (error) {
        failed++;
        log.writeln('FAIL  ${check.name}');
        log.writeln('        $error');
      }
    }
    log.writeln('=== ${conformanceChecks.length - failed} passed, '
        '$failed failed ===');
    // ignore: avoid_print
    print(log);
    setState(() => _report = log.toString());
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
