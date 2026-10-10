import 'package:flutter3d_core/flutter3d_core.dart'
    show CuboidShape, DeviceMesh, MeshNode, RenderMaterial;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SnapshotPart;
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

  /// The wrecks held, oldest first, each with whether it is a slick of oil
  /// (drawn) or a heap of timbers (not).
  final Map<TrackedBody, bool> _burning = <TrackedBody, bool>{};

  /// How far behind the player a fire is let go, in metres.
  final double behind;

  /// [behind] unless a game says otherwise, in metres.
  static const double defaultBehind = 40.0;

  /// A blast's fireball over what it hits: about what a large burning
  /// hydrocarbon's flame gives what it engulfs, a hundred kilowatts a square
  /// metre from gas at 1300 K, held for 4.5 s.
  ///
  /// **Long enough to light the heap, and no longer.** A body catches on a
  /// patch a few centimetres across and the fire spreads from there (the
  /// core's ignition since 1.0), and a bed of splinters ([timbers]) catches
  /// a few centimetres deep: a one-second flash lights nothing. Measured on
  /// [timbers]: held 3.25 s it never catches, held 3.5 s it catches at
  /// 3.47 s and burns on; 4.5 s is that with a second's margin.
  static const Igniter fireball = Igniter(
    flux: 1e5,
    area: 1.0,
    temperature: 1300.0,
    seconds: 4.5,
  );

  /// The splinters a heap of [timbers] burns in, as square metres of surface
  /// per cubic metre of wood (per metre): square sticks 4 mm across,
  /// σ = 4 / 0.004.
  static const double splinterSurface = 1000.0;

  /// Their own density, kg/m³: wood's, as Rothermel takes for every fine
  /// fuel (513, USDA INT-115, 1972), to the figure.
  static const double splinterDensity = 500.0;

  /// The wrecks still held, oldest first: what a game's sound or score asks
  /// after, and what is let go by [step].
  List<TrackedBody> get bodies => List<TrackedBody>.unmodifiable(_burning.keys);

  /// A cargo of oil spread over the water at [at] and burning: crude, which
  /// burns as long and as sooty as rubber does — sixty kilograms of it over
  /// a slick three metres by one and a half. It is the oil that burns, not
  /// the hull, which goes down under it: the slick floats, far lighter than
  /// the water, and the current carries it and its fire off. Drawn as what
  /// it is, a black film as glossy as water — oil's refractive index of
  /// about 1.5 reflects 4% head on, as water's 1.33 reflects 2%.
  void oil(Vector3 at) => _light(
    Solid.box(
      _slickHalf,
      material: NativeMaterial.rubber(),
      density: 60.0 / (2.8 * 0.1 * 1.6),
    ),
    Vector3(at.x, 0.05, at.z),
    type: NativeBodyType.dynamic,
    look: _slick(),
  );

  static Vector3 get _slickHalf => Vector3(1.4, 0.05, 0.8);

  /// The black film a slick is drawn as.
  MeshNode _slick() => MeshNode(
    DeviceMesh.upload(_device, CuboidShape(size: _slickHalf * 2.0).build()),
    RenderMaterial(
      name: 'crude',
      baseColor: LinearColor.fromSrgb(0.02, 0.018, 0.015, 1.0),
      roughness: 0.08,
    ),
    name: 'slick',
  );

  /// A heap of timbers at [at], burning where they fell: 160 kg of wood.
  ///
  /// **A porous bed, not a block.** A blast leaves timbers smashed, and
  /// what a fire takes hold in is the splintered stuff between them, which
  /// the core reads as a bed of elements of [splinterSurface] in sticks of
  /// wood's own density, packed at the heap's 49 kg/m³. One face of solid
  /// wood cannot keep a flame without outside heat, so a heap modelled as a
  /// block went out the moment the fireball did. Measured with the
  /// [fireball]: sticks 1 cm across (400 m⁻¹) catch at 8.6 s, 4 mm (1000
  /// m⁻¹) at 3.5 s, 2 mm (2000 m⁻¹) at 1.7 s; each burns on once caught.
  void timbers(Vector3 at) => _light(
    Solid.box(
      Vector3(0.9, 0.5, 0.9),
      material: NativeMaterial.wood().copyWith(
        elementSurface: splinterSurface,
        elementDensity: splinterDensity,
      ),
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
    _burning[body] = look != null;
  }

  /// The player [distance] metres on along the way it travels: a fire more
  /// than [behind] metres back is let go. The elements step and draw the
  /// fires.
  void step(double distance) {
    _burning.removeWhere((body, _) {
      final on = _elements.world.localPositionOf(body.native).dot(_along);
      if (on > distance - behind) return false;
      _elements.remove(body);
      return true;
    });
  }

  /// Every fire put out, for a run starting the stretch again.
  void clear() {
    _burning.keys.forEach(_elements.remove);
    _burning.clear();
  }

  /// The wrecks held as a [SnapshotPart], under [id]: which bodies of the
  /// elements' world are wrecks, so a rewind, a rollback or the double-step
  /// check puts the list back with the world rather than leaving it holding
  /// bodies the world no longer has.
  ///
  /// **Registered after whatever restores the elements' world**, which the
  /// registry restores first in registration order: a wreck the snapshot
  /// held is kept only when that world has its body again. A wreck lit
  /// since is let go; one let go since, whose body the world has again, is
  /// taken back in and drawn as it was. What a body is doing — where it
  /// lies, how hot it is, how much is left to burn — is the world's to put
  /// back, and the flames held to it the elements' (`Elements.snapshotPart`).
  SnapshotPart snapshotPart({String id = 'flutter3d.game_physics.wrecks'}) =>
      SnapshotPart.of(id: id, capture: _capture, restore: _restore);

  Object? _capture() => <Object?>[
    for (final MapEntry(key: body, value: oil) in _burning.entries)
      <String, Object?>{'body': body.native.raw, 'oil': oil},
  ];

  void _restore(Object? data, int version) {
    final saved = <int, bool>{
      if (data is List<Object?>)
        for (final wreck in data)
          if (wreck case {'body': final int raw, 'oil': final bool oil})
            raw: oil,
    };
    final held = <int, TrackedBody>{
      for (final body in _burning.keys) body.native.raw: body,
    };
    for (final MapEntry(key: raw, value: body) in held.entries) {
      if (!saved.containsKey(raw)) _elements.remove(body);
    }
    final world = _elements.world;
    final restored = <TrackedBody, bool>{
      for (final MapEntry(key: raw, value: oil) in saved.entries)
        ?(held[raw] ?? _retrack(world, NativeBody(raw), oil: oil)): oil,
    };
    _burning
      ..clear()
      ..addAll(restored);
  }

  /// [native] taken back into the elements, drawn as a slick when [oil];
  /// null when the world does not have it.
  TrackedBody? _retrack(
    NativeWorld world,
    NativeBody native, {
    required bool oil,
  }) {
    if (!world.contains(native)) return null;
    final look = oil ? _slick() : null;
    return _elements.track(native, look: look, chars: look);
  }
}
