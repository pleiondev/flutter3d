import 'dart:math' as math;

import 'package:chemlab/chemlab.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a circular segment is none, half and all of the disc', () {
    expect(segmentArea(1, -1), 0.0);
    expect(segmentArea(1, 0), closeTo(math.pi / 2, 1e-12));
    expect(segmentArea(1, 1), closeTo(math.pi, 1e-12));
  });

  test('the volume under a tilted plane is the volume poured', () {
    final wall = tubeLiquidProfile(0.8).sublist(0, 9 + 1);
    final full = volumeUpTo(wall, 0.5);
    // Tipped by a radian, the plane that leaves the same volume under it.
    final up = Vector3(0, math.cos(1.0), -math.sin(1.0));
    final height = surfaceFor(wall, up, full);
    expect(volumeBelow(wall, up, height), closeTo(full, full * 1e-4));
    // And an upright vessel's level comes back from its volume.
    expect(levelFor(wall, full), closeTo(0.5, 1e-4));
  });

  test('sharing leaves the two tubes holding the same', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final from = bench.vessels[1];
    final to = bench.clean;
    final before = from.volumeAt(from.level);
    expect(to.empty, isTrue);
    expect(bench.canShare(from), isTrue);
    expect(bench.canShare(to), isFalse);

    bench.share(from);
    expect(bench.busy, isTrue);
    var seconds = 0.0;
    var streamed = false;
    while (bench.busy) {
      bench.step(1 / 60);
      seconds += 1 / 60;
      streamed |= bench.scene.root.children.any(
        (n) => n.name == 'stream' && n.visible,
      );
      expect(seconds, lessThan(20));
    }
    expect(streamed, isTrue);
    // Mutation: stop the pour at the start's volume, and nothing moves.
    final mine = from.volumeAt(from.level);
    final theirs = to.volumeAt(to.level);
    expect(mine, closeTo(before / 2, before * 0.01));
    expect(theirs, closeTo(before / 2, before * 0.01));
    expect(to.empty, isFalse);
    expect(to.liquid.visible, isTrue);
    // The poured tube is back where it stood, upright.
    expect(from.tilt, 0.0);
    expect(from.body.readPosition(), from.at);
    // And the clean tube holds the colour poured into it.
    expect(to.colour.r, closeTo(from.colour.r, 1e-6));
    expect(to.colour.g, closeTo(from.colour.g, 1e-6));
    expect(to.colour.b, closeTo(from.colour.b, 1e-6));
  });

  test('two solutions poured together take light away together', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final blue = bench.vessels[1];
    final orange = bench.vessels[3];
    final to = bench.clean;
    bench.share(blue);
    while (bench.busy) {
      bench.step(1 / 60);
    }
    final held = to.volumeAt(to.level);
    bench.share(orange);
    final added = (orange.volumeAt(orange.level) - held) / 2;
    while (bench.busy) {
      bench.step(1 / 60);
    }
    // Beer and Lambert: the mixture's absorption is the two weighed by
    // volume. Mutation: mix the colours themselves, and red comes out a
    // shade lighter than the absorptions give.
    double absorb(double c) => -math.log(c);
    final red = math.exp(
      -(absorb(blue.colour.r) * held + absorb(orange.colour.r) * added) /
          (held + added),
    );
    expect(to.colour.r, closeTo(red, 0.01));
  });

  test('the lip passes the flow it is asked to, and faster for more', () {
    final slow = overLip(flow: 2e-4, radius: 0.074, tilt: 1.6);
    final fast = overLip(flow: 1e-3, radius: 0.074, tilt: 1.6);
    // Mutation: drop the weir's three-halves power, and the head a flow
    // needs is wrong by a factor that grows with it.
    expect(fast.head, greaterThan(slow.head));
    expect(fast.speed, greaterThan(slow.speed));
    // Critical flow over the crest: a speed of about √(g · 2h/3).
    expect(slow.speed, closeTo(math.sqrt(9.81 * slow.head * 2 / 3), 0.15));
    expect(fast.width, lessThanOrEqualTo(2 * 0.074));
  });

  test('a pour goes in at the mouth, lip over the rim', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final from = bench.vessels[2];
    final to = bench.clean;
    bench.share(from);
    var checked = 0;
    while (bench.busy) {
      final before = from.volumeAt(from.level);
      bench.step(1 / 60);
      // While liquid is leaving the lip; the tail that falls after it may
      // be in the air as the tube goes back.
      if (from.volumeAt(from.level) < before - 1e-6) {
        // Mutation: hold the lip high over the middle again, and the stream
        // crosses the rim on its way down: the lip is outside the mouth.
        final lip = from.body.worldMatrix.transformed3(from.lip);
        final off = Vector2(lip.x - to.at.x, lip.z - to.at.z).length;
        expect(off, lessThan(to.lip.z));
        final rim = to.glass.map((p) => p.y).reduce(math.max);
        expect(lip.y, greaterThan(to.at.y + rim));
        expect(lip.y, lessThan(to.at.y + rim + 0.05));
        checked++;
      }
    }
    expect(checked, greaterThan(10));
  });

  test('what leaves the lip is in the air for a fall before it lands', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final from = bench.vessels[2];
    final to = bench.clean;
    final total = from.volumeAt(from.level);
    bench.share(from);
    var aloft = 0.0;
    var clock = 0.0;
    var lastPoured = 0.0;
    var lastSeen = 0.0;
    bool streamVisible() => bench.scene.root.children.any(
      (n) => n.name == 'stream' && n.visible,
    );
    while (bench.busy) {
      final before = from.volumeAt(from.level);
      bench.step(1 / 60);
      clock += 1 / 60;
      final mine = from.volumeAt(from.level);
      final theirs = to.volumeAt(to.level);
      // Nothing is made: the two tubes never hold more than there was.
      expect(mine + theirs, lessThanOrEqualTo(total * 1.002));
      aloft = math.max(aloft, total - mine - theirs);
      if (mine < before - 1e-12) lastPoured = clock;
      if (streamVisible()) lastSeen = clock;
    }
    expect(aloft, greaterThan(total * 0.02));
    // The last of it falls for a while after the last left the lip — and
    // then the stream is gone: within a fall, about a third of a second.
    // Mutation: fill the clean tube the moment liquid leaves the lip, and
    // nothing is ever in the air; drop the history, and the stream vanishes
    // the frame the pour stops.
    expect(lastSeen - lastPoured, greaterThan(0.05));
    expect(lastSeen - lastPoured, lessThan(0.5));
    // And by the end it has all landed.
    expect(
      from.volumeAt(from.level) + to.volumeAt(to.level),
      closeTo(total, total * 0.01),
    );
  });
}

