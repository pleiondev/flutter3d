/// The limits a WebGPU device is opened with, and the check and the record
/// that keep a pair over them from being refused every second.
///
///     flutter test test/webgpu_layout_limits_test.dart
///
/// **Found on the river demo, on WebGPU in Chrome on an M3.** An instanced
/// mesh stage beside the river's liquid material binds 9 uniform blocks,
/// every one with a dynamic offset; the device was opened without asking
/// for `maxDynamicUniformBuffersPerPipelineLayout`, so it kept WebGPU's 8
/// where the adapter had 10, and the browser refused the layouts. The pair
/// was made again each time the spray came back, so the refusal was thrown
/// about once a second and the spray never drew.
///
/// Pure Dart, so it runs on the VM: `open_test.dart` holds the same limits
/// against a real adapter in a browser.
@TestOn('vm')
library;

import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_layout_limits.dart';
import 'package:flutter3d_webgpu/src/webgpu_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

const WebGpuVisibility _both = (vertex: true, fragment: true);
const WebGpuVisibility _fragment = (vertex: false, fragment: true);

WebGpuBoundBlock _block(int group, int binding, WebGpuVisibility visibility) =>
    WebGpuBoundBlock(
      block: WebGpuBlock(
        name: 'Block${group}_$binding',
        group: group,
        binding: binding,
        sizeInBytes: 16,
        members: const <WebGpuBlockMember>[],
      ),
      visibility: visibility,
    );

WebGpuBoundSampler _sampler(int binding) => WebGpuBoundSampler(
  sampler: WebGpuSampler(
    name: 'map$binding',
    group: 1,
    textureBinding: binding,
    samplerBinding: binding + 1,
    dimension: WebGpuTextureDimension.twoDimensional,
  ),
  visibility: _fragment,
);

/// Nine blocks over two groups, the shape of the pair that was refused.
List<WebGpuGroupShape> _nineBlocks() => <WebGpuGroupShape>[
  WebGpuGroupShape(
    blocks: <WebGpuBoundBlock>[for (var b = 0; b < 4; b++) _block(0, b, _both)],
    samplers: const <WebGpuBoundSampler>[],
  ),
  WebGpuGroupShape(
    blocks: <WebGpuBoundBlock>[
      for (var b = 0; b < 5; b++) _block(1, b, _fragment),
    ],
    samplers: <WebGpuBoundSampler>[_sampler(10)],
  ),
];

/// WebGPU's guaranteed minimums.
const WebGpuLayoutLimits _minimums = (
  maxBindGroups: 4,
  maxDynamicUniformBuffersPerPipelineLayout: 8,
  maxUniformBuffersPerShaderStage: 12,
  maxSampledTexturesPerShaderStage: 16,
  maxSamplersPerShaderStage: 16,
);

/// What Chrome reported for the M3 Pro the refusal was found on.
const WebGpuLayoutLimits _m3 = (
  maxBindGroups: 4,
  maxDynamicUniformBuffersPerPipelineLayout: 10,
  maxUniformBuffersPerShaderStage: 12,
  maxSampledTexturesPerShaderStage: 16,
  maxSamplersPerShaderStage: 16,
);

void main() {
  group('the limits a device is opened with', () {
    // Mutation: drop a name from `webgpuRequestedLimits`, and the device
    // keeps WebGPU's minimum of that limit whatever the adapter has.
    test('include every limit a pipeline layout is held to', () {
      expect(
        webgpuRequestedLimits,
        containsAll(<String>[
          'maxDynamicUniformBuffersPerPipelineLayout',
          'maxBindGroups',
          'maxUniformBuffersPerShaderStage',
          'maxSampledTexturesPerShaderStage',
          'maxSamplersPerShaderStage',
          'maxStorageBuffersPerShaderStage',
          'maxStorageTexturesPerShaderStage',
        ]),
      );
      expect(
        webgpuRequestedLimits.toSet(),
        hasLength(webgpuRequestedLimits.length),
        reason: 'a limit named twice is a slip, not a request',
      );
    });
  });

  group('webgpuLayoutProblem', () {
    test('passes the pair of nine on an adapter that has ten', () {
      expect(webgpuLayoutProblem('A+B', _nineBlocks(), _m3), isNull);
    });

    test('names the limit a pair of nine is over at the minimum of eight', () {
      final problem = webgpuLayoutProblem(
        'MeshInstancedVertex+Liquid',
        _nineBlocks(),
        _minimums,
      );
      expect(problem, contains('MeshInstancedVertex+Liquid'));
      expect(problem, contains('9 uniform blocks with a dynamic offset'));
      expect(problem, contains('at most 8'));
      expect(problem, contains('maxDynamicUniformBuffersPerPipelineLayout'));
    });

    test('counts a block every stage sees once for the layout', () {
      final shape = <WebGpuGroupShape>[
        WebGpuGroupShape(
          blocks: <WebGpuBoundBlock>[
            for (var b = 0; b < 8; b++) _block(0, b, _both),
          ],
          samplers: const <WebGpuBoundSampler>[],
        ),
      ];
      expect(webgpuLayoutProblem('A+B', shape, _minimums), isNull);
    });

    test('counts bind groups', () {
      final shape = <WebGpuGroupShape>[
        for (var g = 0; g < 5; g++)
          const WebGpuGroupShape(
            blocks: <WebGpuBoundBlock>[],
            samplers: <WebGpuBoundSampler>[],
          ),
      ];
      expect(
        webgpuLayoutProblem('A+B', shape, _minimums),
        contains('maxBindGroups'),
      );
    });

    test('counts textures and samplers by the stage that sees them', () {
      final shape = <WebGpuGroupShape>[
        const WebGpuGroupShape(
          blocks: <WebGpuBoundBlock>[],
          samplers: <WebGpuBoundSampler>[],
        ),
        WebGpuGroupShape(
          blocks: const <WebGpuBoundBlock>[],
          samplers: <WebGpuBoundSampler>[
            for (var s = 0; s < 17; s++) _sampler(s * 2),
          ],
        ),
      ];
      final problem = webgpuLayoutProblem('A+B', shape, _minimums);
      expect(problem, contains('17 textures in its fragment stage'));
      expect(problem, contains('maxSampledTexturesPerShaderStage'));
    });
  });

  group('WebGpuLayoutRefusals', () {
    // Mutation: forget a refusal when the pipeline over the pair is given
    // back (keep it with the handle), and the second pipeline over the pair
    // is refused and reported again — the once-a-second refusal.
    test('keeps a refusal by the pair, across every handle over it', () {
      final refusals = WebGpuLayoutRefusals();
      final pair = Object();
      expect(refusals.isRefused(pair), isFalse);
      expect(refusals.tell(pair), isNull);

      refusals.refuse(pair, 'over maxDynamicUniformBuffersPerPipelineLayout');
      expect(refusals.isRefused(pair), isTrue);
      expect(
        refusals.reasonOf(pair),
        'over maxDynamicUniformBuffersPerPipelineLayout',
      );
    });

    test('tells a refusal once', () {
      final refusals = WebGpuLayoutRefusals();
      final pair = Object();
      refusals.refuse(pair, 'the first reason');
      expect(refusals.tell(pair), 'the first reason');
      expect(refusals.tell(pair), isNull);
      expect(refusals.tell(pair), isNull);
      expect(refusals.isRefused(pair), isTrue, reason: 'told, not forgotten');
    });

    test('keeps the first reason when a pair is refused again', () {
      final refusals = WebGpuLayoutRefusals();
      final pair = Object();
      refusals
        ..refuse(pair, 'over a limit, before the browser was asked')
        ..refuse(pair, 'the browser, about the invalid layout');
      expect(
        refusals.reasonOf(pair),
        'over a limit, before the browser was asked',
      );
      expect(refusals.length, 1);
    });

    test('a pair of new modules is a new pair', () {
      final refusals = WebGpuLayoutRefusals()..refuse(Object(), 'old modules');
      expect(refusals.isRefused(Object()), isFalse);
      refusals.clear();
      expect(refusals.length, 0);
    });
  });
}
