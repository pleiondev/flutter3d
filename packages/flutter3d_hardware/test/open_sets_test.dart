// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

/// The values, their names in order, the name of one, and `byName`.
typedef _OpenSet = (
  List<Object>,
  List<String>,
  String Function(Object),
  Object? Function(String),
);

void main() {
  final sets = <String, _OpenSet>{
    'BlendFactor': (
      BlendFactor.values,
      <String>[
        'zero',
        'one',
        'sourceColor',
        'oneMinusSourceColor',
        'sourceAlpha',
        'oneMinusSourceAlpha',
        'destinationColor',
        'oneMinusDestinationColor',
        'destinationAlpha',
        'oneMinusDestinationAlpha',
        'sourceAlphaSaturated',
        'blendColor',
        'oneMinusBlendColor',
        'blendAlpha',
        'oneMinusBlendAlpha',
        'source1Color',
        'oneMinusSource1Color',
        'source1Alpha',
        'oneMinusSource1Alpha',
      ],
      (v) => (v as BlendFactor).name,
      BlendFactor.byName,
    ),
    'BlendOperation': (
      BlendOperation.values,
      <String>['add', 'subtract', 'reverseSubtract', 'min', 'max'],
      (v) => (v as BlendOperation).name,
      BlendOperation.byName,
    ),
    'CullMode': (
      CullMode.values,
      <String>['none', 'frontFace', 'backFace'],
      (v) => (v as CullMode).name,
      CullMode.byName,
    ),
    'DepthRange': (
      DepthRange.values,
      <String>['zeroToOne', 'negativeOneToOne'],
      (v) => (v as DepthRange).name,
      DepthRange.byName,
    ),
    'FeatureStability': (
      FeatureStability.values,
      <String>['stable', 'reserved'],
      (v) => (v as FeatureStability).name,
      FeatureStability.byName,
    ),
    'GeometryUsage': (
      GeometryUsage.values,
      <String>['vertices', 'indices'],
      (v) => (v as GeometryUsage).name,
      GeometryUsage.byName,
    ),
    'IndexType': (
      IndexType.values,
      <String>['int16', 'int32'],
      (v) => (v as IndexType).name,
      IndexType.byName,
    ),
    'LoadAction': (
      LoadAction.values,
      <String>['dontCare', 'load', 'clear'],
      (v) => (v as LoadAction).name,
      LoadAction.byName,
    ),
    'MapMode': (
      MapMode.values,
      <String>['read', 'write'],
      (v) => (v as MapMode).name,
      MapMode.byName,
    ),
    'MinMagFilter': (
      MinMagFilter.values,
      <String>['nearest', 'linear'],
      (v) => (v as MinMagFilter).name,
      MinMagFilter.byName,
    ),
    'MipFilter': (
      MipFilter.values,
      <String>['nearest', 'linear'],
      (v) => (v as MipFilter).name,
      MipFilter.byName,
    ),
    'PipelineStatistic': (
      PipelineStatistic.values,
      <String>[
        'vertexShaderInvocations',
        'clipperInvocations',
        'clipperPrimitivesOut',
        'fragmentShaderInvocations',
        'computeShaderInvocations',
      ],
      (v) => (v as PipelineStatistic).name,
      PipelineStatistic.byName,
    ),
    'PolygonMode': (
      PolygonMode.values,
      <String>['fill', 'line'],
      (v) => (v as PolygonMode).name,
      PolygonMode.byName,
    ),
    'PrimitiveType': (
      PrimitiveType.values,
      <String>['triangle', 'triangleStrip', 'line', 'lineStrip', 'point'],
      (v) => (v as PrimitiveType).name,
      PrimitiveType.byName,
    ),
    'SamplerAddressMode': (
      SamplerAddressMode.values,
      <String>['clampToEdge', 'repeat', 'mirror'],
      (v) => (v as SamplerAddressMode).name,
      SamplerAddressMode.byName,
    ),
    'SamplerBorderColor': (
      SamplerBorderColor.values,
      <String>['transparentBlack', 'opaqueBlack', 'opaqueWhite'],
      (v) => (v as SamplerBorderColor).name,
      SamplerBorderColor.byName,
    ),
    'StencilOperation': (
      StencilOperation.values,
      <String>[
        'keep',
        'zero',
        'setToReferenceValue',
        'incrementClamp',
        'decrementClamp',
        'invert',
        'incrementWrap',
        'decrementWrap',
      ],
      (v) => (v as StencilOperation).name,
      StencilOperation.byName,
    ),
    'StorageMode': (
      StorageMode.values,
      <String>['hostVisible', 'devicePrivate', 'deviceTransient'],
      (v) => (v as StorageMode).name,
      StorageMode.byName,
    ),
    'StoreAction': (
      StoreAction.values,
      <String>[
        'dontCare',
        'store',
        'multisampleResolve',
        'storeAndMultisampleResolve',
      ],
      (v) => (v as StoreAction).name,
      StoreAction.byName,
    ),
    'TextureDimension': (
      TextureDimension.values,
      <String>['d1', 'd2', 'd2Array', 'd3', 'cube', 'cubeArray'],
      (v) => (v as TextureDimension).name,
      TextureDimension.byName,
    ),
    'TextureSampleKind': (
      TextureSampleKind.values,
      <String>['float', 'sint', 'uint', 'depth', 'stencil'],
      (v) => (v as TextureSampleKind).name,
      TextureSampleKind.byName,
    ),
    'TextureType': (
      TextureType.values,
      <String>[
        'texture2D',
        'texture2DMultisample',
        'textureCube',
        'textureExternalOES',
      ],
      (v) => (v as TextureType).name,
      TextureType.byName,
    ),
    'VertexStepMode': (
      VertexStepMode.values,
      <String>['vertex', 'instance'],
      (v) => (v as VertexStepMode).name,
      VertexStepMode.byName,
    ),
  };

  for (final MapEntry(key: type, value: (values, names, nameOf, byName))
      in sets.entries) {
    test('$type is an open class that keeps its wire names', () {
      expect(values.map(nameOf), names);
      for (final value in values) {
        expect(value, isNot(isA<Enum>()), reason: '$value');
        expect('$value', '$type.${nameOf(value)}');
        expect(byName(nameOf(value)), same(value));
      }
      expect(byName('not-a-$type'), isNull);
    });
  }
}
