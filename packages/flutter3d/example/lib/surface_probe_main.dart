/// The `GpuImageSurface` probe, run against Impeller.
///
///     flutter run -d macos -t lib/surface_probe_main.dart
///
/// Or `packages/flutter3d_impeller/tool/surface_probe.sh`, which runs this,
/// prints the report and returns its verdict. An application rather than a
/// test for the reason `conformance_main.dart` is one: Flutter GPU needs
/// Impeller, and a headless `flutter test` does not enable it. What it
/// measures and why is on `ImageSurfaceProbe`.
library;

import 'dart:io';

import 'package:flutter/material.dart' hide Material;

import 'surface_probe.dart';
import 'surface_probe_report.dart';

void main() => runApp(const SurfaceProbeApp());

class SurfaceProbeApp extends StatefulWidget {
  const SurfaceProbeApp({super.key});

  @override
  State<SurfaceProbeApp> createState() => _SurfaceProbeAppState();
}

class _SurfaceProbeAppState extends State<SurfaceProbeApp> {
  String? _report;

  Future<void> _done(SurfaceProbeReport report) async {
    final text = report.lines.join('\n');
    // ignore: avoid_print
    print(text);
    if (mounted) setState(() => _report = text);

    // And then leave, with the verdict as the code — the same arrangement as
    // `conformance_main.dart`, held back by `--dart-define=stay=true` when a
    // person wants to read the numbers on screen.
    if (const bool.fromEnvironment('stay')) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(report.failures == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: switch (_report) {
        null => ImageSurfaceProbe(onDone: _done),
        final String report => SingleChildScrollView(
          child: Text(
            report,
            style: const TextStyle(
              color: Color(0xFFDDDDDD),
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      },
    ),
  );
}
