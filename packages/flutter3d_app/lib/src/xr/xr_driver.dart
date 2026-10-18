/// How a view drives an XR session: the runtime's frames into the loop,
/// the views and the layers, and what was drawn back out.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show DeviceFeature, TextureHandle;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show DisplayTime, InputAction, InputState, XrActionSource;

import 'xr_layers.dart';
import 'xr_session.dart';
import 'xr_swapchain.dart';

/// What a `Flutter3dView` is told to do with an XR session: which session,
/// what to ask it for, what to show beside the scene and how the controls
/// reach the game.
final class XrSettings {
  /// Drive [session], started as [request].
  const XrSettings({
    required this.session,
    this.request = const XrSessionRequest(),
    this.panels = const <XrPanel>[],
    this.actions = const <String, InputAction<Object>>{},
    this.swapchain,
    this.near = 0.05,
    this.far = 500.0,
    this.mainLight,
  });

  /// The light a runtime's measured main light drives
  /// (`XrLightEstimate.applyTo`), or null to leave the scene's lights alone;
  /// the scene's ambient light follows the room's either way, on a frame
  /// that measured it.
  final LightNode? mainLight;

  /// The runtime.
  final XrSession session;

  /// What it is started as.
  final XrSessionRequest request;

  /// Widgets shown as layers of their own beside the scene.
  final List<XrPanel> panels;

  /// Which action each control drives, by `XrActionSource.sourceId`; empty
  /// leaves the controls to a game's own action map, which binds the same
  /// ids.
  final Map<String, InputAction<Object>> actions;

  /// The images asked for, or null for 1440 × 1584 a view, two views: a
  /// standalone headset's recommended size.
  final XrSwapchainRequest? swapchain;

  /// Each eye's near clip plane, meters.
  final double near;

  /// Each eye's far clip plane, meters.
  final double far;

  /// These settings with the fields given replaced; [clearSwapchain] and
  /// [clearMainLight] set those two back to null.
  XrSettings copyWith({
    XrSession? session,
    XrSessionRequest? request,
    List<XrPanel>? panels,
    Map<String, InputAction<Object>>? actions,
    XrSwapchainRequest? swapchain,
    bool clearSwapchain = false,
    double? near,
    double? far,
    LightNode? mainLight,
    bool clearMainLight = false,
  }) => XrSettings(
    session: session ?? this.session,
    request: request ?? this.request,
    panels: panels ?? this.panels,
    actions: actions ?? this.actions,
    swapchain: clearSwapchain ? null : swapchain ?? this.swapchain,
    near: near ?? this.near,
    far: far ?? this.far,
    mainLight: clearMainLight ? null : mainLight ?? this.mainLight,
  );
}

/// Drives one XR session for one renderer: waits for the runtime's frames,
/// hands each to the loop and the eyes, copies what was drawn into the
/// runtime's image and ends the frame with its layers.
///
/// **One frame in flight.** The next frame is asked for only once the last
/// one is ended, so the runtime paces the engine and nothing queues. What
/// a frame does, in order:
///
/// 1. [beginFrame]: the runtime's predicted display time goes to [time];
///    the frame's poses, planes and meshes go into the loop's input as
///    external state, so they are on the tape with the step that takes
///    them; the controls go to the actions; the eye cameras take the
///    views' poses and angles; the image is acquired and handed to the
///    projection node.
/// 2. The frame is drawn through [views].
/// 3. [endFrame]: the image goes back to the runtime and the frame ends
///    with the projection layer and a layer for each panel.
final class XrDriver {
  /// A driver of [settings]' session over [renderer], placing the eyes
  /// under [origin]: where the player stands.
  XrDriver({
    required this.settings,
    required this.renderer,
    required this.origin,
    this.drawPanel,
  });

  /// What it drives and how.
  final XrSettings settings;

  /// What draws the frames.
  final Renderer renderer;

  /// Where the player stands: the eye cameras are its children, placed by
  /// the runtime's poses in the session's space.
  final SceneNode origin;

  /// Draws a panel's widget into a texture of the size an [XrPanelRequest]
  /// asks for; null shows no panels. A view hands `WidgetTexture.draw`.
  final Future<TextureHandle?> Function(XrPanelRequest panel)? drawPanel;

  /// The loop's clock while the session runs: the runtime's display times.
  final DisplayTime time = DisplayTime();

  /// The node that copies the views into the runtime's image.
  final ProjectionLayerNode projection = ProjectionLayerNode();

  /// The node that puts the room's depth in the frame.
  final EnvironmentDepthNode environmentDepth = EnvironmentDepthNode();

  /// The session driven, as the view's XR settings name it.
  XrSession get session => settings.session;

  final List<CameraNode> _eyes = <CameraNode>[];
  final List<CameraView> _views = <CameraView>[];
  XrSwapchain? _swapchain;
  XrFrame? _pending;
  XrFrame? _current;
  TextureHandle? _image;
  XrActionSource? _actions;
  final List<Registration> _steps = <Registration>[];
  final Map<XrPanel, (int, TextureHandle)> _panelImages =
      <XrPanel, (int, TextureHandle)>{};
  bool _running = false;
  bool _asking = false;

  /// How many frames have been ended: what a frame panel shows beside the
  /// runtime's own count, and a test reads.
  int get framesEnded => _framesEnded;
  int _framesEnded = 0;

  /// The swapchain, once [start] has made one; null for an inline session.
  XrSwapchain? get swapchain => _swapchain;

  /// The views the frame is drawn through: one per view of the runtime's
  /// last frame, side by side in the target, each through its eye.
  List<CameraView> get views => List<CameraView>.unmodifiable(_views);

  /// Starts the session, makes its swapchain when it is immersive, adds the
  /// nodes the frame needs, and asks for the first frame. Throws the
  /// session's refusal as it comes ([XrSession.start]), and the projection
  /// layer's when the device cannot feed the runtime's images.
  Future<void> start({InputState? input}) async {
    final request = settings.request;
    await session.start(request);
    if (input != null && settings.actions.isNotEmpty) {
      _actions = XrActionSource(input: input, bindings: settings.actions);
    }
    if (request.mode != XrCapability.inline) {
      final device = renderer.device;
      final asked =
          settings.swapchain ??
          const XrSwapchainRequest(width: 1440, height: 1584);
      final swapchain = _swapchain = session.createSwapchain(
        asked.format == null
            ? asked.withFormat(device.defaultColorFormat)
            : asked,
      );
      if (!device.features.has(DeviceFeature.textureCopy)) {
        swapchain.dispose();
        _swapchain = null;
        await session.end();
        throw UnsupportedCapabilityException(
          DeviceFeature.textureCopy,
          backend: device.backendName,
          reason:
              "a headset's views are copied into the layers of its image, "
              'and this device copies no texture',
        );
      }
      _steps.add(renderer.renderSteps.addNode(projection));
    }
    if (session.capabilities.contains(XrCapability.depthOcclusion) &&
        (request.required.contains(XrCapability.depthOcclusion) ||
            request.optional.contains(XrCapability.depthOcclusion))) {
      _steps.add(renderer.renderSteps.addNode(environmentDepth));
    }
    _running = true;
    _ask();
  }

  void _ask() {
    if (!_running || _asking || _pending != null) return;
    _asking = true;
    unawaited(
      session.waitFrame().then(
        (XrFrame frame) {
          _asking = false;
          if (_running) _pending = frame;
        },
        onError: (Object _) {
          _asking = false;
        },
      ),
    );
  }

  /// Takes the runtime's waiting frame and readies everything for drawing
  /// it, writing its state into [input]; null when the runtime has not
  /// handed one since the last.
  XrFrame? beginFrame(InputState input) {
    final frame = _pending;
    if (frame == null) return null;
    _pending = null;
    _current = frame;
    time.predict(frame.predictedDisplayTime);
    for (final external in frame.toInputs()) {
      input.feedExternal(external);
    }
    _actions?.apply(frame.controlReadings);
    _placeEyes(frame);
    environmentDepth.depth = frame.depth;
    if ((frame.light, origin.scene) case (final light?, final scene?)) {
      light.applyTo(scene, main: settings.mainLight);
    }
    final swapchain = _swapchain;
    if (swapchain != null && frame.shouldRender) {
      _image = projection.target = swapchain.acquire(renderer.device);
    } else {
      _image = projection.target = null;
    }
    return frame;
  }

  void _placeEyes(XrFrame frame) {
    final count = frame.views.length;
    while (_eyes.length < count) {
      final eye = CameraNode(name: 'xr.eye.${_eyes.length}');
      origin.add(eye);
      _eyes.add(eye);
    }
    if (_views.length != count) {
      for (final view in _views) {
        view.dispose();
      }
      _views
        ..clear()
        ..addAll(<CameraView>[
          for (var i = 0; i < count; i++)
            CameraView(
              camera: _eyes[i],
              viewportFraction: ViewportRect(i / count, 0.0, 1 / count, 1.0),
            ),
        ]);
    }
    for (final view in frame.views) {
      final eye = _eyes[view.index];
      final at = view.pose.position;
      eye
        ..setPosition(at.x, at.y, at.z)
        ..setRotation(view.pose.orientation)
        ..projection = view.fov.projection(
          near: settings.near,
          far: settings.far,
        );
    }
  }

  /// Ends the frame [beginFrame] began, once it is drawn: the image goes
  /// back to the runtime, the frame ends with its layers, and the next
  /// frame is asked for. Does nothing when no frame was begun.
  Future<void> endFrame() async {
    final frame = _current;
    if (frame == null) return;
    _current = null;
    final layers = <XrLayer>[];
    final image = _image;
    final swapchain = _swapchain;
    if (image != null && swapchain != null) {
      await swapchain.release();
      layers.add(
        XrProjectionLayer(
          space: frame.space,
          swapchain: swapchain,
          image: image,
          views: frame.views,
        ),
      );
    }
    if (frame.shouldRender) {
      for (final panel in settings.panels) {
        final image = _panelImage(panel);
        if (image != null) layers.add(panel.layer(frame.space, image));
      }
    }
    _image = projection.target = null;
    session.endFrame(XrFrameEnd(frame: frame, layers: layers));
    _framesEnded++;
    _ask();
  }

  /// The texture [panel] shows: the last one drawn, while a newer one is
  /// drawn when its generation moved.
  TextureHandle? _panelImage(XrPanel panel) {
    final draw = drawPanel;
    if (draw == null) return null;
    final drawn = _panelImages[panel];
    if (drawn == null || drawn.$1 != panel.generation) {
      final generation = panel.generation;
      unawaited(
        draw(
          XrPanelRequest(
            widget: panel.child,
            width: panel.pixelWidth,
            height: panel.pixelHeight,
          ),
        ).then((TextureHandle? texture) {
          if (texture == null || !_running) return;
          final old = _panelImages[panel];
          _panelImages[panel] = (generation, texture);
          if (old != null) renderer.device.releaseTexture(old.$2);
        }),
      );
    }
    return drawn?.$2;
  }

  /// Ends the session and takes away what the driver added.
  Future<void> dispose() async {
    _running = false;
    for (final step in _steps) {
      step.cancel();
    }
    _steps.clear();
    _actions?.letGo();
    environmentDepth.dispose();
    for (final (_, texture) in _panelImages.values) {
      renderer.device.releaseTexture(texture);
    }
    _panelImages.clear();
    for (final view in _views) {
      view.dispose();
    }
    _views.clear();
    for (final eye in _eyes) {
      eye.removeFromParent();
    }
    _eyes.clear();
    _swapchain?.dispose();
    _swapchain = null;
    if (session.state != XrSessionState.ended &&
        session.state != XrSessionState.lost) {
      await session.end();
    }
  }
}

/// What `XrDriver.drawPanel` is asked to draw: a panel's [widget] into a
/// texture [width] by [height] pixels.
///
/// **One object, so a later minor can ask for more** (a scale, a colour
/// space) without breaking a drawer.
final class XrPanelRequest {
  /// [widget], drawn [width] by [height].
  const XrPanelRequest({
    required this.widget,
    required this.width,
    required this.height,
  });

  /// What the panel shows.
  final Widget widget;

  /// The texture's width, in pixels.
  final int width;

  /// The texture's height, in pixels.
  final int height;
}
