/// The instancing scale probe, run against whichever backend opens.
///
///     flutter run -d macos -t lib/instancing_scale_probe_main.dart
///
/// An application rather than a test because the number wanted is a real
/// device's, and a headless `flutter test` has none. What it measures and why
/// is on `InstancingScaleProbe`.
library;

import 'dart:io';

import 'package:flutter/material.dart' hide Material;

import 'instancing_scale_probe.dart';

void main() => runApp(const InstancingScaleProbeApp());

/// Runs the ladder, prints the table and leaves.
class InstancingScaleProbeApp extends StatefulWidget {
  /// Builds the application.
  const InstancingScaleProbeApp({super.key});

  @override
  State<InstancingScaleProbeApp> createState() =>
      _InstancingScaleProbeAppState();
}

class _InstancingScaleProbeAppState extends State<InstancingScaleProbeApp> {
  String? _report;

  Future<void> _done(InstancingScaleReport report) async {
    final String text = report.lines.join('\n');
    // ignore: avoid_print
    print(text);
    if (mounted) setState(() => _report = text);

    if (const bool.fromEnvironment('stay')) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(0);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: switch (_report) {
        null => InstancingScaleProbe(onDone: _done),
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
