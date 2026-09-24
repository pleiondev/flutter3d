/// The dungeon's five levels: the crypt, the vaults, the deep, the cistern and
/// the sanctum.
///
/// **Edit these, not the JSON.** Each function is one level's arrangement and
/// returns its document; run `dart run tool/regenerate_levels.dart` from this
/// package and the files are identical unless something here changed — that
/// is what makes a generator rather than a description of what somebody once
/// did.
///
/// The `generatedBy` each document carries is the name its first generator
/// had. It is kept, not renamed to this file, because it is part of the
/// document and so of the level's digest, which recorded runs are checked
/// against; the registry in `shipped.dart` maps the name to the function.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'crypt_kit.dart';

const String _levels = 'apps/flutter3d_demo_dungeon/assets/levels';

RoomDoor _door(String side, double offset, double width, double height) =>
    RoomDoor(side, offset, width, height);

const double _east = -1.5708;
const double _west = 1.5708;
const List<num> _dawn = <num>[0.55, 0.78, 1.0];

/// The first level. It teaches in the order a player can absorb it: walk and
/// look; shoot one runner in a room seen whole; a locked door seen **before**
/// the key; a key down a side passage visible from the hall; leave. Nothing
/// here is a mechanism the player has to be told about — the lift, the button
/// and the moving platform are the second level's lesson.
///
/// ```
///                         [ vault ]  key, guarded
///                              |
///   [ hall ] —— [ guard room ] —— locked door —— [ stair ] —— exit
/// ```
Map<String, String> crypt(GeneratorSource _) {
  const tool = 'apps/flutter3d_demo_dungeon/tool/make_crypt.py';
  const hall = <num>[0.0, 0.0, 8.0];
  const guard = <num>[0.0, 0.0, -8.0];
  const vault = <num>[14.0, 0.0, -8.0];
  const stair = <num>[0.0, 0.0, -26.0];
  final k = CryptKit()
    // The hall. Light, and nothing else.
    ..room(hall, <num>[12.0, 0.0, 12.0], doors: [_door('north', 0.0, 4.0, 4.0)])
    ..spawn(<num>[0.0, 0.0, 12.0])
    ..torch(<num>[-5.4, 2.8, 10.0], name: 'hall_west', yaw: _west)
    ..torch(<num>[5.4, 2.8, 10.0], name: 'hall_east', yaw: _east)
    // On the wall beside the doorway rather than in the middle of it: the
    // hall's north wall's inner face is z = 2.0 and the doorway takes x from
    // −2 to 2, so this sits on the panel west of it, facing into the room.
    ..note(
      <num>[-3.5, 1.6, 2.03],
      'They sealed the lower door and took the key down with them. '
      'It is still down there.',
    )
    ..corridor(
      <num>[0.0, 0.0, 2.0],
      <num>[0.0, 0.0, -2.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('north', 0.0, 4.0, 4.0), _door('south', 0.0, 4.0, 4.0)],
    )
    // The guard room. One runner, seen from the doorway.
    ..room(
      guard,
      <num>[16.0, 0.0, 12.0],
      doors: [
        _door('south', 0.0, 4.0, 4.0), // back to the hall
        _door('north', 0.0, 6.0, 4.0), // the locked door
        _door('east', 0.0, 3.0, 3.0), // the side passage
      ],
    )
    ..torch(<num>[-7.4, 2.8, -8.0], name: 'guard_west', yaw: _west)
    ..torch(
      <num>[7.4, 2.8, -12.0],
      name: 'guard_east',
      yaw: _east,
      intensity: 5.0,
    )
    ..pillar(<num>[-4.0, 2.0, -10.0])
    ..pillar(<num>[4.0, 2.0, -10.0])
    // Far enough that the pistol is the right answer and the fists are not.
    ..monster('runner', <num>[0.0, 0.0, -12.0])
    ..pickup('health', <num>[-6.0, 0.8, -5.0], amount: 25)
    // The door before the key, straight ahead of the way in. Six wide
    // because at four the route from the vault arrives along the north wall
    // on a diagonal and wedges the player in the corner; and a doorway is as
    // wide as the narrowest thing sharing its wall, so the corridor behind it
    // is six too. Four tall, like the rooms.
    ..door(
      'crypt_door',
      <num>[0.0, 2.0, -14.0],
      key: 'iron',
      size: <num>[6.0, 4.0, 1.0],
      travel: <num>[0.0, 4.1, 0.0],
    )
    ..trigger('crypt_door', <num>[0.0, 1.5, -12.4], size: <num>[6.0, 3.0, 2.0])
    // The vault, through the guard room's east wall. No corridor between
    // them: two rooms whose walls land on the same plane share it, so an
    // opening cut from each side is one opening.
    ..room(vault, <num>[10.0, 0.0, 10.0], doors: [_door('west', 0.0, 3.0, 3.0)])
    ..torch(<num>[14.0, 2.8, -12.4], name: 'vault_north')
    // Guarded by the one that shoots: a corridor is cover.
    ..monster('shooter', <num>[16.0, 0.0, -10.0])
    ..pickup('bullets', <num>[11.0, 0.8, -6.0], amount: 20)
    ..key('iron', <num>[14.0, 0.9, -8.0])
    // Down, and out.
    ..corridor(
      <num>[0.0, 0.0, -15.0],
      <num>[0.0, 0.0, -20.0],
      width: 6.0,
      height: 4.0,
      doors: [_door('north', 0.0, 6.0, 4.0), _door('south', 0.0, 6.0, 4.0)],
    )
    ..room(
      stair,
      <num>[10.0, 0.0, 12.0],
      height: 6.0,
      doors: [_door('south', 0.0, 6.0, 4.0)],
    )
    ..torch(
      <num>[-4.4, 3.0, -28.0],
      name: 'stair_west',
      yaw: _west,
      colour: _dawn,
      intensity: 5.0,
    )
    ..pickup('armour', <num>[3.0, 0.8, -24.0], amount: 25)
    ..exitAt('way_down', <num>[0.0, 0.0, -30.0])
    ..widgetSurface(
      'run-terminal',
      <num>[1.4, 1.6, 10.0],
      widget: 'run-terminal',
      yaw: 3.14159265,
    );
  return <String, String>{
    '$_levels/crypt.json': k.write(
      file: 'crypt.json',
      name: 'The Crypt',
      next: 'assets/levels/vaults.json',
      tool: tool,
    ),
  };
}

/// The second level, where the game stops being a corridor: a crossroads
/// with a key in each wing and one door that wants both, so a player who walks
/// in a straight line runs out of level and has to look. The mechanisms the
/// crypt deliberately lacked are here, one per wing, so each is met alone.
///
/// ```
///    [ west wing ]        [ landing ]        [ east wing ]
///      brass key    ——   crossroads   ——      iron key
///                             |
///                        double door
///                             |
///                        [ shaft ]  lift, button, exit
/// ```
Map<String, String> vaults(GeneratorSource _) {
  const tool = 'apps/flutter3d_demo_dungeon/tool/make_vaults.py';
  const landing = <num>[0.0, 0.0, 6.0];
  const cross = <num>[0.0, 0.0, -8.0];
  const west = <num>[-20.0, 0.0, -8.0];
  const east = <num>[20.0, 0.0, -8.0];
  const shaft = <num>[0.0, 0.0, -26.0];
  final k = CryptKit()
    ..room(
      landing,
      <num>[10.0, 0.0, 10.0],
      doors: [_door('north', 0.0, 4.0, 4.0)],
    )
    ..spawn(<num>[0.0, 0.0, 9.0])
    ..torch(<num>[-4.4, 2.8, 8.0], name: 'landing_west', yaw: _west)
    ..torch(<num>[4.4, 2.8, 8.0], name: 'landing_east', yaw: _east)
    ..note(
      <num>[-3.5, 1.6, 1.03],
      'Two locks, and they gave a key to each of the wings. '
      'Neither warden trusted the other.',
    )
    ..corridor(
      <num>[0.0, 0.0, 1.0],
      <num>[0.0, 0.0, -2.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('north', 0.0, 4.0, 4.0), _door('south', 0.0, 4.0, 4.0)],
    )
    // The crossroads, taller than the rest: the double door is five high.
    ..room(
      cross,
      <num>[14.0, 0.0, 12.0],
      height: 5.0,
      doors: [
        _door('south', 0.0, 4.0, 4.0),
        _door('west', 0.0, 4.0, 4.0),
        _door('east', 0.0, 4.0, 4.0),
        _door('north', 0.0, 6.0, 5.0),
      ],
    )
    ..lamp(
      <num>[0.0, 4.2, -8.0],
      name: 'cross_lamp',
      intensity: 6.0,
      range: 16.0,
    )
    ..pillar(<num>[-5.0, 2.5, -4.0], size: <num>[1.2, 5.0, 1.2])
    ..pillar(<num>[5.0, 2.5, -4.0], size: <num>[1.2, 5.0, 1.2])
    ..pickup('health', <num>[0.0, 0.8, -4.0], amount: 25)
    ..pickup('sensor', <num>[2.0, 0.8, -4.0], amount: 30)
    // Two doors, one behind the other, one key each.
    ..door(
      'vault_door',
      <num>[0.0, 2.5, -14.0],
      key: 'brass',
      size: <num>[6.0, 5.0, 1.0],
      travel: <num>[0.0, 4.6, 0.0],
    )
    ..door(
      'vault_inner',
      <num>[0.0, 2.5, -17.0],
      key: 'iron',
      size: <num>[6.0, 5.0, 1.0],
      travel: <num>[0.0, 4.6, 0.0],
    )
    // The west wing: runners and corners, and a moving platform.
    ..corridor(
      <num>[-7.0, 0.0, -8.0],
      <num>[-13.0, 0.0, -8.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('east', 0.0, 4.0, 4.0), _door('west', 0.0, 4.0, 4.0)],
    )
    ..room(west, <num>[14.0, 0.0, 14.0], doors: [_door('east', 0.0, 4.0, 4.0)])
    ..torch(<num>[-25.4, 2.8, -8.0], name: 'west_far', yaw: _west)
    ..torch(<num>[-20.0, 2.8, -14.4], name: 'west_north')
    ..pillar(<num>[-16.0, 2.0, -12.0])
    ..pillar(<num>[-24.0, 2.0, -4.0])
    ..monster('runner', <num>[-22.0, 0.0, -12.0])
    ..monster('runner', <num>[-17.0, 0.0, -4.0])
    ..platform(
      'west_ferry',
      <num>[-20.0, 0.3, -8.0],
      travel: <num>[0.0, 0.0, -4.0],
    )
    ..pickup('shells', <num>[-24.0, 0.8, -11.0], amount: 8)
    ..key('brass', <num>[-20.0, 0.9, -13.0])
    // The east wing: shooters and long sight lines.
    ..corridor(
      <num>[7.0, 0.0, -8.0],
      <num>[13.0, 0.0, -8.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('west', 0.0, 4.0, 4.0), _door('east', 0.0, 4.0, 4.0)],
    )
    ..room(east, <num>[14.0, 0.0, 20.0], doors: [_door('west', 0.0, 4.0, 4.0)])
    ..torch(<num>[25.4, 2.8, -2.0], name: 'east_near', yaw: _east)
    ..torch(<num>[25.4, 2.8, -14.0], name: 'east_far', yaw: _east)
    ..pillar(<num>[17.0, 2.0, -6.0])
    ..pillar(<num>[23.0, 2.0, -10.0])
    ..monster('shooter', <num>[20.0, 0.0, -15.0])
    ..monster('shooter', <num>[24.0, 0.0, -2.0])
    ..monster('runner', <num>[16.0, 0.0, -12.0])
    ..pickup('bullets', <num>[17.0, 0.8, -2.0], amount: 20)
    ..pickup('armour', <num>[24.0, 0.8, -16.0], amount: 25)
    ..key('iron', <num>[20.0, 0.9, -16.0])
    // The shaft: a lift, the button that calls it, and the way on above.
    ..corridor(
      <num>[0.0, 0.0, -15.0],
      <num>[0.0, 0.0, -20.0],
      width: 6.0,
      height: 5.0,
      doors: [_door('north', 0.0, 6.0, 5.0), _door('south', 0.0, 6.0, 5.0)],
    )
    ..room(
      shaft,
      <num>[12.0, 0.0, 12.0],
      height: 8.0,
      doors: [_door('south', 0.0, 6.0, 5.0)],
    )
    ..torch(
      <num>[-5.4, 3.0, -26.0],
      name: 'shaft_west',
      yaw: _west,
      colour: _dawn,
      intensity: 5.0,
    )
    ..lift(
      'shaft_lift',
      <num>[0.0, 0.25, -28.0],
      size: <num>[3.0, 0.5, 3.0],
      travel: <num>[0.0, 4.0, 0.0],
      speed: 1.4,
      wait: 5.0,
    )
    ..button('shaft_lift', <num>[0.0, 1.5, -31.4], size: <num>[0.7, 0.7, 0.25])
    ..pickup('health', <num>[-4.0, 0.8, -23.0], amount: 25)
    ..exitAt('deeper', <num>[0.0, 4.5, -28.0]);
  return <String, String>{
    '$_levels/vaults.json': k.write(
      file: 'vaults.json',
      name: 'The Vaults',
      next: 'assets/levels/deep.json',
      tool: tool,
    ),
  };
}

/// The third level, which asks **which weapon** by taking away the freedom to
/// answer wrong: small rooms, slow hard tanks, less ammunition on the floor
/// than the fight in front of it, and a rocket that hurts whoever fires it in
/// a room this size. No keys, no lift, no crossroads. The way out is still
/// called `the_surface`, from when this was the end of the game.
Map<String, String> deep(GeneratorSource _) {
  const tool = 'apps/flutter3d_demo_dungeon/tool/make_deep.py';
  const arrival = <num>[0.0, 0.0, 4.0];
  const first = <num>[0.0, 0.0, -8.0];
  const narrow = <num>[0.0, 0.0, -20.0];
  const last = <num>[0.0, 0.0, -34.0];
  List<RoomDoor> through() => [
    _door('north', 0.0, 3.0, 3.0),
    _door('south', 0.0, 3.0, 3.0),
  ];
  final k = CryptKit()
    // Arrival. Small, and the only quiet room in the level.
    ..room(
      arrival,
      <num>[8.0, 0.0, 8.0],
      height: 3.5,
      doors: [_door('north', 0.0, 3.0, 3.0)],
    )
    ..spawn(<num>[0.0, 0.0, 6.0])
    ..torch(
      <num>[-3.4, 2.4, 5.0],
      name: 'arrival_west',
      yaw: _west,
      colour: _dawn,
      intensity: 4.5,
    )
    ..note(<num>[
      -2.5,
      1.6,
      0.03,
    ], 'Nothing below here was buried. It came down on its own.')
    ..pickup('shells', <num>[2.5, 0.8, 6.0], amount: 8)
    // The first room. One tank, and nowhere to back away to.
    ..corridor(
      <num>[0.0, 0.0, -0.5],
      <num>[0.0, 0.0, -3.0],
      width: 3.0,
      height: 3.0,
      doors: through(),
    )
    ..room(
      first,
      <num>[10.0, 0.0, 8.0],
      height: 3.5,
      doors: [_door('south', 0.0, 3.0, 3.0), _door('north', 0.0, 3.0, 3.0)],
    )
    ..torch(
      <num>[4.4, 2.4, -8.0],
      name: 'first_east',
      yaw: _east,
      intensity: 4.0,
    )
    ..pillar(<num>[0.0, 1.75, -10.0], size: <num>[1.6, 3.5, 1.6])
    // Behind the pillar, so the room is entered before it is seen.
    ..monster('tank', <num>[0.0, 0.0, -11.0])
    ..pickup('health', <num>[-4.0, 0.8, -6.0], amount: 25)
    // The narrows. Two rooms wide enough to fight in and no more.
    ..corridor(
      <num>[0.0, 0.0, -12.5],
      <num>[0.0, 0.0, -15.0],
      width: 3.0,
      height: 3.0,
      doors: through(),
    )
    ..room(
      narrow,
      <num>[12.0, 0.0, 10.0],
      height: 3.5,
      doors: [_door('south', 0.0, 3.0, 3.0), _door('north', 0.0, 3.0, 3.0)],
    )
    ..torch(
      <num>[-5.4, 2.4, -17.0],
      name: 'narrow_west',
      yaw: _west,
      intensity: 4.0,
    )
    ..torch(
      <num>[5.4, 2.4, -23.0],
      name: 'narrow_east',
      yaw: _east,
      intensity: 4.0,
    )
    ..pillar(<num>[-3.0, 1.75, -20.0], size: <num>[1.4, 3.5, 1.4])
    ..pillar(<num>[3.0, 1.75, -20.0], size: <num>[1.4, 3.5, 1.4])
    ..monster('tank', <num>[-4.0, 0.0, -23.0])
    ..monster('shooter', <num>[4.0, 0.0, -17.0])
    ..monster('runner', <num>[4.0, 0.0, -23.0])
    // The only bullets in the level, and not enough of them: the shells
    // behind you are the answer, which is the point.
    ..pickup('bullets', <num>[0.0, 0.8, -17.0], amount: 20)
    // The last room. Everything at once, and the way out behind it.
    ..corridor(
      <num>[0.0, 0.0, -25.5],
      <num>[0.0, 0.0, -28.0],
      width: 3.0,
      height: 3.0,
      doors: through(),
    )
    ..room(
      last,
      <num>[16.0, 0.0, 12.0],
      height: 5.0,
      doors: [_door('south', 0.0, 3.0, 3.0)],
    )
    ..lamp(
      <num>[0.0, 4.2, -34.0],
      name: 'last_lamp',
      colour: _dawn,
      intensity: 6.0,
      range: 18.0,
    )
    ..pillar(<num>[-5.0, 2.5, -31.0], size: <num>[1.4, 5.0, 1.4])
    ..pillar(<num>[5.0, 2.5, -31.0], size: <num>[1.4, 5.0, 1.4])
    ..monster('tank', <num>[-6.0, 0.0, -37.0])
    ..monster('tank', <num>[6.0, 0.0, -37.0])
    ..monster('shooter', <num>[0.0, 0.0, -38.0])
    // Rockets, here and nowhere else: the first room big enough that firing
    // one is not also hitting yourself.
    ..pickup('rockets', <num>[0.0, 0.8, -30.0], amount: 4)
    ..pickup('armour', <num>[-7.0, 0.8, -30.0], amount: 25)
    ..exitAt('the_surface', <num>[0.0, 0.0, -39.0]);
  return <String, String>{
    '$_levels/deep.json': k.write(
      file: 'deep.json',
      name: 'The Deep',
      next: 'assets/levels/cistern.json',
      tool: tool,
    ),
  };
}

/// The fourth level. The deep took the rocket launcher away by making every
/// room too small; this gives the room back and takes the floor instead. The
/// middle is a flooded basin a metre and a fifth below everything around it,
/// a pier runs in from each doorway and ends in steps down into the water, and
/// the fight is about **height**. Two keys, one per wing, both across the
/// water — and the game's first secret, at the water line behind a pillar.
///
/// ```
///                          [ drain ] —— locked (iron) —— [ outflow ] exit
///                              |
///                       locked (brass)
///                              |
///    [ sluice ] ——pier—— [ b a s i n ] ——pier—— [ pump room ]
///     brass key           water, tanks             iron key
///                              |
///                         [ landing ]
/// ```
Map<String, String> cistern(GeneratorSource _) {
  const tool = 'apps/flutter3d_demo_dungeon/tool/make_cistern.py';
  // How far the basin's floor is below everything around it: enough to wade
  // and to be looked down on, not enough to need swimming.
  const depth = 1.2;
  const fog = <num>[0.024, 0.036, 0.034];
  const landing = <num>[0.0, 0.0, 14.0];
  const basin = <num>[0.0, 0.0, -6.0];
  const alcove = <num>[-15.0, 0.0, 2.0];
  const sluice = <num>[-19.0, 0.0, -6.0];
  const pump = <num>[19.0, 0.0, -6.0];
  const drain = <num>[0.0, 0.0, -28.0];
  const outflow = <num>[0.0, 0.0, -43.0];
  const wet = <num>[0.5, 0.85, 0.8];
  RoomDoor sill(String side, double offset, double width, double height) =>
      RoomDoor(side, offset, width, height, sill: 0.0);

  final k = CryptKit()
    ..room(
      landing,
      <num>[10.0, 0.0, 8.0],
      doors: [_door('north', 0.0, 4.0, 4.0)],
    )
    ..spawn(<num>[0.0, 0.0, 16.0])
    ..torch(<num>[-4.4, 2.8, 14.0], name: 'landing_west', yaw: _west)
    ..torch(<num>[4.4, 2.8, 14.0], name: 'landing_east', yaw: _east)
    ..note(
      <num>[-3.5, 1.6, 10.03],
      'The wardens flooded the cistern to keep what is in it from climbing '
      'out. It did not work.',
    )
    ..pickup('shells', <num>[3.0, 0.8, 12.0], amount: 8)
    ..corridor(
      <num>[0.0, 0.0, 9.0],
      <num>[0.0, 0.0, 5.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('north', 0.0, 4.0, 4.0), _door('south', 0.0, 4.0, 4.0)],
    )
    // The basin: its floor sunk, its walls up to the same ceiling as the
    // rooms around it, and its doorways starting at their floors, not its.
    ..room(
      basin,
      <num>[24.0, 0.0, 20.0],
      base: -depth,
      height: 6.2,
      doors: [
        sill('south', 0.0, 4.0, 4.0), // the landing
        sill('west', 0.0, 4.0, 4.0), // the sluice
        sill('east', 0.0, 4.0, 4.0), // the pump room
        sill('north', 0.0, 6.0, 4.0), // the locked gate
        _door('west', 8.0, 1.2, 2.4), // the secret, floor to lintel
      ],
    )
    ..block(
      <num>[0.0, -depth + 0.325, -6.0],
      <num>[24.0, 0.05, 20.0],
      'water',
      solid: false,
      casts: false,
    )
    // A pier from each doorway, and a flight down into the water.
    ..block(<num>[0.0, -depth / 2.0, 1.5], <num>[4.0, depth, 5.0], 'stone')
    ..stair(
      <num>[0.0, 0.0, -0.5],
      <num>[0.0, -depth, -4.5],
      steps: 4,
      bottom: -depth,
    )
    ..block(<num>[-10.0, -depth / 2.0, -6.0], <num>[4.0, depth, 4.0], 'stone')
    ..stair(
      <num>[-8.5, 0.0, -6.0],
      <num>[-4.5, -depth, -6.0],
      steps: 4,
      bottom: -depth,
    )
    ..block(<num>[10.0, -depth / 2.0, -6.0], <num>[4.0, depth, 4.0], 'stone')
    ..stair(
      <num>[8.5, 0.0, -6.0],
      <num>[4.5, -depth, -6.0],
      steps: 4,
      bottom: -depth,
    )
    ..block(<num>[0.0, -depth / 2.0, -14.0], <num>[6.0, depth, 4.0], 'stone')
    ..stair(
      <num>[0.0, 0.0, -12.5],
      <num>[0.0, -depth, -8.5],
      steps: 4,
      bottom: -depth,
    );
  // Columns standing in the water, the last of them hiding the secret.
  for (final (x, z) in const <(double, double)>[
    (-6.0, -2.0),
    (6.0, -2.0),
    (-6.0, -10.0),
    (6.0, -10.0),
    (-10.0, 2.0),
  ]) {
    k.pillar(<num>[x, -depth + 3.1, z], size: <num>[1.4, 6.2, 1.4]);
  }
  k
    ..lamp(
      <num>[0.0, 4.0, -6.0],
      name: 'basin_lamp',
      colour: wet,
      intensity: 6.0,
      range: 18.0,
    )
    ..torch(<num>[-11.4, 2.0, -12.0], name: 'basin_northwest', yaw: _west)
    ..torch(<num>[11.4, 2.0, -12.0], name: 'basin_northeast', yaw: _east)
    ..torch(
      <num>[-11.4, 2.0, 0.0],
      name: 'basin_southwest',
      yaw: _west,
      intensity: 5.0,
    )
    ..torch(
      <num>[11.4, 2.0, 0.0],
      name: 'basin_southeast',
      yaw: _east,
      intensity: 5.0,
    )
    // Tanks wading, shooters on the piers: the high ground is where the
    // fire comes from.
    ..monster('tank', <num>[0.0, -depth, -6.0])
    ..monster('tank', <num>[-4.0, -depth, -12.0])
    ..monster('shooter', <num>[-2.0, 0.0, -14.0])
    ..monster('shooter', <num>[10.0, 0.0, -7.0])
    ..monster('runner', <num>[8.0, -depth, -1.0])
    ..monster('runner', <num>[-8.0, -depth, -11.0])
    ..pickup('health', <num>[4.0, -depth + 0.8, 2.0], amount: 25)
    ..pickup('shells', <num>[-4.0, -depth + 0.8, -13.0], amount: 8)
    ..door(
      'sluice_gate',
      <num>[0.0, 2.0, -16.0],
      key: 'brass',
      size: <num>[6.0, 4.0, 1.0],
      travel: <num>[0.0, 4.1, 0.0],
    )
    ..trigger('sluice_gate', <num>[0.0, 1.5, -14.4], size: <num>[6.0, 3.0, 2.0])
    // The secret: an opening a metre wide at the water line, with the
    // rockets the rest of the level is short of.
    ..room(
      alcove,
      <num>[4.0, 0.0, 4.0],
      base: -depth,
      height: 3.0,
      doors: [_door('east', 0.0, 1.2, 2.4)],
    )
    ..torch(
      <num>[-16.4, 1.0, 2.0],
      name: 'alcove',
      yaw: _west,
      colour: wet,
      intensity: 3.0,
      range: 8.0,
    )
    ..secret(<num>[-15.0, -depth + 1.25, 2.0])
    ..pickup('rockets', <num>[-15.0, -depth + 0.8, 2.0], amount: 4)
    ..pickup('armour', <num>[-16.0, -depth + 0.8, 1.0], amount: 25)
    // The sluice: the brass key.
    ..room(
      sluice,
      <num>[12.0, 0.0, 10.0],
      doors: [_door('east', 0.0, 4.0, 4.0)],
    )
    ..torch(<num>[-24.4, 2.8, -6.0], name: 'sluice_west', yaw: _west)
    ..torch(<num>[-19.0, 2.8, -10.4], name: 'sluice_north')
    ..pillar(<num>[-17.0, 2.0, -9.0])
    ..pillar(<num>[-21.0, 2.0, -6.0])
    ..monster('shooter', <num>[-22.0, 0.0, -9.0])
    ..monster('shooter', <num>[-22.0, 0.0, -3.0])
    ..monster('runner', <num>[-16.0, 0.0, -2.0])
    ..pickup('shells', <num>[-15.0, 0.8, -9.0], amount: 8)
    ..pickup('health', <num>[-23.0, 0.8, -2.0], amount: 25)
    ..key('brass', <num>[-23.0, 0.9, -6.0])
    // The pump room: the iron key, on a plinth.
    ..room(
      pump,
      <num>[12.0, 0.0, 12.0],
      height: 5.0,
      doors: [_door('west', 0.0, 4.0, 4.0)],
    )
    ..lamp(
      <num>[19.0, 4.2, -6.0],
      name: 'pump_lamp',
      intensity: 5.0,
      range: 14.0,
    )
    ..torch(<num>[24.4, 3.0, -9.0], name: 'pump_northeast', yaw: _east)
    ..torch(<num>[24.4, 3.0, -3.0], name: 'pump_southeast', yaw: _east)
    ..pillar(<num>[16.0, 2.5, -3.0], size: <num>[1.2, 5.0, 1.2])
    ..pillar(<num>[16.0, 2.5, -9.0], size: <num>[1.2, 5.0, 1.2])
    ..block(<num>[22.0, 0.15, -6.0], <num>[4.0, 0.3, 4.0], 'stone')
    ..monster('tank', <num>[22.0, 0.0, -10.0])
    ..monster('tank', <num>[22.0, 0.0, -2.0])
    ..monster('shooter', <num>[16.0, 0.0, -10.0])
    ..pickup('bullets', <num>[15.0, 0.8, -1.0], amount: 20)
    ..pickup('rockets', <num>[24.0, 0.8, -11.0], amount: 2)
    ..pickup('health', <num>[24.0, 0.8, -1.0], amount: 25)
    ..key('iron', <num>[22.0, 1.2, -6.0])
    // The drain, behind the brass gate.
    ..corridor(
      <num>[0.0, 0.0, -17.0],
      <num>[0.0, 0.0, -22.0],
      width: 6.0,
      height: 4.0,
      doors: [_door('north', 0.0, 6.0, 4.0), _door('south', 0.0, 6.0, 4.0)],
    )
    ..room(
      drain,
      <num>[12.0, 0.0, 10.0],
      doors: [_door('south', 0.0, 6.0, 4.0), _door('north', 0.0, 4.0, 4.0)],
    )
    ..torch(
      <num>[-5.4, 2.8, -25.0],
      name: 'drain_west',
      yaw: _west,
      colour: wet,
      intensity: 5.0,
    )
    ..torch(
      <num>[5.4, 2.8, -31.0],
      name: 'drain_east',
      yaw: _east,
      colour: wet,
      intensity: 5.0,
    )
    ..pillar(<num>[-3.0, 2.0, -28.0])
    ..pillar(<num>[3.0, 2.0, -28.0])
    ..monster('tank', <num>[0.0, 0.0, -30.0])
    ..monster('runner', <num>[-4.0, 0.0, -25.0])
    ..monster('runner', <num>[4.0, 0.0, -31.0])
    ..pickup('health', <num>[-4.0, 0.8, -24.0], amount: 25)
    ..pickup('shells', <num>[4.0, 0.8, -24.0], amount: 8)
    ..pickup('armour', <num>[-4.0, 0.8, -31.0], amount: 25)
    ..door(
      'outflow_gate',
      <num>[0.0, 2.0, -33.0],
      key: 'iron',
      size: <num>[4.0, 4.0, 1.0],
      travel: <num>[0.0, 4.1, 0.0],
    )
    ..trigger(
      'outflow_gate',
      <num>[0.0, 1.5, -31.4],
      size: <num>[4.0, 3.0, 2.0],
    )
    // The outflow, and the way on.
    ..corridor(
      <num>[0.0, 0.0, -34.0],
      <num>[0.0, 0.0, -38.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('north', 0.0, 4.0, 4.0), _door('south', 0.0, 4.0, 4.0)],
    )
    ..room(
      outflow,
      <num>[10.0, 0.0, 8.0],
      height: 5.0,
      doors: [_door('south', 0.0, 4.0, 4.0)],
    )
    ..torch(
      <num>[-4.4, 3.0, -43.0],
      name: 'outflow_west',
      yaw: _west,
      colour: _dawn,
      intensity: 5.0,
    )
    ..pickup('armour', <num>[3.0, 0.8, -41.0], amount: 25)
    ..exitAt('the_sanctum', <num>[0.0, 0.0, -45.0]);
  return <String, String>{
    '$_levels/cistern.json': k.write(
      file: 'cistern.json',
      name: 'The Cistern',
      fog: fog,
      next: 'assets/levels/sanctum.json',
      extra: const <String, Row>{'water': CryptKit.water},
      tool: tool,
    ),
  };
}

/// The last level. Everything the game taught, in the biggest rooms it has:
/// a nave with a wing to each side and a key in each, two gates one behind
/// the other, a choir, and an altar hall thirty-two metres across under a
/// grid of reflection probes — the room `LevelSketch.probeReach` was written
/// for. A second secret, behind a column in the reliquary.
Map<String, String> sanctum(GeneratorSource _) {
  const tool = 'apps/flutter3d_demo_dungeon/tool/make_sanctum.py';
  const vestibule = <num>[0.0, 0.0, 14.0];
  const nave = <num>[0.0, 0.0, -8.0];
  const reliquary = <num>[-21.0, 0.0, -12.0];
  const hidden = <num>[-19.0, 0.0, -21.0];
  const wardens = <num>[21.0, 0.0, -12.0];
  const choir = <num>[0.0, 0.0, -33.0];
  const altar = <num>[0.0, 0.0, -58.0];
  const candle = <num>[1.0, 0.85, 0.55];

  final k = CryptKit()
    ..room(
      vestibule,
      <num>[10.0, 0.0, 8.0],
      doors: [_door('north', 0.0, 4.0, 4.0)],
    )
    ..spawn(<num>[0.0, 0.0, 16.0])
    ..torch(<num>[-4.4, 2.8, 14.0], name: 'vestibule_west', yaw: _west)
    ..torch(<num>[4.4, 2.8, 14.0], name: 'vestibule_east', yaw: _east)
    ..note(
      <num>[-3.5, 1.6, 10.03],
      'Two wardens kept the sanctum, and they kept its keys apart, '
      'as they always did. What they kept it from is still in it.',
    )
    ..pickup('health', <num>[3.0, 0.8, 12.0], amount: 25)
    ..corridor(
      <num>[0.0, 0.0, 9.0],
      <num>[0.0, 0.0, 5.0],
      width: 4.0,
      height: 4.0,
      doors: [_door('north', 0.0, 4.0, 4.0), _door('south', 0.0, 4.0, 4.0)],
    )
    ..room(
      nave,
      <num>[28.0, 0.0, 24.0],
      height: 7.0,
      doors: [
        _door('south', 0.0, 4.0, 4.0),
        _door('west', -4.0, 4.0, 4.0), // the reliquary
        _door('east', -4.0, 4.0, 4.0), // the wardens' crypt
        _door('north', 0.0, 8.0, 5.0), // the great door
      ],
    );
  for (final x in const <double>[-6.0, 6.0]) {
    for (final z in const <double>[-16.0, -10.0, -4.0]) {
      k.pillar(<num>[x, 3.5, z], size: <num>[1.6, 7.0, 1.6]);
    }
  }
  k
    ..lamp(
      <num>[0.0, 6.2, -14.0],
      name: 'nave_north',
      colour: candle,
      intensity: 7.0,
      range: 20.0,
    )
    ..lamp(
      <num>[0.0, 6.2, -2.0],
      name: 'nave_south',
      colour: candle,
      intensity: 7.0,
      range: 20.0,
    )
    ..torch(<num>[-13.4, 3.0, -4.0], name: 'nave_southwest', yaw: _west)
    ..torch(<num>[13.4, 3.0, -4.0], name: 'nave_southeast', yaw: _east)
    ..torch(<num>[-13.4, 3.0, -16.0], name: 'nave_northwest', yaw: _west)
    ..torch(<num>[13.4, 3.0, -16.0], name: 'nave_northeast', yaw: _east)
    ..monster('tank', <num>[0.0, 0.0, -12.0])
    ..monster('shooter', <num>[-10.0, 0.0, -18.0])
    ..monster('shooter', <num>[10.0, 0.0, -18.0])
    ..monster('runner', <num>[-10.0, 0.0, -2.0])
    ..monster('runner', <num>[10.0, 0.0, -2.0])
    ..monster('runner', <num>[0.0, 0.0, -17.0])
    ..pickup('health', <num>[-12.0, 0.8, 2.0], amount: 25)
    ..pickup('shells', <num>[12.0, 0.8, 2.0], amount: 8)
    ..pickup('bullets', <num>[-3.0, 0.8, -7.0], amount: 20)
    ..pickup('armour', <num>[3.0, 0.8, -7.0], amount: 25)
    // The great door, twice: brass, then iron.
    ..door(
      'sanctum_door',
      <num>[0.0, 2.5, -20.0],
      key: 'brass',
      size: <num>[8.0, 5.0, 1.0],
      travel: <num>[0.0, 4.6, 0.0],
    )
    ..trigger(
      'sanctum_door',
      <num>[0.0, 1.5, -18.4],
      size: <num>[8.0, 3.0, 2.0],
    )
    ..door(
      'sanctum_inner',
      <num>[0.0, 2.5, -24.0],
      key: 'iron',
      size: <num>[8.0, 5.0, 1.0],
      travel: <num>[0.0, 4.6, 0.0],
    )
    ..trigger(
      'sanctum_inner',
      <num>[0.0, 1.5, -22.4],
      size: <num>[8.0, 3.0, 2.0],
    )
    // The reliquary: the brass key, and the secret behind the column.
    ..room(
      reliquary,
      <num>[12.0, 0.0, 10.0],
      doors: [
        _door('east', 0.0, 4.0, 4.0),
        _door('north', 3.0, 1.2, 2.4), // the secret, behind the column
      ],
    )
    ..torch(<num>[-26.4, 2.8, -9.0], name: 'reliquary_west', yaw: _west)
    ..torch(<num>[-21.0, 2.8, -7.6], name: 'reliquary_south', yaw: 3.1416)
    ..pillar(<num>[-18.0, 2.0, -15.0])
    ..monster('tank', <num>[-22.0, 0.0, -12.0])
    ..monster('shooter', <num>[-25.0, 0.0, -9.0])
    ..monster('shooter', <num>[-25.0, 0.0, -15.0])
    ..pickup('armour', <num>[-16.0, 0.8, -8.0], amount: 25)
    ..pickup('shells', <num>[-26.0, 0.8, -16.0], amount: 8)
    ..key('brass', <num>[-26.0, 0.9, -12.0])
    ..room(
      hidden,
      <num>[6.0, 0.0, 6.0],
      height: 3.0,
      doors: [_door('south', 1.0, 1.2, 2.4)],
    )
    ..torch(
      <num>[-21.4, 2.0, -21.0],
      name: 'hidden',
      yaw: _west,
      colour: candle,
      intensity: 3.5,
      range: 8.0,
    )
    ..secret(<num>[-19.0, 1.25, -21.0])
    ..pickup('rockets', <num>[-19.0, 0.8, -22.0], amount: 8)
    ..pickup('armour', <num>[-17.0, 0.8, -22.0], amount: 25)
    ..pickup('health', <num>[-21.0, 0.8, -22.0], amount: 25)
    // The wardens' crypt: the iron key, on a plinth.
    ..room(
      wardens,
      <num>[12.0, 0.0, 10.0],
      doors: [_door('west', 0.0, 4.0, 4.0)],
    )
    ..torch(<num>[26.4, 2.8, -9.0], name: 'wardens_northeast', yaw: _east)
    ..torch(<num>[26.4, 2.8, -15.0], name: 'wardens_southeast', yaw: _east)
    ..pillar(<num>[18.0, 2.0, -9.0])
    ..pillar(<num>[18.0, 2.0, -15.0])
    ..block(<num>[25.0, 0.15, -12.0], <num>[3.0, 0.3, 3.0], 'stone')
    ..monster('tank', <num>[22.0, 0.0, -9.0])
    ..monster('tank', <num>[22.0, 0.0, -15.0])
    ..monster('shooter', <num>[18.0, 0.0, -12.0])
    ..pickup('shells', <num>[16.0, 0.8, -8.0], amount: 8)
    ..pickup('health', <num>[26.0, 0.8, -8.0], amount: 25)
    ..pickup('bullets', <num>[26.0, 0.8, -16.0], amount: 20)
    ..key('iron', <num>[25.0, 1.2, -12.0])
    // The choir.
    ..corridor(
      <num>[0.0, 0.0, -21.0],
      <num>[0.0, 0.0, -27.0],
      width: 8.0,
      height: 5.0,
      doors: [_door('north', 0.0, 8.0, 5.0), _door('south', 0.0, 8.0, 5.0)],
    )
    ..room(
      choir,
      <num>[16.0, 0.0, 10.0],
      height: 5.0,
      doors: [_door('south', 0.0, 8.0, 5.0), _door('north', 0.0, 6.0, 5.0)],
    )
    ..lamp(
      <num>[0.0, 4.2, -33.0],
      name: 'choir_lamp',
      colour: candle,
      intensity: 5.0,
      range: 14.0,
    )
    ..pillar(<num>[-4.0, 2.5, -33.0], size: <num>[1.2, 5.0, 1.2])
    ..pillar(<num>[4.0, 2.5, -33.0], size: <num>[1.2, 5.0, 1.2])
    ..monster('shooter', <num>[-6.0, 0.0, -36.0])
    ..monster('shooter', <num>[6.0, 0.0, -36.0])
    ..monster('runner', <num>[-6.0, 0.0, -30.0])
    ..monster('runner', <num>[6.0, 0.0, -30.0])
    ..pickup('rockets', <num>[0.0, 0.8, -33.0], amount: 4)
    ..pickup('health', <num>[-7.0, 0.8, -33.0], amount: 25)
    ..pickup('armour', <num>[7.0, 0.8, -33.0], amount: 25)
    // The altar hall.
    ..corridor(
      <num>[0.0, 0.0, -39.0],
      <num>[0.0, 0.0, -43.0],
      width: 6.0,
      height: 5.0,
      doors: [_door('north', 0.0, 6.0, 5.0), _door('south', 0.0, 6.0, 5.0)],
    )
    ..room(
      altar,
      <num>[32.0, 0.0, 28.0],
      height: 9.0,
      doors: [_door('south', 0.0, 6.0, 5.0)],
    );
  for (final x in const <double>[-9.0, 9.0]) {
    for (final z in const <double>[-48.0, -54.0, -60.0, -66.0]) {
      k.pillar(<num>[x, 4.5, z], size: <num>[1.8, 9.0, 1.8]);
    }
  }
  k
    ..lamp(
      <num>[0.0, 8.2, -50.0],
      name: 'altar_south',
      colour: candle,
      intensity: 9.0,
      range: 24.0,
    )
    ..lamp(
      <num>[0.0, 8.2, -64.0],
      name: 'altar_north',
      colour: candle,
      intensity: 9.0,
      range: 24.0,
    )
    ..torch(<num>[-15.4, 3.5, -48.0], name: 'altar_southwest', yaw: _west)
    ..torch(<num>[15.4, 3.5, -48.0], name: 'altar_southeast', yaw: _east)
    ..torch(<num>[-15.4, 3.5, -68.0], name: 'altar_northwest', yaw: _west)
    ..torch(<num>[15.4, 3.5, -68.0], name: 'altar_northeast', yaw: _east)
    ..torch(
      <num>[0.0, 3.0, -71.4],
      name: 'dawn',
      colour: _dawn,
      intensity: 6.0,
      range: 16.0,
    )
    // The altar: three steps of dais.
    ..block(<num>[0.0, 0.15, -64.0], <num>[16.0, 0.3, 12.0], 'stone')
    ..block(<num>[0.0, 0.45, -64.0], <num>[14.0, 0.3, 10.0], 'stone')
    ..block(<num>[0.0, 0.75, -64.0], <num>[12.0, 0.3, 8.0], 'stone')
    ..monster('tank', <num>[-4.0, 0.9, -65.0])
    ..monster('tank', <num>[4.0, 0.9, -65.0])
    ..monster('tank', <num>[0.0, 0.9, -62.0])
    ..monster('shooter', <num>[-12.0, 0.0, -66.0])
    ..monster('shooter', <num>[12.0, 0.0, -66.0])
    ..monster('shooter', <num>[0.0, 0.0, -71.0])
    ..monster('runner', <num>[-13.0, 0.0, -47.0])
    ..monster('runner', <num>[13.0, 0.0, -47.0])
    ..pickup('rockets', <num>[-6.0, 0.8, -46.0], amount: 4)
    ..pickup('rockets', <num>[6.0, 0.8, -46.0], amount: 4)
    ..pickup('health', <num>[-14.0, 0.8, -56.0], amount: 25)
    ..pickup('health', <num>[14.0, 0.8, -56.0], amount: 25)
    ..pickup('armour', <num>[0.0, 0.8, -50.0], amount: 25)
    ..pickup('shells', <num>[-14.0, 0.8, -62.0], amount: 8)
    ..pickup('bullets', <num>[14.0, 0.8, -62.0], amount: 20)
    ..pickup('invulnerability', <num>[0.0, 0.8, -46.0], amount: 20)
    ..pickup('berserk', <num>[0.0, 0.8, -58.0], amount: 30)
    ..exitAt('the_light', <num>[0.0, 0.9, -66.0]);
  return <String, String>{
    '$_levels/sanctum.json': k.write(
      file: 'sanctum.json',
      name: 'The Sanctum',
      tool: tool,
    ),
  };
}
