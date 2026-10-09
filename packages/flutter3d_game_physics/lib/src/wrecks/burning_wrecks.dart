import 'package:flutter3d_core/flutter3d_core.dart'
    show CuboidShape, DeviceMesh, MeshNode, RenderMaterial;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// What a hit leaves burning: oil spread on the water and alight, a heap of
/// timbers on the bank. Fires of the physics core's own heat in a game's
/// [Elements], lit by a blast's fireball, which burn as long as their fuel
/// lasts and light what stands close enough, drawn as flames and smoke, and
/// let go once whoever left them is far enough past.
///
/// **On the elements, not beside them.** A wreck is a body in the elements'
/// world: the water floats the slick and its current carries it off, the
/// fires model spreads the burning, and the elements step and draw both.
/// This class only places them and lets them go.
final class BurningWrecks {
  /// Wrecks in [elements], their looks uploaded to [device].
  ///
  /// [along] is the way the player travels: a fire more than [behind]
  /// metres back along it from the distance [step] is told is let go.
  BurningWrecks(
    Elements elements,
    GraphicsDevice device, {
    Vector3? along,
    this.behind = defaultBehind,
  }) : _elements = elements,
       _device = device,
       _along = (along ?? Vector3(0.0, 0.0, -1.0)).normalized();

  /// The elements: the water, and what burns on it.
  final Elements _elements;
  final GraphicsDevice _device;
  final Vector3 _along;
  final List<TrackedBody> _burning = <TrackedBody>[];

  /// How far behind the player a fire is let go, in metres.
  final double behind;

  /// [behind] unless a game says otherwise, in metres.
  static const double defaultBehind = 40.0;

  /// A blast's fireball over what it hits: about what a large burning
  /// hydrocarbon's flame gives what it engulfs, a hundred kilowatts a square
  /// metre from gas at 1300 K, for the second the fireball lasts.
  static const Igniter fireball = Igniter(
    flux: 1e5,
    area: 1.0,
    temperature: 1300.0,
    seconds: 1.0,
  );

  /// The wrecks still held, oldest first: what a game's sound or score asks
  /// after, and what is let go by [step].
  List<TrackedBody> get bodies => List<TrackedBody>.unmodifiable(_burning);

  /// A cargo of oil spread over the water at [at] and burning: crude, which
  /// burns as long and as sooty as rubber does — sixty kilograms of it over
  /// a slick three metres by one and a half. It is the oil that burns, not
  /// the hull, which goes down under it: the slick floats, far lighter than
  /// the water, and the current carries it and its fire off. Drawn as what
  /// it is, a black film as glossy as water — oil's refractive index of
  /// about 1.5 reflects 4% head on, as water's 1.33 reflects 2%.
  void oil(Vector3 at) {
    final half = Vector3(1.4, 0.05, 0.8);
    _light(
      Solid.box(
        half,
        material: NativeMaterial.rubber(),
        density: 60.0 / (2.8 * 0.1 * 1.6),
      ),
      Vector3(at.x, 0.05, at.z),
      type: NativeBodyType.dynamic,
      look: MeshNode(
        DeviceMesh.upload(_device, CuboidShape(size: half * 2.0).build()),
        RenderMaterial(
          name: 'crude',
          baseColor: LinearColor.fromSrgb(0.02, 0.018, 0.015, 1.0),
          roughness: 0.08,
        ),
        name: 'slick',
      ),
    );
  }

  /// A heap of timbers at [at], burning where they fell: 160 kg of wood.
  void timbers(Vector3 at) => _light(
    Solid.box(
      Vector3(0.9, 0.5, 0.9),
      material: NativeMaterial.wood(),
      density: 160.0 / (1.8 * 1.0 * 1.8),
    ),
    at,
  );

  void _light(
    Solid solid,
    Vector3 at, {
    NativeBodyType type = NativeBodyType.fixed,
    MeshNode? look,
  }) {
    final body = _elements.addBody(solid, at: at, type: type, look: look);
    _elements.fires.ignite(
      body,
      by: fireball,
      at: Vector3(at.x, at.y + 0.5, at.z),
    );
    _burning.add(body);
  }

  /// The player [distance] metres on along the way it travels: a fire more
  /// than [behind] metres back is let go. The elements step and draw the
  /// fires.
  void step(double distance) {
    _burning.removeWhere((body) {
      final on = _elements.world.localPositionOf(body.native).dot(_along);
      if (on > distance - behind) return false;
      _elements.remove(body);
      return true;
    });
  }

  /// Every fire put out, for a run starting the stretch again.
  void clear() {
    _burning
      ..forEach(_elements.remove)
      ..clear();
  }
}
