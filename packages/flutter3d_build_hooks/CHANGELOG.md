## 1.0.0-rc.1

- **Breaking: a generated material accessor is over a `MaterialParameters`**,
  the shape `RenderMaterial.parameters` has, and its `defaults()` answers
  one. A `vec3` or `vec4` uniform whose name says it is a colour says in
  its doc that the vector is the linear buffer the shader reads.
- **A material build asks the backends' own compilers.**
  `MaterialCompilers.registry` (and `MaterialCompilers.locate(registry:)`)
  holds a `MaterialCompilerRegistry`; `compileMaterial` hands each
  compiler the stages as GLSL, the engine's headers and the WebGPU stages
  it wrote, and puts its section in the bundle. A compiler whose section
  the build writes with a tool of its own (`isSectionWrittenByBuild`, Impeller's)
  and that refuses leaves the build's section; any other refusal fails the
  build. Without glslang and naga WebGPU's compiler is not asked, and the
  bundle goes without its section, as it does with no registry.
- **Stages that disagree fail the build as a `MaterialBuildException`**
  naming the source, where a `StageAgreementException` from a section
  writer used to escape as itself.
- **A material's own blocks and textures are numbered after the engine's
  in its WebGPU section**, in its slot table's order.
- **Depends on `flutter3d_foundation` instead of the plugin API**, for the
  exception family `MaterialBuildException` is of.

- **New: the material compiler a build hook needs, on its own.**
  `compileMaterial`, `MaterialCompilers`, `MaterialBuildException` and
  `generateMaterialAccessors` moved here from `flutter3d_build`, which still
  exports them under the same names. A package that compiles its own
  materials in its build hook, as `flutter3d_effects` does, depends on this
  and no longer resolves `flutter3d_build`'s converters, MCP servers and
  `dart_mcp` into every game that depends on it.
