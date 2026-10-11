## 1.0.0-rc.1

- **A material build asks the backends' own compilers.**
  `MaterialCompilers.registry` (and `MaterialCompilers.locate(registry:)`)
  holds a `MaterialCompilerRegistry`; `compileMaterial` hands each
  compiler the stages as GLSL, the engine's headers and the WebGPU stages
  it wrote, and puts its section in the bundle. A compiler that refuses a
  section the build already wrote leaves it; one that refuses a section of
  its own fails the build.
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
