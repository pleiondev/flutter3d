/// A texture node is read through a visitor, so a kind a later release adds
/// breaks no pass written against this one.
///
///     flutter test test/texture_node_visitor_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final nodes = <TextureNode>[
    const ImageTextureNode(id: 1, imageId: 0),
    ColorTextureNode(id: 2, value: Vector4(1, 1, 1, 1)),
    const BlendTextureNode(id: 3, factor: 0.5),
    const ChannelsTextureNode(id: 4, channel: TextureChannel.r),
    const LevelsTextureNode(id: 5),
    const InvertTextureNode(id: 6),
    UvTransformTextureNode(id: 7),
    CheckerTextureNode(id: 8),
    const NoiseTextureNode(id: 9),
    const NormalFromHeightTextureNode(id: 10),
    const OutputTextureNode(id: 11),
  ];

  test('every kind reaches the method named for it', () {
    // Mutation: point one kind's `accept` at another method, and its name
    // comes back wrong.
    expect(nodes.map((n) => n.accept(const _Names())).toList(), <String>[
      'image',
      'color',
      'blend',
      'channels',
      'levels',
      'invert',
      'uvTransform',
      'checker',
      'noise',
      'normalFromHeight',
      'output',
    ]);
  });

  test('a visitor that names no kind sees every node as unknown', () {
    expect(
      nodes.map((n) => n.accept(const _OnlyUnknown())).toList(),
      nodes.map((n) => n.id).toList(),
    );
  });

  test('a kind this visitor predates reaches visitUnknown', () {
    // A later release's twelfth kind, as a visitor written today meets it.
    expect(const _Later(id: 12).accept(const _Names()), 'unknown later');
  });
}

final class _Names extends TextureNodeVisitor<String> {
  const _Names();

  @override
  String visitImage(ImageTextureNode node) => 'image';
  @override
  String visitColor(ColorTextureNode node) => 'color';
  @override
  String visitBlend(BlendTextureNode node) => 'blend';
  @override
  String visitChannels(ChannelsTextureNode node) => 'channels';
  @override
  String visitLevels(LevelsTextureNode node) => 'levels';
  @override
  String visitInvert(InvertTextureNode node) => 'invert';
  @override
  String visitUvTransform(UvTransformTextureNode node) => 'uvTransform';
  @override
  String visitChecker(CheckerTextureNode node) => 'checker';
  @override
  String visitNoise(NoiseTextureNode node) => 'noise';
  @override
  String visitNormalFromHeight(NormalFromHeightTextureNode node) =>
      'normalFromHeight';
  @override
  String visitOutput(OutputTextureNode node) => 'output';
  @override
  String visitUnknown(TextureNode node) => 'unknown ${node.kind}';
}

final class _OnlyUnknown extends TextureNodeVisitor<int> {
  const _OnlyUnknown();

  @override
  int visitUnknown(TextureNode node) => node.id;
}

final class _Later extends TextureNode {
  const _Later({required super.id});

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs =>
      const <String, TextureInputSocket>{};

  @override
  Map<String, MaterialHint> get hints => const <String, MaterialHint>{};

  @override
  String get kind => 'later';

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};
}
