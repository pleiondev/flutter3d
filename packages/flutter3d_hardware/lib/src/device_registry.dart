/// How an engine picks which [GraphicsDevice] to open, and how it finds the
/// thing that shows a frame from one — a registry a backend adds itself to,
/// rather than a list this package or `flutter3d_app` would have to already
/// know every entry of.
///
/// **One registry per engine, since 1.0** (principle A.4 of the API review:
/// no global mutable state). Before it the openers and presenters were
/// top-level lists every engine in the isolate shared, so two engines — two
/// plugin hosts, a test beside an application — could not choose backends
/// of their own, and a fake registered by one test leaked into the next.
/// Now an engine owns a [DeviceRegistry], a backend's `register…Backend`
/// adds itself to the one it is handed, and every addition is a
/// [Registration] that takes it out again.
///
/// **Opening a device names no framework**, so the whole of opening lives
/// here, in the vocabulary every backend already depends on. **Showing a
/// frame returns a Flutter `Widget`**, which this package must not name, so
/// only the generic half lives here: a presenter registered for a device
/// type and looked up by `device is T`, of the type [DeviceRegistry]'s `P`
/// names — `flutter3d_app`'s `FramePresenter`, the one place a `Widget` is
/// allowed to be named.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;
import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'compute_placement.dart';
import 'device_exceptions.dart';
import 'graphics_device.dart';

/// Opens a compute-only [GraphicsDevice] for a [ComputePlacement], or
/// throws: the wgpu sidecar, a CPU device — 1.0. Its [DeviceRequest] has no
/// size ([DeviceRequest.compute]), because it presents nothing.
typedef ComputeOpener = Future<GraphicsDevice> Function(DeviceRequest request);

/// Opens a [GraphicsDevice] for [request], or throws.
///
/// **The one shape of opening, on every backend**, since 1.0: asynchronous,
/// and given the size of the surface it starts at. A backend that sizes its
/// targets per frame (Impeller) takes the size and is not held to it; one
/// that cannot (the software rasteriser, WebGL2's canvas) draws at it.
///
/// **One [DeviceRequest], since 1.0.0-rc.1**, where it was a width and a
/// height as named parameters: an opener is a function type every backend
/// assigns to, so a parameter added later would make every `open` written
/// before it unassignable. A field with a default on the request breaks
/// nobody, and a backend that does not read it is still asked for what it
/// says: the registry holds the device [open] answers to
/// [DeviceRequest.checkSatisfiedBy].
typedef BackendOpener = Future<GraphicsDevice> Function(DeviceRequest request);

/// What an application asks of the device it opens — since 1.0.0-rc.1.
///
/// The size of the surface it starts at, and what WebGPU's `requestAdapter`
/// and `requestDevice` take: the features and limits the application cannot
/// do without, which GPU to prefer, whether the API's validation layer is
/// wanted, and a label. Every field after the size has a default that asks
/// for nothing, so a field a minor adds breaks no backend.
@immutable
final class DeviceRequest {
  /// A device for a surface [width] by [height] pixels.
  const DeviceRequest({
    required this.width,
    required this.height,
    this.requiredFeatures = const <DeviceFeature>{},
    this.requiredLimits = const <String, int>{},
    this.powerPreference = PowerPreference.none,
    this.validation = false,
    this.label,
  });

  /// A device that presents nothing — what a [ComputeOpener] is handed.
  const DeviceRequest.compute({
    this.requiredFeatures = const <DeviceFeature>{},
    this.requiredLimits = const <String, int>{},
    this.powerPreference = PowerPreference.none,
    this.validation = false,
    this.label,
  }) : width = 0,
       height = 0;

  /// The width of the surface the device starts at, in pixels; zero for a
  /// compute device.
  final int width;

  /// The height of the surface the device starts at, in pixels; zero for a
  /// compute device.
  final int height;

  /// Features the device must have, or not be opened. A backend that can
  /// ask its API for them (WebGPU's `requiredFeatures`) does; every device
  /// is held to them by [checkSatisfiedBy] when the registry opens it.
  final Set<DeviceFeature> requiredFeatures;

  /// Limits the device must reach, by their `DeviceLimits.toMap` names: at
  /// least the value for a `max…` limit, at most it for a `min…` alignment.
  /// A name `DeviceLimits` does not know is refused, as WebGPU refuses one.
  final Map<String, int> requiredLimits;

  /// Which GPU to prefer where there is a choice.
  final PowerPreference powerPreference;

  /// Whether the API's validation layer is wanted, where it has one that
  /// can be switched on (Vulkan's, Metal's API validation). Ignored where it
  /// cannot; WebGPU and WebGL2 always validate.
  final bool validation;

  /// What the device is called, for a GPU debugger; null for nothing.
  final String? label;

  /// Why [device] does not satisfy this request, one sentence per shortfall;
  /// empty when it does.
  List<String> shortfallsOf(GraphicsDevice device) {
    final limits = device.limits.toMap();
    return <String?>[
      for (final feature in DeviceFeature.values)
        if (requiredFeatures.contains(feature) && !device.features.has(feature))
          'it has no ${feature.name}',
      for (final MapEntry(key: name, value: wanted) in requiredLimits.entries)
        switch (limits[name]) {
          null => 'no limit is called $name',
          final int has when name.startsWith('min') && has > wanted =>
            '$name is $has, above the $wanted asked for',
          final int has when !name.startsWith('min') && has < wanted =>
            '$name is $has, below the $wanted asked for',
          _ => null,
        },
    ].nonNulls.toList();
  }

  /// Throws a [DeviceUnavailableException] naming every shortfall when
  /// [device] does not satisfy this request.
  ///
  /// **Called by the registry on every device an opener answers**, so a
  /// backend that never reads [requiredFeatures] still cannot hand an
  /// application a device without them; a backend that asks its API for
  /// them may call it too, before it hands the device over.
  void checkSatisfiedBy(GraphicsDevice device) {
    final shortfalls = shortfallsOf(device);
    if (shortfalls.isEmpty) return;
    throw DeviceUnavailableException(
      '${device.backendName} does not satisfy the request: '
      '${shortfalls.join('; ')}',
      refusals: List<String>.unmodifiable(shortfalls),
    );
  }

  /// This request at another size — what a registry hands each backend it
  /// tries for the same surface.
  DeviceRequest sized({required int width, required int height}) =>
      DeviceRequest(
        width: width,
        height: height,
        requiredFeatures: requiredFeatures,
        requiredLimits: requiredLimits,
        powerPreference: powerPreference,
        validation: validation,
        label: label,
      );

  @override
  bool operator ==(Object other) =>
      other is DeviceRequest &&
      other.width == width &&
      other.height == height &&
      other.requiredFeatures.length == requiredFeatures.length &&
      other.requiredFeatures.containsAll(requiredFeatures) &&
      other.requiredLimits.length == requiredLimits.length &&
      requiredLimits.entries.every(
        (MapEntry<String, int> e) => other.requiredLimits[e.key] == e.value,
      ) &&
      other.powerPreference == powerPreference &&
      other.validation == validation &&
      other.label == label;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    Object.hashAllUnordered(requiredFeatures),
    Object.hashAllUnordered(<Object>[
      for (final MapEntry(:key, :value) in requiredLimits.entries)
        Object.hash(key, value),
    ]),
    powerPreference,
    validation,
    label,
  );

  @override
  String toString() =>
      'DeviceRequest(${width}x$height'
      '${requiredFeatures.isEmpty ? '' : ', features: ${requiredFeatures.map((DeviceFeature f) => f.name).join(', ')}'}'
      '${requiredLimits.isEmpty ? '' : ', limits: $requiredLimits'}'
      '${powerPreference == PowerPreference.none ? '' : ', ${powerPreference.name}'}'
      '${validation ? ', validation' : ''}'
      '${label == null ? '' : ', "$label"'})';
}

/// Which GPU a [DeviceRequest] prefers where there is a choice: WebGPU's
/// `powerPreference`.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
@immutable
final class PowerPreference {
  const PowerPreference._(this.name);

  /// No preference: the API's default.
  static const PowerPreference none = PowerPreference._('none');

  /// The integrated GPU, where a laptop has two.
  static const PowerPreference lowPower = PowerPreference._('low-power');

  /// The discrete GPU, where a laptop has two.
  static const PowerPreference highPerformance = PowerPreference._(
    'high-performance',
  );

  /// Every value this version names, in declaration order.
  static const List<PowerPreference> values = <PowerPreference>[
    none,
    lowPower,
    highPerformance,
  ];

  /// The value called [name], or null for a name this version does not know.
  static PowerPreference? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'PowerPreference.$name';
}

/// The backends one engine may open, in the order it tries them, and the
/// presenters of type [P] that show their frames.
///
/// **Typed by what a presenter is, since 1.0.** A presenter was held as an
/// [Object] and every caller cast what [presenterFor] answered; now the
/// registry is made for one presenter type — `DeviceRegistry<FramePresenter>`
/// in `flutter3d_app`, whose `platformDevices` makes one — so [addPresenter]
/// takes only that type and [presenterFor] answers it. A registry used only
/// to open devices, a test's or a tool's, is a `DeviceRegistry<Object>`.
///
/// A backend's own `register…Backend` takes the registry as a
/// `DeviceRegistry<Object>`, because a backend package cannot name the
/// application's presenter type; what it adds is checked against the
/// registry's real `P` when it is added, not when a frame is first shown.
final class DeviceRegistry<P extends Object> {
  /// An empty registry: no backend until one is added.
  DeviceRegistry();

  final List<({String name, BackendOpener open})> _preferred =
      <({String name, BackendOpener open})>[];
  final List<({String name, BackendOpener open})> _fallbacks =
      <({String name, BackendOpener open})>[];
  final List<({bool Function(GraphicsDevice) accepts, P presenter})>
  _presenters = <({bool Function(GraphicsDevice) accepts, P presenter})>[];

  /// The names of the backends [open] would try, in the order it tries them —
  /// for an application's diagnostics screen, or a test checking what it
  /// registered.
  List<String> get backendNames => List<String>.unmodifiable(<String>[
    for (final entry in _preferred.reversed) entry.name,
    if (_fallbacks.isNotEmpty) _fallbacks.last.name,
  ]);

  /// Adds [open] as a backend [this.open] may try, named [name] for the line
  /// printed if it refuses to start.
  ///
  /// Tried before every backend already added — last added, first tried —
  /// unless [asFallback] is set, in which case [open] becomes *the* fallback:
  /// the one backend tried last, and the only one still tried if every
  /// preferred one refuses. Adding a second fallback puts it in front of the
  /// first until its registration is cancelled; there is only ever one in
  /// use, since a fallback's whole promise is being the thing still standing
  /// when nothing else is.
  ///
  /// The [Registration] takes it out again: an application ignores it; a
  /// test cancels it in a tear-down.
  Registration addBackend(
    String name,
    BackendOpener open, {
    bool asFallback = false,
  }) {
    final entry = (name: name, open: open);
    final list = asFallback ? _fallbacks : _preferred;
    list.add(entry);
    return Registration(
      () => list.removeWhere(
        (({String name, BackendOpener open}) e) => identical(e, entry),
      ),
    );
  }

  /// Opens the first backend that starts: the preferred ones, newest first,
  /// then the fallback. [onFallback] is told each refusal before the next
  /// backend is tried.
  ///
  /// Throws a [DeviceUnavailableException] naming every refusal when none
  /// starts, its [DeviceUnavailableException.refusals] one line per backend
  /// tried. (It was a `StateError` before 1.0: a machine with no backend that
  /// will start is something a correct program meets, not a mistake in it.)
  ///
  /// **The device opened takes its compute from here**, since
  /// 1.0.0-rc.1, as [adopt] says: its frames' [FrameCompute] offers the
  /// compute devices added with [addComputeDevice], opened the first time
  /// a frame needs them, each that will not start told to [onFallback].
  Future<GraphicsDevice> open({
    required int width,
    required int height,
    void Function(String message)? onFallback,
  }) => openFor(
    DeviceRequest(width: width, height: height),
    onFallback: onFallback,
  );

  /// [open], for everything [request] asks — since 1.0.0-rc.1.
  ///
  /// Each backend is handed [request]; a device that does not satisfy it
  /// ([DeviceRequest.checkSatisfiedBy]) is disposed and counted as that
  /// backend's refusal, and the next one is tried, so an application that
  /// cannot draw without a feature is never handed a device without it.
  Future<GraphicsDevice> openFor(
    DeviceRequest request, {
    void Function(String message)? onFallback,
  }) async {
    final device = await _openFirst(request, onFallback);
    adopt(device, onRefused: onFallback);
    return device;
  }

  /// Makes the compute devices added here ([addComputeDevice]) the ones
  /// frames drawn on [device] may place their compute on, beside [device]
  /// itself — opened the first time a frame needs them, each that will not
  /// start told to [onRefused] and left out — since 1.0.0-rc.1.
  ///
  /// [open] does this for every device it opens. A layer that opens a
  /// device some other way, or a test that makes one directly, adopts it to
  /// give its frames the same compute. The latest adoption wins.
  void adopt(
    GraphicsDevice device, {
    void Function(String message)? onRefused,
  }) => attachCompute(
    device,
    () => computeExecutors(device, onRefused: onRefused),
  );

  /// [open] of one entry, held to [request]: a device that falls short is
  /// disposed, and its shortfall thrown as the entry's refusal.
  static Future<GraphicsDevice> _openHeld(
    BackendOpener open,
    DeviceRequest request,
  ) async {
    final device = await open(request);
    try {
      request.checkSatisfiedBy(device);
    } on DeviceUnavailableException {
      device.dispose();
      rethrow;
    }
    return device;
  }

  Future<GraphicsDevice> _openFirst(
    DeviceRequest request,
    void Function(String message)? onFallback,
  ) async {
    final refusals = <String>[];
    for (final entry in _preferred.reversed.toList()) {
      try {
        return await _openHeld(entry.open, request);
      } catch (error) {
        refusals.add('${entry.name}: $error');
        onFallback?.call(
          '${entry.name} would not start ($error), trying the next backend',
        );
      }
    }
    if (_fallbacks.isNotEmpty) {
      final fallback = _fallbacks.last;
      try {
        return await _openHeld(fallback.open, request);
      } catch (error) {
        refusals.add('${fallback.name}: $error');
      }
    }
    throw DeviceUnavailableException(
      'DeviceRegistry.open: no backend could be opened — '
      '${refusals.isEmpty ? 'none was added' : refusals.join('; ')}',
      refusals: List<String>.unmodifiable(refusals),
    );
  }

  /// Adds [presenter] as what shows a frame from a device that `is` a [T] —
  /// `flutter3d_app`'s `FramePresenter`, for the registry that app makes.
  /// The latest addition a device matches wins until its registration is
  /// cancelled.
  ///
  /// **Matched with `is`, not by exact runtime type, since 1.0**, so a
  /// presenter for a backend's device also shows a frame from a subclass of
  /// it, and a wrapper that extends the device it wraps is not left without
  /// one.
  Registration addPresenter<T extends GraphicsDevice>(P presenter) {
    final entry = (
      accepts: (GraphicsDevice device) => device is T,
      presenter: presenter,
    );
    _presenters.add(entry);
    return Registration(() => _presenters.remove(entry));
  }

  /// What shows a frame from [device] — the latest presenter added for a
  /// type [device] is — or null when nothing was added for it (absent).
  P? presenterFor(GraphicsDevice device) {
    for (final entry in _presenters.reversed) {
      if (entry.accepts(device)) return entry.presenter;
    }
    return null;
  }

  final List<({ComputePlacement placement, String name, ComputeOpener open})>
  _compute =
      <({ComputePlacement placement, String name, ComputeOpener open})>[];

  /// Adds [open] as the device for [placement] — 1.0: `flutter3d_wgpu` adds
  /// the sidecar, `flutter3d_cpu` the CPU — named [name] for the line
  /// [computeExecutors] reports when it will not start. The latest added
  /// for a placement wins until its registration is cancelled.
  ///
  /// [ComputePlacement.device] is not added here: it is the device the
  /// frame is drawn on, whichever [open] started.
  Registration addComputeDevice(
    ComputePlacement placement,
    String name,
    ComputeOpener open,
  ) {
    final entry = (placement: placement, name: name, open: open);
    _compute.add(entry);
    return Registration(() => _compute.remove(entry));
  }

  /// The executors a frame drawn on [device] may place compute on: [device]
  /// itself, and the newest sidecar and CPU device added that will start.
  /// One that refuses to start is left out and [onRefused] told why; the
  /// frame then places its steps on what is left.
  ///
  /// Each compute device is opened with [request] (no requirements by
  /// default) and held to it, as [openFor] holds a drawing device.
  Future<ComputeExecutors> computeExecutors(
    GraphicsDevice device, {
    void Function(String message)? onRefused,
    DeviceRequest request = const DeviceRequest.compute(),
  }) async {
    Future<GraphicsDevice?> openFor(ComputePlacement placement) async {
      for (final entry in _compute.reversed) {
        if (entry.placement != placement) continue;
        try {
          return await _openHeld(entry.open, request);
        } catch (error) {
          onRefused?.call(
            '${entry.name} (${placement.name} compute) would not start: '
            '$error',
          );
        }
      }
      return null;
    }

    return ComputeExecutors(
      device: device,
      sidecar: await openFor(ComputePlacement.sidecar),
      cpu: await openFor(ComputePlacement.cpu),
    );
  }
}
