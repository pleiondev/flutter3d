// The honesty check runs in the shader-free tier: a device with no stages
// yet is told which features could not be asked, and is not blamed for
// them.
import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// Lists nothing, prefers four samples, and answers every call it gates
/// with something other than a refusal.
final class _Boaster extends GraphicsDevice {
  @override
  DeviceFeatures get features => DeviceFeatures.none;

  @override
  int get preferredSampleCount => 4;

  @override
  ShaderLibrary get shaders =>
      FakeBackend(missingShaders: const <String>{'DebugLine'}).shaders;

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      TextureFormatSupport.none;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} is not refused');
}

ConformanceCheck _check(String name) =>
    conformanceChecks.firstWhere((c) => c.name == name);

const _honesty = 'every capability a device reports is honest';

void main() {
  test('a device without stages is not blamed for them', () async {
    // Mutation: drop the `hasStage` skip, and the sampler, storage and
    // uniform probes fail with "the DebugLine stage is missing", reported as
    // a dishonest feature report. The fake's report is wrong in other ways
    // (it answers every format), which is what lets this see the message.
    final device = FakeBackend(missingShaders: const <String>{'DebugLine'});
    await expectLater(
      _check(_honesty).run(device),
      throwsA(
        isA<ConformanceFailureException>().having(
          (e) => e.message,
          'message',
          allOf(
            isNot(contains('DebugLine')),
            isNot(contains('sampler-compare')),
            isNot(contains('uniform-bytes')),
            isNot(contains('render-stage-storage')),
          ),
        ),
      ),
    );
  });

  test('a sample count and a cube are asked like any feature', () async {
    // Mutation: drop the sample-count clause, or the cube probe (back in
    // `unprobedFeatures`), and a device that prefers four samples it cannot
    // allocate, or makes cubes it does not list, passes.
    await expectLater(
      _check(_honesty).run(_Boaster()),
      throwsA(
        isA<ConformanceFailureException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('preferredSampleCount is 4 without offscreen-multisample'),
            contains('cube-textures is not reported'),
          ),
        ),
      ),
    );
  });

  test('no check compares a getter with itself', () {
    // The pre-1.0 getters are gone since 1.0; a check that compared each
    // answer with itself printed a green line for nothing.
    expect(
      conformanceChecks.map((c) => c.name),
      isNot(contains('the pre-1.0 capability getters agree with features')),
    );
  });
}
