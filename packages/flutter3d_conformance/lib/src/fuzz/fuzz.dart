/// Fuzzing a backend with programs it has never seen — `H4`.
///
/// The conformance checks ask questions somebody thought of. This asks the
/// ones nobody did: a seed becomes a program of passes and draws over the
/// probe stages every bundle ships (`DebugLineVertex`, `DebugLine`), with
/// viewports, scissors, blending and depth chosen at random, and the program
/// becomes a trace any device can replay.
///
/// **The oracle is the program against itself.** A random picture has no
/// reference, but a pair of programs that must draw the same picture does:
/// each [FuzzTransform] rewrites a program into one whose frame is, by
/// construction, identical to the byte — a draw split in two at a triangle
/// boundary, two draws that touch no common pixel drawn in the other order, a
/// power of two moved out of the vertices and into the matrix. A device that
/// draws the two differently has a bug, and [shrinkFinding] cuts the program
/// down to the draws that still show it.
///
/// Every step of the transforms is exact in IEEE 754 — splitting changes no
/// triangle, reordering is confined to disjoint pixels, and scaling by a power
/// of two only moves an exponent — so on the software rasteriser any
/// difference at all is a finding. Against a hardware backend the comparison
/// is to the software rasteriser's frame within the conformance tolerance,
/// which is the browser suites' half, in a 0.8 patch.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import '../../flutter3d_conformance.dart' show DeviceFactory;

/// A deterministic generator, the same on the VM and in a browser.
///
/// Park and Miller's minimal standard: every product stays below 2^53, so a
/// JavaScript number carries it exactly, where `dart:math`'s `Random` makes
/// no promise across platforms.
final class FuzzRandom {
  FuzzRandom(int seed) : _state = (seed % 2147483646) + 1;

  int _state;

  int _next() => _state = (_state * 48271) % 2147483647;

  /// An integer in `[0, n)`.
  int below(int n) => _next() % n;

  /// A double in `[lo, hi)`, on a grid of 1/1024 so a trace's numbers are
  /// short and every one of them is exact in single precision.
  double between(double lo, double hi) =>
      lo + (hi - lo) * (below(1024) / 1024.0);

  bool chance(int percent) => below(100) < percent;

  T pick<T>(List<T> from) => from[below(from.length)];
}

/// One vertex of a probe triangle: where, and what colour.
typedef FuzzVertex = ({double x, double y, double z, List<double> rgba});

/// A draw and the state it is drawn with.
final class FuzzDraw {
  const FuzzDraw({
    required this.viewport,
    required this.triangles,
    this.scissor,
    this.blend,
    this.depthWrite = false,
    this.depthCompare = CompareFunction.always,
    this.exponent = 0,
  });

  final ScreenRect viewport;
  final ScreenRect? scissor;
  final BlendState? blend;
  final bool depthWrite;
  final CompareFunction depthCompare;

  /// Three vertices per triangle, in the order they are drawn.
  final List<FuzzVertex> triangles;

  /// The vertices are stored times `2^exponent` and the matrix undoes it.
  final int exponent;

  int get triangleCount => triangles.length ~/ 3;

  FuzzDraw copyWith({List<FuzzVertex>? triangles, int? exponent}) => FuzzDraw(
    viewport: viewport,
    scissor: scissor,
    blend: blend,
    depthWrite: depthWrite,
    depthCompare: depthCompare,
    triangles: triangles ?? this.triangles,
    exponent: exponent ?? this.exponent,
  );
}

/// A pass over one colour target, and optionally a depth target.
final class FuzzProgram {
  const FuzzProgram({
    required this.width,
    required this.height,
    required this.clear,
    required this.depth,
    required this.draws,
  });

  final int width;
  final int height;
  final List<double> clear;
  final bool depth;
  final List<FuzzDraw> draws;

  FuzzProgram withDraws(List<FuzzDraw> draws) => FuzzProgram(
    width: width,
    height: height,
    clear: clear,
    depth: depth,
    draws: draws,
  );

  /// The program as a trace: create the targets, open one pass, draw, and
  /// read the colour target back.
  Trace toTrace({required TextureFormat depthFormat}) {
    final events = <TraceEvent>[
      TraceCreateTexture(
        id: 0,
        spec: RenderTargetSpec(
          width: width,
          height: height,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      ),
      if (depth)
        TraceCreateTexture(
          id: 1,
          spec: RenderTargetSpec(
            width: width,
            height: height,
            format: depthFormat,
          ),
        ),
      const TraceCreatePipeline(
        id: 2,
        vertex: 'DebugLineVertex',
        fragment: 'DebugLine',
      ),
      TraceBeginRenderPass(
        pass: 0,
        label: 'fuzz',
        colors: <TraceColorTarget>[
          (
            texture: 0,
            resolveTexture: null,
            loadAction: LoadAction.clear,
            storeAction: StoreAction.store,
            clearValue: Vector4(clear[0], clear[1], clear[2], clear[3]),
            face: 0,
            mipLevel: 0,
          ),
        ],
        depth: depth
            ? (
                texture: 1,
                clearValue: 1.0,
                loadAction: LoadAction.clear,
                storeAction: StoreAction.dontCare,
                stencilLoadAction: LoadAction.clear,
                stencilStoreAction: StoreAction.dontCare,
                stencilClearValue: 0,
              )
            : null,
      ),
      const TraceSetPrimitiveType(0, PrimitiveType.triangle),
      const TraceSetCullMode(0, CullMode.none),
    ];
    for (final draw in draws) {
      final scale = _powerOfTwo(draw.exponent);
      final inverse = _powerOfTwo(-draw.exponent);
      events
        ..add(TraceSetViewport(0, draw.viewport))
        ..add(
          TraceSetScissor(
            0,
            draw.scissor ??
                ScreenRect(x: 0, y: 0, width: width, height: height),
          ),
        )
        ..add(TraceSetBlend(0, draw.blend, 0))
        ..add(TraceSetDepthWrite(0, draw.depthWrite))
        ..add(TraceSetDepthCompare(0, draw.depthCompare))
        ..add(const TraceBindPipeline(0, 2))
        ..add(
          TraceBindUniformBlock(
            pass: 0,
            shader: 'DebugLineVertex',
            block: 'LineInfo',
            members: <String, Float32List>{
              'view_projection': Float32List.fromList(<double>[
                inverse, 0, 0, 0, //
                0, inverse, 0, 0, //
                0, 0, inverse, 0, //
                0, 0, 0, 1,
              ]),
            },
          ),
        )
        ..add(
          TraceBindVertexData(
            pass: 0,
            bytes: ByteData.sublistView(
              Float32List.fromList(<double>[
                for (final v in draw.triangles) ...<double>[
                  v.x * scale,
                  v.y * scale,
                  v.z * scale,
                  ...v.rgba,
                ],
              ]),
            ),
            vertexCount: draw.triangles.length,
          ),
        )
        ..add(
          TraceBindIndexData(
            pass: 0,
            bytes: ByteData.sublistView(
              Uint16List.fromList(<int>[
                for (var i = 0; i < draw.triangles.length; i++) i,
              ]),
            ),
            type: IndexType.int16,
            indexCount: draw.triangles.length,
          ),
        )
        ..add(const TraceDraw(0));
    }
    events
      ..add(const TraceSubmit(0))
      ..add(const TraceReadPixels(0));
    return Trace(events);
  }
}

double _powerOfTwo(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent.abs(); i++) {
    value = exponent > 0 ? value * 2.0 : value * 0.5;
  }
  return value;
}

/// The blend states a draw picks from: none, the two everyone uses, and one
/// that subtracts, which is where a backend's operation order shows.
const List<BlendState?> _blends = <BlendState?>[
  null,
  BlendState(
    sourceColorFactor: BlendFactor.sourceAlpha,
    destinationColorFactor: BlendFactor.oneMinusSourceAlpha,
    sourceAlphaFactor: BlendFactor.one,
    destinationAlphaFactor: BlendFactor.oneMinusSourceAlpha,
  ),
  BlendState(
    sourceColorFactor: BlendFactor.one,
    destinationColorFactor: BlendFactor.one,
    sourceAlphaFactor: BlendFactor.one,
    destinationAlphaFactor: BlendFactor.one,
  ),
  BlendState(
    colorOperation: BlendOperation.reverseSubtract,
    sourceColorFactor: BlendFactor.one,
    destinationColorFactor: BlendFactor.one,
  ),
];

/// A program from [seed], always the same one.
FuzzProgram generateFuzzProgram(int seed) {
  final random = FuzzRandom(seed);
  final width = 8 + random.below(25);
  final height = 8 + random.below(25);
  final depth = random.chance(50);

  ScreenRect rect({required bool whole}) {
    if (whole) return ScreenRect(x: 0, y: 0, width: width, height: height);
    final x = random.below(width);
    final y = random.below(height);
    return ScreenRect(
      x: x,
      y: y,
      width: 1 + random.below(width - x),
      height: 1 + random.below(height - y),
    );
  }

  FuzzVertex vertex() => (
    x: random.between(-1.25, 1.25),
    y: random.between(-1.25, 1.25),
    z: random.between(0.0, 1.0),
    rgba: <double>[for (var c = 0; c < 4; c++) random.below(256) / 255.0],
  );

  return FuzzProgram(
    width: width,
    height: height,
    clear: <double>[for (var c = 0; c < 3; c++) random.below(256) / 255.0, 1.0],
    depth: depth,
    draws: <FuzzDraw>[
      for (var d = 1 + random.below(6); d > 0; d--)
        FuzzDraw(
          viewport: rect(whole: random.chance(60)),
          scissor: random.chance(40) ? rect(whole: false) : null,
          blend: random.pick(_blends),
          depthWrite: depth && random.chance(60),
          depthCompare: depth
              ? random.pick(const <CompareFunction>[
                  CompareFunction.always,
                  CompareFunction.less,
                  CompareFunction.lessEqual,
                  CompareFunction.greater,
                ])
              : CompareFunction.always,
          triangles: <FuzzVertex>[
            for (var t = (1 + random.below(4)) * 3; t > 0; t--) vertex(),
          ],
        ),
    ],
  );
}

// ------------------------------------------------------------- transforms

/// A rewrite of a program into one that must draw the same bytes.
sealed class FuzzTransform {
  const FuzzTransform();

  /// The draws this transform reads, which the shrinker has to keep.
  Set<int> get involves;

  /// The rewritten program, or null when this transform does not apply to
  /// [program].
  FuzzProgram? apply(FuzzProgram program);
}

/// Draw [draw]'s first [at] triangles, then the rest, as two draws with the
/// same state. The same triangles in the same order.
final class SplitDraw extends FuzzTransform {
  const SplitDraw(this.draw, this.at);
  final int draw;
  final int at;
  @override
  Set<int> get involves => <int>{draw};
  @override
  FuzzProgram? apply(FuzzProgram program) {
    if (draw >= program.draws.length) return null;
    final d = program.draws[draw];
    if (at <= 0 || at >= d.triangleCount) return null;
    return program.withDraws(<FuzzDraw>[
      ...program.draws.take(draw),
      d.copyWith(triangles: d.triangles.sublist(0, at * 3)),
      d.copyWith(triangles: d.triangles.sublist(at * 3)),
      ...program.draws.skip(draw + 1),
    ]);
  }

  @override
  String toString() => 'split draw $draw after triangle $at';
}

/// Draw [draw] and the one after it in the other order, where no pixel is
/// touched by both.
final class SwapDisjointDraws extends FuzzTransform {
  const SwapDisjointDraws(this.draw);
  final int draw;
  @override
  Set<int> get involves => <int>{draw, draw + 1};
  @override
  FuzzProgram? apply(FuzzProgram program) {
    if (draw + 1 >= program.draws.length) return null;
    final a = program.draws[draw];
    final b = program.draws[draw + 1];
    final aBox = _coverage(a, program);
    final bBox = _coverage(b, program);
    if (aBox == null || bBox == null || _overlap(aBox, bBox)) {
      // Nothing drawn by one of them is trivially disjoint, and swapping it
      // is still exact — but it tests nothing, so it is not offered.
      return null;
    }
    return program.withDraws(<FuzzDraw>[
      ...program.draws.take(draw),
      b,
      a,
      ...program.draws.skip(draw + 2),
    ]);
  }

  @override
  String toString() => 'swap draws $draw and ${draw + 1}';
}

/// Store draw [draw]'s positions times `2^exponent` and put `2^-exponent`
/// into its matrix. Both are exact, so clip space does not move by a bit.
final class FoldPowerOfTwo extends FuzzTransform {
  const FoldPowerOfTwo(this.draw, this.exponent);
  final int draw;
  final int exponent;
  @override
  Set<int> get involves => <int>{draw};
  @override
  FuzzProgram? apply(FuzzProgram program) {
    if (draw >= program.draws.length || exponent == 0) return null;
    return program.withDraws(<FuzzDraw>[
      for (var i = 0; i < program.draws.length; i++)
        i == draw
            ? program.draws[i].copyWith(
                exponent: program.draws[i].exponent + exponent,
              )
            : program.draws[i],
    ]);
  }

  @override
  String toString() => 'fold 2^$exponent into draw $draw';
}

/// Every transform [program] offers, in a fixed order.
List<FuzzTransform> transformsFor(FuzzProgram program, int seed) {
  final random = FuzzRandom(seed ^ 0x5eed);
  return <FuzzTransform>[
    for (var d = 0; d < program.draws.length; d++) ...<FuzzTransform>[
      if (program.draws[d].triangleCount > 1)
        SplitDraw(d, 1 + random.below(program.draws[d].triangleCount - 1)),
      SwapDisjointDraws(d),
      FoldPowerOfTwo(d, random.pick(const <int>[-3, -1, 2, 5])),
    ],
  ].where((t) => t.apply(program) != null).toList();
}

/// Where [draw] can touch pixels: the bounding box of its triangles in
/// pixels, clipped to its viewport, its scissor and the target, and grown by
/// two pixels each way — and mirrored vertically too, since a backend whose
/// row zero is the bottom maps the same triangle to the other half.
/// Conservative on purpose: calling two draws disjoint that are not would
/// make an honest backend fail.
(int, int, int, int)? _coverage(FuzzDraw draw, FuzzProgram program) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  final v = draw.viewport;
  for (final p in draw.triangles) {
    final x = v.x + (p.x + 1.0) * 0.5 * v.width;
    final y = v.y + (1.0 - p.y) * 0.5 * v.height;
    final mirrored = v.y + (p.y + 1.0) * 0.5 * v.height;
    for (final yy in <double>[y, mirrored]) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (yy < minY) minY = yy;
      if (yy > maxY) maxY = yy;
    }
  }
  var x0 = minX.floor() - 2;
  var y0 = minY.floor() - 2;
  var x1 = maxX.ceil() + 2;
  var y1 = maxY.ceil() + 2;
  final clips = <ScreenRect>[
    v,
    ?draw.scissor,
    ScreenRect(x: 0, y: 0, width: program.width, height: program.height),
  ];
  for (final c in clips) {
    if (x0 < c.x) x0 = c.x;
    if (y0 < c.y) y0 = c.y;
    if (x1 > c.x + c.width) x1 = c.x + c.width;
    if (y1 > c.y + c.height) y1 = c.y + c.height;
  }
  if (x0 >= x1 || y0 >= y1) return null;
  return (x0, y0, x1, y1);
}

bool _overlap((int, int, int, int) a, (int, int, int, int) b) =>
    a.$1 < b.$3 && b.$1 < a.$3 && a.$2 < b.$4 && b.$2 < a.$4;

// ---------------------------------------------------------------- running

/// A program and a rewrite of it that a device drew differently.
final class FuzzFinding {
  const FuzzFinding({
    required this.seed,
    required this.program,
    required this.transform,
    required this.differingBytes,
  });

  final int seed;
  final FuzzProgram program;
  final FuzzTransform transform;
  final int differingBytes;

  @override
  String toString() =>
      'seed $seed: ${program.draws.length} draws on a '
      '${program.width}x${program.height} target, and "$transform" changed '
      '$differingBytes bytes of the frame';
}

/// Draws [seed]'s program and each of its rewrites on fresh devices from
/// [makeDevice] and returns the rewrites that came out different.
Future<List<FuzzFinding>> fuzzSeed(int seed, DeviceFactory makeDevice) async {
  final program = generateFuzzProgram(seed);
  final original = await _draw(program, makeDevice);
  return <FuzzFinding>[
    for (final transform in transformsFor(program, seed))
      if (_differing(
            original,
            await _draw(transform.apply(program)!, makeDevice),
          )
          case final int bytes when bytes > 0)
        FuzzFinding(
          seed: seed,
          program: program,
          transform: transform,
          differingBytes: bytes,
        ),
  ];
}

/// [finding]'s program cut down to the draws that still show it: delta
/// debugging over every draw its transform does not read.
///
/// Draws are removed from the end of the list inwards so the indices the
/// transform names stay put; a removal that makes the difference go away is
/// put back.
Future<FuzzFinding> shrinkFinding(
  FuzzFinding finding,
  DeviceFactory makeDevice,
) async {
  var program = finding.program;
  var bytes = finding.differingBytes;
  final keep = finding.transform.involves;
  for (var i = program.draws.length - 1; i >= 0; i--) {
    if (keep.contains(i)) continue;
    if (keep.any((k) => k > i)) continue;
    final candidate = program.withDraws(<FuzzDraw>[
      for (var j = 0; j < program.draws.length; j++)
        if (j != i) program.draws[j],
    ]);
    final rewritten = finding.transform.apply(candidate);
    if (rewritten == null) continue;
    final differing = _differing(
      await _draw(candidate, makeDevice),
      await _draw(rewritten, makeDevice),
    );
    if (differing > 0) {
      program = candidate;
      bytes = differing;
    }
  }
  return FuzzFinding(
    seed: finding.seed,
    program: program,
    transform: finding.transform,
    differingBytes: bytes,
  );
}

/// How far one device's frame for [seed]'s program is from a reference
/// device's — `H4`'s other oracle, for a backend whose rounding is its own.
///
/// The fraction of pixels in which any channel differs by more than
/// [threshold] steps. A hardware backend is not held to the software
/// rasteriser's bytes, only to its picture: edge coverage and blending round
/// differently from one driver to the next, and a threshold of a few steps is
/// where the cross-backend golden tests draw the same line.
Future<double> fuzzDifference(
  int seed, {
  required DeviceFactory device,
  required DeviceFactory reference,
  int threshold = 8,
}) async {
  final program = generateFuzzProgram(seed);
  final a = await _draw(program, device);
  final b = await _draw(program, reference);
  var differing = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 4; c++) {
      if ((a[i + c] - b[i + c]).abs() > threshold) {
        differing++;
        break;
      }
    }
  }
  return differing / (a.length / 4);
}

/// The frame [program] draws on a fresh device from [makeDevice], as
/// premultiplied RGBA8 rows from the top.
Future<Uint8List> drawFuzzProgram(
  FuzzProgram program,
  DeviceFactory makeDevice,
) => _draw(program, makeDevice);

Future<Uint8List> _draw(FuzzProgram program, DeviceFactory makeDevice) async {
  final device = await makeDevice(width: program.width, height: program.height);
  final replay = await replayTrace(
    program.toTrace(depthFormat: device.defaultDepthStencilFormat),
    device,
  );
  final pixels = replay.pixels.single!;
  return pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);
}

int _differing(Uint8List a, Uint8List b) {
  if (a.length != b.length) return a.length > b.length ? a.length : b.length;
  var count = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) count++;
  }
  return count;
}
