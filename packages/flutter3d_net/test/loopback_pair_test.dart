import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

void main() {
  test('a loopback pair names its two ends by slot', () {
    final LoopbackPair pair = LoopbackWire.pair();
    expect(pair.first.slot, 0);
    expect(pair.second.slot, 1);
    final LoopbackPair(:first, :second) = LoopbackWire.pair(delaySteps: 1);
    expect(first.slot, isNot(second.slot));
  });
}
