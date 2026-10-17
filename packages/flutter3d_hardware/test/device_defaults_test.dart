/// What a device inherits for a member it does not override: the refusal
/// names the feature that member is actually gated by.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

/// Overrides nothing: every abstract member answers with a `StateError`.
final class _BareDevice extends GraphicsDevice {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} has no default body');
}

Matcher _refuses(DeviceFeature feature) => throwsA(
  isA<UnsupportedCapabilityException>().having(
    (UnsupportedCapabilityException e) => e.feature,
    'feature',
    feature,
  ),
);

void main() {
  test('reading a timestamp set is refused as timestamps', () async {
    // Mutation: refuse `occlusionQuery` for every set, as the default did,
    // and a device without timestamps names the wrong feature.
    final device = _BareDevice();
    final timestamps = wrapQuerySet(
      backend: Object(),
      type: QueryType.timestamp,
      count: 2,
    );
    await expectLater(
      device.readQueryResults(timestamps),
      _refuses(DeviceFeature.timestampQuery),
    );
    final occlusion = wrapQuerySet(
      backend: Object(),
      type: QueryType.occlusion,
      count: 2,
    );
    await expectLater(
      device.readQueryResults(occlusion),
      _refuses(DeviceFeature.occlusionQuery),
    );
  });

  test('a transfer pass is never refused; its copies are', () {
    // Mutation: refuse `bufferCopy` from `beginTransferPass`, as the default
    // did against its own doc, and a device with texture copies alone cannot
    // open the pass its copies go through.
    final transfer = _BareDevice().beginTransferPass();
    final buffer = wrapStorageBuffer(backend: Object(), lengthInBytes: 16);
    expect(
      () => transfer.copyBufferToBuffer(buffer, 0, buffer, 0, 4),
      _refuses(DeviceFeature.bufferCopy),
    );
    transfer.submit();
  });
}
