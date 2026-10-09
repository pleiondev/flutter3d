/// What the elements and the renderer say, on a bus: the listeners as thin
/// adapters, the world's events as `ElementEvent`s, and the registries of
/// event kinds and switches plugin elements fill.
///
///     dart test test/bus_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

/// A bus that keeps what is published, in order.
final class _Bus extends EventRegistry {
  final List<BusEvent> published = <BusEvent>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) => published.add(event);

  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}

Future<Elements> _open() {
  final device = elementsDevice();
  return Elements.open(
    device: device,
    renderer: Renderer.create(device: device),
    scene: Scene(),
    load: (_) async => waterBundle(),
    quality: ElementsQuality.of(phone: true),
  );
}

void main() {
  test('the renderer\'s listener publishes each frame onto the bus', () {
    final device = CpuDevice(
      width: 16,
      height: 16,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
    final scene = Scene()..add(camera);
    final renderer = Renderer.create(device: device);
    final bus = _Bus();
    renderer.listener = RenderListener.toBus(bus, frameBudget: Duration.zero);
    final result = renderer.render(
      width: 16,
      height: 16,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );
    // Mutation: leave `drawn` out of `RenderListener.toBus` — the frame is
    // never heard on the bus, though the field is set.
    final drawn = bus.published.whereType<FrameDrawn>().toList();
    expect(drawn, hasLength(1));
    expect(identical(drawn.single.result, result), isTrue);
    // Mutation: publish only the first skipped pass — the counts part.
    expect(
      bus.published.whereType<FramePassSkipped>().length,
      result.skipped.length,
    );
    // A budget of nothing: every frame is over it.
    expect(bus.published.whereType<FrameOverTime>(), hasLength(1));
    // In the order `notify` calls them: skipped, over time, drawn.
    expect(bus.published.last, isA<FrameDrawn>());
  });

  test('the elements\' listener publishes what the world said', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final bus = _Bus();
    elements.listener = ElementsListener.toBus(bus);
    final crate = elements.addBody(
      Solid.box(
        Vector3.all(0.1),
        material: NativeMaterial.wood(),
        density: 500.0,
      ),
      at: Vector3(0.0, 0.1, 0.0),
      type: NativeBodyType.fixed,
    );
    elements.world.setTemperature(crate.native, 900.0);
    for (var i = 0; i < 90; i++) {
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    }
    // Mutation: map `caught` to `ElementOut` in `ElementsListener.toBus` —
    // a crate set alight is heard going out.
    final caught = bus.published.whereType<ElementCaught>().toList();
    expect(caught, isNotEmpty);
    expect(caught.first.body, crate.native);
    expect(identical(caught.first.made, crate), isTrue);
    expect(bus.published.whereType<ElementOut>(), isEmpty);
  });

  test('publishTo puts the world\'s events on the bus by kind', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final bus = _Bus();
    final registration = elements.publishTo(bus);
    final crate = elements.addBody(
      Solid.box(
        Vector3.all(0.1),
        material: NativeMaterial.wood(),
        density: 500.0,
      ),
      at: Vector3(0.0, 0.1, 0.0),
      type: NativeBodyType.fixed,
    );
    elements.world.setTemperature(crate.native, 900.0);
    for (var i = 0; i < 90; i++) {
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    }
    // Mutation: publish only when a listener is set — nothing reaches the
    // bus here, where none is.
    final events = bus.published.whereType<ElementEvent>().toList();
    expect(
      events.where((e) => e.kind == NativeEventKind.ignited).map((e) => e.body),
      contains(crate.native),
    );
    // Mutation: leave `_bus` set on cancel — the count goes on growing.
    registration.cancel();
    final before = bus.published.length;
    elements.world.setTemperature(crate.native, 300.0);
    elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    expect(bus.published.length, before);
  });
}
