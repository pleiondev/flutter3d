/// The material language's own words and the names it keeps from a
/// source, each with the version it arrived in — 1.0.
///
/// **What `api/material_language.vocabulary` is written from**, beside the
/// inputs and builtins of `material_ast.dart`: a word or a reservation that
/// a later version adds is written here with that version, so a source of
/// an older one keeps reading as it did, and the structure rule that holds
/// the vocabulary to the base recorded at the tag sees it arrive with a
/// version above the base's newest.
///
/// Not exported: the parser reads these, and the vocabulary snapshot is
/// what an author or a tool outside the engine reads.
library;

/// The words that open a declaration, a block or a kind, or that a block's
/// grammar reads, by the version that brought each.
///
/// The `state` block's settings, its `blend` and `depthCompare` words and
/// an `updates` block's verbs are listed here too, with their own versions:
/// `materialDepthCompares` and `MaterialBlend.all` are what the parser
/// reads them from, and the vocabulary writes each with this table's
/// version for its setting.
const Map<String, int> materialWordVersions = <String, int>{
  // The header and the kinds.
  'f3dmat': 1,
  'material': 1,
  'fullscreen': 2,
  'compute': 2,
  // Declarations.
  'param': 1,
  'uniform': 1,
  'texture': 1,
  'lighttype': 3,
  'version': 3,
  // Blocks.
  'fragment': 1,
  'light': 1,
  'state': 2,
  'vertex': 2,
  'ambient': 2,
  'composite': 2,
  'workgroup': 2,
  'kernel': 2,
  'updates': 3,
  // Statements.
  'let': 1,
  'return': 1,
  'out': 2,
  'sample': 1,
  // The `state` block's settings and its two switch words.
  'blend': 2,
  'cutoff': 2,
  'depthWrite': 2,
  'depthTest': 2,
  'depthCompare': 2,
  'alphaToCoverage': 2,
  'doubleSided': 2,
  'depthLayer': 2,
  'effectsDepth': 2,
  'environment': 2,
  'directional': 2,
  'on': 2,
  'off': 2,
  // An `updates` block's verbs.
  'rename': 3,
  'scale': 3,
  'remove': 3,
};

/// The emitter's own names and `surface.glsl`'s, which a `let` or a
/// `uniform` would collide with once the stage is written: `s` and
/// `result` are the emitter's locals, the `v_…` varyings are what the
/// `uv` and `world` inputs are written as. Taken in every version.
const Set<String> materialEmitterNames = <String>{
  // The emitter's own, `P8`'s uniform block among them.
  's', 'result', 'main', 'material_params', 'MaterialParams', 'light', 'lit',
  // `surface.glsl`'s, as the emitted shader spells them.
  'Surface', 'LightSample', 'ReadSurface', 'WriteSurface', 'ShadeLight',
  'LightVisibility', 'v_texcoord', 'v_world_position', 'AccumulateLights',
  'ShadowFactor', 'ApplyCommonMaps', 'SampleLightmap',
};

/// Every keyword and every word reserved for future use of GLSL 4.60 (with
/// its Vulkan words) and GLSL ES 3.00, which the emitted stage is compiled
/// as and translated to. Taken from a `let`, a `uniform` and a full-screen
/// stage's texture in every version.
///
/// **Every version, not from the next one.** A material binding one of
/// these never compiled on a GPU: glslang refused it with its own message
/// rather than a line and column in the source, and only the software
/// backend and a translator that renames locals ran it. Refusing it in the
/// parser takes nothing from a source that ever drew on a GPU.
const Set<String> materialGlslWords = <String>{
  // Storage, layout, interpolation and precision qualifiers.
  'const', 'uniform', 'buffer', 'shared', 'attribute', 'varying',
  'coherent', 'volatile', 'restrict', 'readonly', 'writeonly', 'layout',
  'centroid', 'flat', 'smooth', 'noperspective', 'patch', 'sample',
  'invariant', 'precise', 'subroutine', 'in', 'out', 'inout', 'lowp',
  'mediump', 'highp', 'precision',
  // Control flow.
  'break', 'continue', 'do', 'for', 'while', 'switch', 'case', 'default',
  'if', 'else', 'discard', 'return',
  // Scalar, vector and matrix types.
  'void', 'bool', 'int', 'uint', 'float', 'double', 'true', 'false',
  'vec2', 'vec3', 'vec4', 'ivec2', 'ivec3', 'ivec4', 'bvec2', 'bvec3',
  'bvec4', 'uvec2', 'uvec3', 'uvec4', 'dvec2', 'dvec3', 'dvec4', 'mat2',
  'mat3', 'mat4', 'mat2x2', 'mat2x3', 'mat2x4', 'mat3x2', 'mat3x3',
  'mat3x4', 'mat4x2', 'mat4x3', 'mat4x4', 'dmat2', 'dmat3', 'dmat4',
  'dmat2x2', 'dmat2x3', 'dmat2x4', 'dmat3x2', 'dmat3x3', 'dmat3x4',
  'dmat4x2', 'dmat4x3', 'dmat4x4', 'atomic_uint', 'struct',
  // Samplers.
  'sampler1D', 'sampler1DShadow', 'sampler1DArray', 'sampler1DArrayShadow',
  'isampler1D', 'isampler1DArray', 'usampler1D', 'usampler1DArray',
  'sampler2D', 'sampler2DShadow', 'sampler2DArray', 'sampler2DArrayShadow',
  'isampler2D', 'isampler2DArray', 'usampler2D', 'usampler2DArray',
  'sampler2DRect', 'sampler2DRectShadow', 'isampler2DRect',
  'usampler2DRect', 'sampler2DMS', 'isampler2DMS', 'usampler2DMS',
  'sampler2DMSArray', 'isampler2DMSArray', 'usampler2DMSArray', 'sampler3D',
  'isampler3D', 'usampler3D', 'samplerCube', 'samplerCubeShadow',
  'isamplerCube', 'usamplerCube', 'samplerCubeArray',
  'samplerCubeArrayShadow', 'isamplerCubeArray', 'usamplerCubeArray',
  'samplerBuffer', 'isamplerBuffer', 'usamplerBuffer',
  // Images.
  'image1D', 'iimage1D', 'uimage1D', 'image1DArray', 'iimage1DArray',
  'uimage1DArray', 'image2D', 'iimage2D', 'uimage2D', 'image2DArray',
  'iimage2DArray', 'uimage2DArray', 'image2DRect', 'iimage2DRect',
  'uimage2DRect', 'image2DMS', 'iimage2DMS', 'uimage2DMS', 'image2DMSArray',
  'iimage2DMSArray', 'uimage2DMSArray', 'image3D', 'iimage3D', 'uimage3D',
  'imageCube', 'iimageCube', 'uimageCube', 'imageCubeArray',
  'iimageCubeArray', 'uimageCubeArray', 'imageBuffer', 'iimageBuffer',
  'uimageBuffer',
  // GLSL 4.60 for Vulkan, which glslang reads the engine's stages as.
  'texture1D', 'texture1DArray', 'itexture1D', 'itexture1DArray',
  'utexture1D', 'utexture1DArray', 'texture2D', 'texture2DArray',
  'itexture2D', 'itexture2DArray', 'utexture2D', 'utexture2DArray',
  'texture2DRect', 'itexture2DRect', 'utexture2DRect', 'texture2DMS',
  'itexture2DMS', 'utexture2DMS', 'texture2DMSArray', 'itexture2DMSArray',
  'utexture2DMSArray', 'texture3D', 'itexture3D', 'utexture3D',
  'textureCube', 'itextureCube', 'utextureCube', 'textureCubeArray',
  'itextureCubeArray', 'utextureCubeArray', 'textureBuffer',
  'itextureBuffer', 'utextureBuffer', 'sampler', 'samplerShadow',
  'subpassInput', 'isubpassInput', 'usubpassInput', 'subpassInputMS',
  'isubpassInputMS', 'usubpassInputMS',
  // Reserved for future use, in 4.60 and in ES 3.00.
  'common', 'partition', 'active', 'asm', 'class', 'union', 'enum',
  'typedef', 'template', 'this', 'resource', 'goto', 'inline', 'noinline',
  'public', 'static', 'extern', 'external', 'interface', 'long', 'short',
  'half', 'fixed', 'unsigned', 'superp', 'input', 'output', 'hvec2',
  'hvec3', 'hvec4', 'fvec2', 'fvec3', 'fvec4', 'filter', 'sizeof', 'cast',
  'namespace', 'using', 'sampler3DRect',
  // The one builtin the emitter calls that a material does not.
  'texture',
};

/// Names a `let` in a `vertex` block cannot take, from version 2, when the
/// block arrived: the vertex stage's own attributes and blocks, which the
/// emitted `main` reads under these names.
const Set<String> materialVertexReservedNames = <String>{
  'texcoord',
  'tangent',
  'joints',
  'weights',
  'frame_info',
  'FrameInfo',
  'skin_info',
  'SkinInfo',
  'material_vertex_info',
  'MaterialVertexInfo',
  'v_normal',
  'v_tangent',
  'v_color',
  'v_lightmap_uv',
  'v_instance',
  'ApplyMorph',
  'JointIndex',
  'SkinMatrix',
};

/// Names a version 2 stage declares besides [materialEmitterNames]: the
/// blocks and samplers a full-screen stage, a compute kernel and the
/// scene's depth are read through. Taken from version 2.
const Set<String> materialVersion2ReservedNames = <String>{
  'v_uv',
  'frag_color',
  'scene_texture',
  'surface_texture',
  'scene_depth_texture',
  'SceneDepthInfo',
  'scene_depth_info',
  'target',
  'image2D',
  'imageStore',
  'textureLod',
  'ShadeAmbient',
  'ShadeComposite',
  'MaterialLights',
};

/// Names the instanced and lightmapped vertex stages declare, which a `let`
/// in a `vertex` block cannot take from version 3, when those stages
/// arrived; a version 2 source keeps every name it had.
const Set<String> materialVariantReservedNames = <String>{
  'i_row0',
  'i_row1',
  'i_row2',
  'i_color',
  'i_data',
  'ApplyMorphInstanced',
  'F3dInstanceIndex',
  'morph_instance_weights',
  'MorphInstanceInfo',
};

/// Names a `let` cannot take from version 3: the light row's struct.
const Set<String> materialVersion3ReservedNames = <String>{'F3dLightRow'};

/// Prefixes a `let` cannot start with, by the version that took each:
/// GLSL's own in every version, the generated stage's from version 2.
const Map<String, int> materialReservedPrefixes = <String, int>{
  'gl_': 1,
  'f3d_': 2,
};
