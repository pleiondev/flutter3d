/// The rasteriser state a pass is configured with, as one value.
///
/// Twelve places in this engine open-code the same block of `setViewport`,
/// `setScissor`, `setPrimitiveType`, `setCullMode`, `setBlend`,
/// `setDepthWrite`, `setDepthCompare`. Repeated state is where a whole class of
/// bug lives: the one that cost a session was `setDepthWrite(false)` being a
/// no-op on one backend, and it was invisible partly because there was no one
/// place to read what a pass was actually asking for.
///
/// **Every field is optional, and that is a correctness requirement rather than
/// a convenience.** The three backends disagree about what an *omitted* call
/// means, in three directions:
///
/// - On Impeller and the software backend, any `setDepthWrite` call turns depth
///   writes **on** — `flutter_gpu`'s native setter ignores its argument, and
///   `flutter3d_cpu` mirrors that deliberately. So emitting a redundant
///   `setDepthWrite(false)` where a site today emits nothing flips behaviour.
/// - On WebGL the setters are immediate calls against global GL state, and
///   `beginRenderPass` re-enables only depth test and scissor. An omitted field
///   inherits whatever the previous pass left.
///
/// So the omissions in a pass's sequence are load-bearing, and a value object
/// with non-nullable fields and defaults would quietly change several passes.
/// Unset means *emit nothing*.
///
/// **No backend implements anything for this.** [PassStateApply] is an
/// extension, statically dispatched, built only from types this package already
/// promises. A virtual `setState` on [PassEncoder] would be a member two of the
/// three backends implement by fanning out to setters they already have — an
/// interface member that is a guess about a backend nobody has written.
///
/// It lives here rather than in the engine because of the backend that does not
/// exist yet: a Vulkan-shaped one has to accumulate this state and look a
/// pipeline up at `draw()`, and that needs something hashable to accumulate
/// into. Hence value equality, and hence this file.
library;

import 'command_encoder.dart';
import 'formats.dart';

/// Distinguishes "leave blending alone" from "turn blending off".
///
/// `setBlend(null)` disables blending and is a thing several passes want, so a
/// plain `BlendState?` cannot say which of the two was meant. A sentinel keeps
/// the natural spelling for both: omit the argument to say nothing, pass null
/// to say off.
const Object _unsetBlend = Object();

/// A pass's rasteriser state. Unset fields are not emitted.
final class PassState {
  const PassState({
    this.viewport,
    this.scissor,
    this.primitiveType,
    this.polygonMode,
    this.cullMode,
    this.windingOrder,
    Object? blend = _unsetBlend,
    this.blendAttachment = 0,
    this.depthWrite,
    this.depthCompare,
  })  : blend = identical(blend, _unsetBlend) ? null : blend as BlendState?,
        setsBlend = !identical(blend, _unsetBlend);

  final ScreenRect? viewport;
  final ScreenRect? scissor;
  final PrimitiveType? primitiveType;
  final PolygonMode? polygonMode;
  final CullMode? cullMode;
  final WindingOrder? windingOrder;

  /// What blending to set, when [setsBlend]. Null with [setsBlend] means off.
  final BlendState? blend;

  /// Whether blending is mentioned at all. False leaves the pass's alone.
  final bool setsBlend;

  final int blendAttachment;

  final bool? depthWrite;
  final CompareFunction? depthCompare;

  /// This state with some fields replaced.
  ///
  /// Cannot clear a field: passing null means "leave it as it was", which is
  /// what every `copyWith` in this repository means. A state that needs a field
  /// unset is a different constant, and naming it is better than clearing one.
  PassState copyWith({
    ScreenRect? viewport,
    ScreenRect? scissor,
    PrimitiveType? primitiveType,
    PolygonMode? polygonMode,
    CullMode? cullMode,
    WindingOrder? windingOrder,
    Object? blend = _unsetBlend,
    int? blendAttachment,
    bool? depthWrite,
    CompareFunction? depthCompare,
  }) =>
      PassState(
        viewport: viewport ?? this.viewport,
        scissor: scissor ?? this.scissor,
        primitiveType: primitiveType ?? this.primitiveType,
        polygonMode: polygonMode ?? this.polygonMode,
        cullMode: cullMode ?? this.cullMode,
        windingOrder: windingOrder ?? this.windingOrder,
        blend: identical(blend, _unsetBlend)
            ? (setsBlend ? this.blend : _unsetBlend)
            : blend,
        blendAttachment: blendAttachment ?? this.blendAttachment,
        depthWrite: depthWrite ?? this.depthWrite,
        depthCompare: depthCompare ?? this.depthCompare,
      );

  @override
  bool operator ==(Object other) =>
      other is PassState &&
      other.viewport == viewport &&
      other.scissor == scissor &&
      other.primitiveType == primitiveType &&
      other.polygonMode == polygonMode &&
      other.cullMode == cullMode &&
      other.windingOrder == windingOrder &&
      other.blend == blend &&
      other.setsBlend == setsBlend &&
      other.blendAttachment == blendAttachment &&
      other.depthWrite == depthWrite &&
      other.depthCompare == depthCompare;

  @override
  int get hashCode => Object.hash(viewport, scissor, primitiveType, polygonMode,
      cullMode, windingOrder, blend, setsBlend, blendAttachment, depthWrite,
      depthCompare);

  @override
  String toString() {
    final parts = <String>[
      if (viewport != null) 'viewport',
      if (scissor != null) 'scissor',
      if (primitiveType != null) 'primitive: ${primitiveType!.name}',
      if (polygonMode != null) 'polygon: ${polygonMode!.name}',
      if (cullMode != null) 'cull: ${cullMode!.name}',
      if (windingOrder != null) 'winding: ${windingOrder!.name}',
      if (setsBlend) 'blend: ${blend == null ? 'off' : 'on'}',
      if (depthWrite != null) 'depthWrite: $depthWrite',
      if (depthCompare != null) 'depthCompare: ${depthCompare!.name}',
    ];
    return 'PassState(${parts.join(', ')})';
  }
}

/// Applies a [PassState] to an encoder.
extension PassStateApply on PassEncoder {
  /// Emits one call per field [state] sets, and nothing for the rest.
  ///
  /// **The order is fixed and is not the order any site used before.** Several
  /// of the twelve sites this replaces emitted these in different orders —
  /// notably the two full-screen paths, one setting blend before depth and the
  /// other after — and one value object cannot reproduce all of them. Choosing
  /// a single order is therefore a deliberate change to what several passes
  /// emit, and it is safe for a reason worth stating rather than assuming:
  /// these are independent pieces of pass state, set before any draw. No
  /// backend's setter reads another's value. On WebGL they are separate GL
  /// calls whose relative order does not matter; on the other two they are
  /// fields of a descriptor read at draw time.
  ///
  /// Geometry first, then topology, then blending, then depth — which reads in
  /// the order a reader asks the questions: where, what shape, how combined,
  /// how occluded.
  void setState(PassState state) {
    if (state.viewport != null) setViewport(state.viewport!);
    if (state.scissor != null) setScissor(state.scissor!);
    if (state.primitiveType != null) setPrimitiveType(state.primitiveType!);
    if (state.polygonMode != null) setPolygonMode(state.polygonMode!);
    if (state.cullMode != null) setCullMode(state.cullMode!);
    if (state.windingOrder != null) setWindingOrder(state.windingOrder!);
    if (state.setsBlend) {
      setBlend(state.blend, attachment: state.blendAttachment);
    }
    if (state.depthWrite != null) setDepthWrite(state.depthWrite!);
    if (state.depthCompare != null) setDepthCompare(state.depthCompare!);
  }
}
