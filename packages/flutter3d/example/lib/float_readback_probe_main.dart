/// The float-readback probe, run against Impeller.
///
///     flutter run -d macos -t lib/float_readback_probe_main.dart
///
/// An application rather than a test for the reason `conformance_main.dart` is
/// one: Flutter GPU needs Impeller, and a headless `flutter test` does not
/// enable it. What it measures and why is on `FloatReadbackProbe`.
library;

import 'dart:io';

import 'package:flutter/material.dart' hide Material;

import 'float_readback_probe.dart';

void main() => runApp(const FloatReadbackProbeApp());

/// Runs the probe, prints the report and leaves with the verdict as the code.
class FloatReadbackProbeApp extends StatefulWidget {
  /// Builds the application.
  const FloatReadbackProbeApp({super.key});

  @override
  State<FloatReadbackProbeApp> createState() => _FloatReadbackProbeAppState();
}

class _FloatReadbackProbeAppState extends State<FloatReadbackProbeApp> {
  String? _report;

  Future<void> _done(FloatReadbackReport report) async {
    final String text = report.lines.join('\n');
    // ignore: avoid_print
    print(text);
    if (mounted) setState(() => _report = text);

    if (const bool.fromEnvironment('stay')) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(report.failures == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: switch (_report) {
        null => FloatReadbackProbe(onDone: _done),
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
