/// Two hundred programs nobody wrote, each drawn against rewrites of itself
/// that must come out the same to the byte — `H4`.
///
///     dart test test/fuzz_test.dart
///
/// The software rasteriser against itself: a program and a rewrite that is
/// exact in IEEE 754 have to draw identical frames here, so any difference is
/// a finding, reported cut down to the draws that still show it. The seeds
/// are fixed, so a failure here is a failure every time and on every machine;
/// widening the set is a matter of changing the range.
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

GraphicsDevice _cpu({required int width, required int height}) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('a seed is always the same program', () {
    final a = generateFuzzProgram(17);
    final b = generateFuzzProgram(17);
    expect(a.width, b.width);
    expect(a.draws.length, b.draws.length);
    expect(a.draws.first.triangles.first.x, b.draws.first.triangles.first.x);
    expect(
      generateFuzzProgram(18).width == a.width &&
          generateFuzzProgram(18).draws.length == a.draws.length &&
          generateFuzzProgram(18).draws.first.triangles.first.x ==
              a.draws.first.triangles.first.x,
      isFalse,
    );
  });

  test('the seeds offer every kind of rewrite', () {
    // A generator that never produced two disjoint draws would leave the
    // swap untested and this suite green for the wrong reason.
    final kinds = <Type>{
      for (var seed = 0; seed < 200; seed++)
        for (final t in transformsFor(generateFuzzProgram(seed), seed))
          t.runtimeType,
    };
    expect(kinds, <Type>{SplitDraw, SwapDisjointDraws, FoldPowerOfTwo});
  });

  test('two hundred programs draw what their rewrites draw', () async {
    final findings = <FuzzFinding>[];
    for (var seed = 0; seed < 200; seed++) {
      for (final finding in await fuzzSeed(seed, _cpu)) {
        findings.add(await shrinkFinding(finding, _cpu));
      }
    }
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('the programs draw something', () async {
    // Two blank frames are identical too. A generator whose triangles all
    // landed off screen, or a probe stage that drew nothing, would make every
    // comparison above pass and mean nothing.
    var drawn = 0;
    for (var seed = 0; seed < 50; seed++) {
      final program = generateFuzzProgram(seed);
      final frame = await drawFuzzProgram(program, _cpu);
      final clear = <int>[for (final c in program.clear) (c * 255).round()];
      for (var i = 0; i < frame.length; i += 4) {
        if (frame[i] != clear[0] ||
            frame[i + 1] != clear[1] ||
            frame[i + 2] != clear[2]) {
          drawn++;
          break;
        }
      }
    }
    // Not all fifty: a program whose only draw is scissored to a sliver its
    // triangles miss, or tested `greater` against a depth cleared to one,
    // draws nothing, and that is a program worth having too. 44 of 50 do.
    expect(drawn, greaterThan(40));
  });

  test('the oracle can tell two frames apart', () async {
    // Swapping two draws that overlap under a blend that does not commute is
    // the mistake a disjointness test exists to prevent. The rewrite is not
    // offered, and drawn anyway it is a different frame — which is what the
    // comparison has to be able to see.
    const whole = ScreenRect(x: 0, y: 0, width: 8, height: 8);
    FuzzDraw quad(List<double> rgba) => FuzzDraw(
      viewport: whole,
      blend: const BlendState(
        sourceColorFactor: BlendFactor.sourceAlpha,
        destinationColorFactor: BlendFactor.oneMinusSourceAlpha,
      ),
      triangles: <({double x, double y, double z, List<double> rgba})>[
        (x: -1.0, y: -1.0, z: 0.5, rgba: rgba),
        (x: 3.0, y: -1.0, z: 0.5, rgba: rgba),
        (x: -1.0, y: 3.0, z: 0.5, rgba: rgba),
      ],
    );
    final program = FuzzProgram(
      width: 8,
      height: 8,
      clear: const <double>[0.0, 0.0, 0.0, 1.0],
      depth: false,
      draws: <FuzzDraw>[
        quad(const <double>[1.0, 0.0, 0.0, 0.5]),
        quad(const <double>[0.0, 0.0, 1.0, 0.5]),
      ],
    );
    expect(
      const SwapDisjointDraws(0).apply(program),
      isNull,
      reason: 'the two quads cover the same pixels, so this is not offered',
    );
    final swapped = program.withDraws(program.draws.reversed.toList());
    expect(
      await drawFuzzProgram(swapped, _cpu),
      isNot(await drawFuzzProgram(program, _cpu)),
    );
  });
}
