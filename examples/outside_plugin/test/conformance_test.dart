/// The plugin held to the plugin suite, as a plugin from anywhere is: under
/// the profile that runs its solver, and under the default one that leaves
/// it registered and off. The backends check installs and steps it on no
/// backend and on each of the four by name.
///
///     flutter test test/conformance_test.dart
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outside_plugin/outside_plugin.dart';

import 'scene.dart';

void main() {
  group('under its own profile', () {
    runPluginConformance(
      OutsidePlugin.new,
      harness: const PluginHarness(
        setUp: bounceBall,
        profile: warmingProfile,
        steps: 240,
      ),
    );
  });

  group('under the default profile', () {
    runPluginConformance(
      OutsidePlugin.new,
      harness: const PluginHarness(setUp: bounceBall, steps: 240),
    );
  });

  test('earns the badge under both', () {
    for (final profile in <SimulationProfile>[
      warmingProfile,
      SimulationProfile.deterministic,
    ]) {
      final outcomes = checkPluginConformance(
        OutsidePlugin.new,
        harness: PluginHarness(setUp: bounceBall, profile: profile, steps: 240),
      );
      expect(
        earnsBadge(outcomes),
        isTrue,
        reason: outcomes.where((o) => !o.passed).join('\n'),
      );
    }
  });
}
