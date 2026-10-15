/// The skinning hooks' passes (D22b): a `SkinningHook` placed as a compute
/// step, writing each claimed mesh's vertices into a buffer the scene draws.
///
/// **A part of `renderer.dart`**, because the mesh pass reads what these
/// write through the renderer's own state, as the shadow passes do.
part of 'renderer.dart';

/// What the skinning steps of one renderer share: the steps, which mesh
/// each skins this frame, and the buffers they write.
final class _SkinningState {
  final List<_SkinningStep> steps = <_SkinningStep>[];

  /// The meshes a hook claimed for this frame, with the step that skins
  /// each and the joint matrices it skins with.
  final Map<MeshNode, ({_SkinningStep step, Float32List joints})> claimed =
      <MeshNode, ({_SkinningStep step, Float32List joints})>{};

  /// The buffer each mesh is drawn from this frame, once its hook wrote it.
  final Map<MeshNode, StorageBuffer> drawn = <MeshNode, StorageBuffer>{};

  /// Each mesh's buffer on the drawing device, kept between frames.
  final Expando<StorageBuffer> _outputs = Expando<StorageBuffer>();

  /// Each mesh's buffer on a CPU executor, kept between frames.
  final Expando<StorageBuffer> _hostOutputs = Expando<StorageBuffer>();

  /// Asks the placed hooks, in the order they were placed, which skinned
  /// meshes of [scene] they skin this frame. Nothing is claimed on a device
  /// that makes no buffers: the mesh is drawn as the engine skins it.
  void begin(Scene scene, GraphicsDevice device) {
    claimed.clear();
    drawn.clear();
    if (steps.isEmpty || !device.features.has(DeviceFeature.buffers)) return;
    for (final node in scene.meshes) {
      final skeleton = node.skeleton;
      if (skeleton == null || node is InstancedMeshNode) continue;
      skeleton.update(node.worldMatrix);
      final joints = Float32List.fromList(skeleton.matrices);
      final asked = SkinningContext(node: node, jointMatrices: joints);
      for (final step in steps) {
        if (!step.isReady || !step.isSupported || !step.hook.claims(asked)) {
          continue;
        }
        claimed[node] = (step: step, joints: joints);
        break;
      }
    }
  }

  /// [node]'s buffer on the drawing [device], made again when the mesh
  /// grew; vertex-bindable, written by a copy, and by a compute pass where
  /// [storage] says one writes it there.
  StorageBuffer outputFor(
    MeshNode node,
    GraphicsDevice device, {
    required bool storage,
  }) {
    final length =
        node.mesh.vertexCount * VertexLayout.standard.floatsPerVertex * 4;
    final kept = _outputs[node];
    if (kept != null &&
        kept.lengthInBytes == length &&
        (!storage || kept.usage.contains(BufferUsage.storage))) {
      return kept;
    }
    if (kept != null) device.releaseStorageBuffer(kept);
    return _outputs[node] = device.createBuffer(
      BufferDescriptor(
        lengthInBytes: length,
        usage: storage
            ? BufferUsage.vertex | BufferUsage.standardStorage
            : BufferUsage.vertex |
                  BufferUsage.copyDestination |
                  BufferUsage.copySource,
      ),
    );
  }

  /// [node]'s buffer on a CPU executor's [device], host-readable.
  StorageBuffer hostOutputFor(MeshNode node, GraphicsDevice device) {
    final length =
        node.mesh.vertexCount * VertexLayout.standard.floatsPerVertex * 4;
    final kept = _hostOutputs[node];
    if (kept != null && kept.lengthInBytes == length) return kept;
    if (kept != null) device.releaseStorageBuffer(kept);
    return _hostOutputs[node] = device.createBuffer(
      BufferDescriptor(
        lengthInBytes: length,
        usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
      ),
    );
  }
}

/// One placed [SkinningHook], as the compute step that runs it.
///
/// A hook with kernels runs where the hardware layer placed it, never
/// beside the frame's device (`prepareForThisFrame`): on the drawing device
/// it writes the mesh's buffer there and the vertices never leave the GPU;
/// on the CPU it writes a buffer of the CPU device, which is copied into
/// the drawing device's buffer from the host. A
/// [HostSkinningHook] needs no placement and uploads what it computed.
final class _SkinningStep extends ComputeStep {
  _SkinningStep(this.hook, this._state, this.name);

  final SkinningHook hook;
  final _SkinningState _state;

  @override
  final String name;

  bool get _onHost => hook is HostSkinningHook || hook.kernels.isEmpty;

  @override
  List<ComputeKernel> get kernels => hook.kernels;

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforeShadows;

  @override
  List<ResourceId> get writes => const <ResourceId>[
    FrameResourceIds.skinnedVertices,
  ];

  @override
  bool get isSupported => _onHost || super.isSupported;

  @override
  void execute(RenderFrame frame) {
    if (!_onHost) return super.execute(frame);
    StorageBuffer? last;
    for (final MapEntry(key: node, value: claim) in _state.claimed.entries) {
      if (!identical(claim.step, this)) continue;
      final output = _state.outputFor(node, frame.device, storage: false);
      final wrote = hook.record(
        SkinningContext(
          node: node,
          jointMatrices: claim.joints,
          device: frame.device,
          output: output,
        ),
      );
      if (wrote) _state.drawn[node] = last = output;
    }
    if (last != null) {
      frame.resources.provideBuffer(FrameResourceIds.skinnedVertices, last);
    }
  }

  @override
  void record(ComputeContext context) {
    final frame = context.frame;
    final onFrame = context.isOnFrameDevice;
    StorageBuffer? last;
    for (final MapEntry(key: node, value: claim) in _state.claimed.entries) {
      if (!identical(claim.step, this)) continue;
      final output = _state.outputFor(node, frame.device, storage: onFrame);
      if (onFrame) {
        final wrote = hook.record(
          SkinningContext(
            node: node,
            jointMatrices: claim.joints,
            device: context.device,
            output: output,
            compute: context,
          ),
        );
        if (wrote) _state.drawn[node] = last = output;
        continue;
      }
      // The CPU device: its own buffer, read in host memory and copied
      // into the drawing device's. No device is read back.
      final executor = context.device;
      if (executor is! SynchronousBufferReadback) continue;
      final host = _state.hostOutputFor(node, executor);
      final wrote = hook.record(
        SkinningContext(
          node: node,
          jointMatrices: claim.joints,
          device: executor,
          output: host,
          compute: context,
        ),
      );
      if (!wrote) continue;
      frame.device.writeBuffer(output, 0, executor.readBufferSync(host));
      _state.drawn[node] = last = output;
    }
    if (last != null) {
      frame.resources.provideBuffer(FrameResourceIds.skinnedVertices, last);
    }
  }
}
