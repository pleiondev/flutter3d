/// The sample plugin's render checks on Impeller.
///
///     dart run tool/build_bundle.dart
///     flutter run -d macos
///
/// An application rather than a test, for the reason the backend's own
/// conformance harness gives: Flutter GPU needs Impeller, which a headless
/// test does not enable. It prints a line a check, PASS, SKIP or FAIL, and
/// exits with 1 when one failed; `--dart-define=stay=true` keeps the list
/// on screen instead. `tool/render_conformance.sh` runs it and the browser
/// half together.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:flutter3d_plugin_runtime_example/acme_sample.dart';

import 'plugin_render_harness.dart';

void main() => runApp(const _RenderConformanceApp());

/// Runs the checks once the first frame is up, and shows what they said.
class _RenderConformanceApp extends StatefulWidget {
  const _RenderConformanceApp();

  @override
  State<_RenderConformanceApp> createState() => _RenderConformanceAppState();
}

class _RenderConformanceAppState extends State<_RenderConformanceApp> {
  String _report = 'running…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final log = StringBuffer();
    var failed = 0;
    var declined = 0;
    try {
      final bundle = await rootBundle.load(acmeSampleBundleAsset);
      final outcomes = await checkPluginRender(
        AcmeSamplePlugin.new,
        backend: 'impeller',
        points: acmeSamplePoints,
        device: () => GpuRenderBackend.open(width: 32, height: 32),
        materials: (GraphicsDevice device) => acmeSampleStages(device, bundle),
      );
      for (final outcome in outcomes) {
        final verdict = outcome.declined
            ? 'SKIP'
            : outcome.passed
            ? 'PASS'
            : 'FAIL';
        if (outcome.declined) declined++;
        if (!outcome.declined && !outcome.passed) failed++;
        log
          ..writeln('$verdict  ${outcome.check}')
          ..writeln('        ${outcome.says}');
      }
      log.writeln(
        '=== ${outcomes.length - failed - declined} passed, $failed failed, '
        '$declined declined on impeller ===',
      );
    } on Object catch (error, stack) {
      failed++;
      log
        ..writeln('FAIL  the checks could not run: $error')
        ..writeln(stack);
    }
    // ignore: avoid_print
    print(log);
    if (mounted) setState(() => _report = log.toString());
    if (const bool.fromEnvironment('stay')) return;
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
