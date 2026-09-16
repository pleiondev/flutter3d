/// Models that are code — `gal-02`.
///
/// **A recipe is a function, not a file.** Every model here is built from
/// the shapes and operations this package already has: a lathe for anything
/// turned, a cuboid for anything sawn, and a join for anything made of more
/// than one piece. That buys three things a downloaded `.glb` does not.
/// Nothing is stored, so the repository does not grow by a megabyte per
/// lamp. Nothing is licensed by somebody else, so a model inserted from
/// here carries no attribution into an export. And every dimension is a
/// number a person can change — a shelf is not 800 millimetres wide
/// because a modeller drew it that way, it is [Shelf.width].
///
/// **Real measurements, because a scene has to hold together.** A dining
/// chair's seat is 450 mm from the floor and a table's top is 740; a mug is
/// 95 mm across. Those are the numbers the objects actually have in the
/// world, and a set of props that each look right alone and wrong beside
/// each other is a set nobody can build a room from.
///
/// **Metres, like everything else in this repository.** The comments say
/// millimetres because that is how furniture is quoted; the code says
/// 0.45 because that is what the document holds.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'parametric.dart';

/// What a recipe belongs to, for a gallery to group by.
enum RecipeCategory {
  lighting('Lighting'),
  furniture('Furniture'),
  tableware('Tableware'),
  architecture('Architecture');

  const RecipeCategory(this.label);

  /// What a gallery's own section heading says.
  final String label;
}

/// One model that can be built rather than downloaded.
final class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.about,
    required this.build,
  });

  /// Stable, lowercase, and what an agent names when it asks for one.
  final String id;

  /// What the gallery card calls it.
  final String name;

  final RecipeCategory category;

  /// One sentence: what it is and what it is for. The same shape `ux-18`
  /// gives every tool, and for the same reason — a name is not a
  /// description.
  final String about;

  /// Builds it. Deterministic: the same call gives the same mesh, vertex
  /// for vertex, which is what lets a golden frame hold one.
  final EditMesh Function() build;
}

/// Every recipe this build ships, in the order a gallery lists them.
List<Recipe> recipes() => <Recipe>[
  Recipe(
    id: 'floor-lamp',
    name: 'Floor lamp',
    category: RecipeCategory.lighting,
    about: 'A turned column on a disc base, under a tapered shade.',
    build: floorLamp,
  ),
  Recipe(
    id: 'pendant-lamp',
    name: 'Pendant lamp',
    category: RecipeCategory.lighting,
    about: 'A dome on a flex, for hanging over a table.',
    build: pendantLamp,
  ),
  Recipe(
    id: 'table-lamp',
    name: 'Table lamp',
    category: RecipeCategory.lighting,
    about: 'A bulbous base and a drum shade, at bedside height.',
    build: tableLamp,
  ),
  Recipe(
    id: 'wall-sconce',
    name: 'Wall sconce',
    category: RecipeCategory.lighting,
    about: 'A backplate, an arm and a half-shade that throws light up.',
    build: wallSconce,
  ),
  Recipe(
    id: 'dining-chair',
    name: 'Dining chair',
    category: RecipeCategory.furniture,
    about: 'Four legs, a seat at 450 and a back a person can lean on.',
    build: diningChair,
  ),
  Recipe(
    id: 'stool',
    name: 'Stool',
    category: RecipeCategory.furniture,
    about: 'Three turned legs and a round top, at counter height.',
    build: stool,
  ),
  Recipe(
    id: 'dining-table',
    name: 'Dining table',
    category: RecipeCategory.furniture,
    about: 'A 1600 by 900 top at 740, on four square legs.',
    build: diningTable,
  ),
  Recipe(
    id: 'bench',
    name: 'Bench',
    category: RecipeCategory.furniture,
    about: 'A plank seat on two slab ends — a hallway or a garden.',
    build: bench,
  ),
  Recipe(
    id: 'shelf',
    name: 'Shelf unit',
    category: RecipeCategory.furniture,
    about: 'Two uprights and four shelves, open at the back.',
    build: shelfUnit,
  ),
  Recipe(
    id: 'cabinet',
    name: 'Cabinet',
    category: RecipeCategory.furniture,
    about: 'A closed box on a plinth, with two doors and handles.',
    build: cabinet,
  ),
  Recipe(
    id: 'mug',
    name: 'Mug',
    category: RecipeCategory.tableware,
    about: 'A turned cup with a handle — 95 across, 95 tall.',
    build: mug,
  ),
  Recipe(
    id: 'vase',
    name: 'Vase',
    category: RecipeCategory.tableware,
    about: 'A waisted profile turned about its own axis.',
    build: vase,
  ),
  Recipe(
    id: 'plate',
    name: 'Plate',
    category: RecipeCategory.tableware,
    about: 'A dinner plate with a rim and a footring.',
    build: plate,
  ),
  Recipe(
    id: 'bottle',
    name: 'Bottle',
    category: RecipeCategory.tableware,
    about: 'A shoulder, a neck and a lip — a wine bottle\'s own profile.',
    build: bottle,
  ),
  Recipe(
    id: 'door',
    name: 'Door',
    category: RecipeCategory.architecture,
    about: 'A 900 by 2040 leaf in its frame, with a lever handle.',
    build: door,
  ),
  Recipe(
    id: 'window',
    name: 'Window',
    category: RecipeCategory.architecture,
    about: 'A casement with a mullion and a sill.',
    build: window,
  ),
];

// ---------------------------------------------------------------- lighting

/// A turned column on a disc, under a tapered shade.
EditMesh floorLamp({
  double height = 1.55,
  double shadeTop = 0.16,
  double shadeBottom = 0.24,
}) => joinMeshes(<PlacedMesh>[
  // The base is wide and shallow, because a lamp this tall falls over
  // otherwise — and a model that would fall over reads as wrong even to
  // somebody who cannot say why.
  PlacedMesh(
    mesh: const ParametricCylinder(
      radiusTop: 0.15,
      radiusBottom: 0.16,
      height: 0.03,
    ).toEditMesh(),
    at: Vector3(0, 0.015, 0),
  ),
  PlacedMesh(
    mesh: const ParametricCylinder(
      radiusTop: 0.018,
      radiusBottom: 0.024,
      height: 1.2,
      segments: 16,
    ).toEditMesh(),
    at: Vector3(0, 0.63, 0),
  ),
  PlacedMesh(
    mesh: ParametricCylinder(
      radiusTop: shadeTop,
      radiusBottom: shadeBottom,
      height: 0.26,
      segments: 24,
      capped: false,
    ).toEditMesh(),
    at: Vector3(0, height - 0.13, 0),
  ),
]);

/// A dome on a flex, for hanging over a table.
EditMesh pendantLamp({double drop = 0.9, double width = 0.36}) =>
    joinMeshes(<PlacedMesh>[
      PlacedMesh(
        mesh: const ParametricCylinder(
          radiusTop: 0.004,
          radiusBottom: 0.004,
          height: 0.7,
          segments: 8,
        ).toEditMesh(),
        at: Vector3(0, drop + 0.35, 0),
      ),
      PlacedMesh(
        mesh: _dome(radius: width / 2, height: 0.2),
        at: Vector3(0, drop, 0),
      ),
    ]);

/// A bulbous base and a drum shade, at bedside height.
EditMesh tableLamp({double height = 0.44}) => joinMeshes(<PlacedMesh>[
  PlacedMesh(
    mesh: ParametricLathe(
      profile: <Vector2>[
        Vector2(0.001, 0),
        Vector2(0.07, 0),
        Vector2(0.085, 0.06),
        Vector2(0.06, 0.14),
        Vector2(0.03, 0.2),
        Vector2(0.018, 0.24),
        Vector2(0.001, 0.24),
      ],
      segments: 24,
    ).toEditMesh(),
    at: Vector3.zero(),
  ),
  PlacedMesh(
    mesh: const ParametricCylinder(
      radiusTop: 0.11,
      radiusBottom: 0.13,
      height: 0.17,
      segments: 24,
      capped: false,
    ).toEditMesh(),
    at: Vector3(0, height - 0.085, 0),
  ),
]);

/// A backplate, an arm and a half-shade that throws light up the wall.
EditMesh wallSconce() => joinMeshes(<PlacedMesh>[
  PlacedMesh(
    mesh: ParametricCuboid(size: Vector3(0.12, 0.2, 0.02)).toEditMesh(),
    at: Vector3(0, 0, 0.01),
  ),
  PlacedMesh(
    mesh: const ParametricCylinder(
      radiusTop: 0.012,
      radiusBottom: 0.012,
      height: 0.14,
      segments: 12,
    ).toEditMesh(),
    at: Vector3(0, 0, 0.09),
    turn: Vector3(math.pi / 2, 0, 0),
  ),
  PlacedMesh(
    mesh: const ParametricCylinder(
      radiusTop: 0.1,
      radiusBottom: 0.07,
      height: 0.12,
      segments: 20,
      capped: false,
    ).toEditMesh(),
    at: Vector3(0, 0.07, 0.16),
  ),
]);

// --------------------------------------------------------------- furniture

/// Four legs, a seat at 450 and a back a person can lean on.
EditMesh diningChair({
  double seat = 0.45,
  double width = 0.44,
  double depth = 0.44,
  double back = 0.85,
}) {
  const double leg = 0.035;
  final double x = width / 2 - leg / 2;
  final double z = depth / 2 - leg / 2;
  return joinMeshes(<PlacedMesh>[
    for (final (double sx, double sz) in <(double, double)>[
      (-x, -z),
      (x, -z),
      (-x, z),
      (x, z),
    ])
      PlacedMesh(
        mesh: ParametricCuboid(size: Vector3(leg, seat, leg)).toEditMesh(),
        at: Vector3(sx, seat / 2, sz),
      ),
    PlacedMesh(
      mesh: ParametricCuboid(size: Vector3(width, 0.04, depth)).toEditMesh(),
      at: Vector3(0, seat + 0.02, 0),
    ),
    // The back leans two degrees off vertical, which is the whole
    // difference between a chair and a box with sticks on it.
    PlacedMesh(
      mesh: ParametricCuboid(
        size: Vector3(width - 0.06, back - seat, 0.03),
      ).toEditMesh(),
      at: Vector3(0, (back + seat) / 2, z),
      turn: Vector3(-0.04, 0, 0),
    ),
  ]);
}

/// Three turned legs and a round top, at counter height.
EditMesh stool({double height = 0.65, double top = 0.32}) {
  final double radius = top / 2 - 0.05;
  return joinMeshes(<PlacedMesh>[
    for (var i = 0; i < 3; i++)
      PlacedMesh(
        mesh: const ParametricCylinder(
          radiusTop: 0.02,
          radiusBottom: 0.028,
          height: 0.62,
          segments: 12,
        ).toEditMesh(),
        at: Vector3(
          math.cos(i * 2 * math.pi / 3) * radius,
          // Lifted by the two millimetres a splayed leg's own rim dips
          // below its axis: a tilted cylinder stands on the edge of its
          // foot, not on the middle of it, and a stool sunk two
          // millimetres into the floor is a stool with no shadow gap.
          (height - 0.03) / 2 + 0.002,
          math.sin(i * 2 * math.pi / 3) * radius,
        ),
        turn: Vector3(
          math.sin(i * 2 * math.pi / 3) * 0.07,
          0,
          -math.cos(i * 2 * math.pi / 3) * 0.07,
        ),
      ),
    PlacedMesh(
      mesh: ParametricCylinder(
        radiusTop: top / 2,
        radiusBottom: top / 2,
        height: 0.03,
        segments: 28,
      ).toEditMesh(),
      at: Vector3(0, height - 0.015, 0),
    ),
  ]);
}

/// A 1600 by 900 top at 740, on four square legs.
EditMesh diningTable({
  double length = 1.6,
  double width = 0.9,
  double height = 0.74,
}) {
  const double leg = 0.07;
  final double x = length / 2 - leg;
  final double z = width / 2 - leg;
  return joinMeshes(<PlacedMesh>[
    for (final (double sx, double sz) in <(double, double)>[
      (-x, -z),
      (x, -z),
      (-x, z),
      (x, z),
    ])
      PlacedMesh(
        mesh: ParametricCuboid(
          size: Vector3(leg, height - 0.04, leg),
        ).toEditMesh(),
        at: Vector3(sx, (height - 0.04) / 2, sz),
      ),
    PlacedMesh(
      mesh: ParametricCuboid(size: Vector3(length, 0.04, width)).toEditMesh(),
      at: Vector3(0, height - 0.02, 0),
    ),
  ]);
}

/// A plank seat on two slab ends.
EditMesh bench({double length = 1.4, double height = 0.45}) =>
    joinMeshes(<PlacedMesh>[
      for (final double sx in <double>[-length / 2 + 0.1, length / 2 - 0.1])
        PlacedMesh(
          mesh: ParametricCuboid(
            size: Vector3(0.04, height - 0.05, 0.34),
          ).toEditMesh(),
          at: Vector3(sx, (height - 0.05) / 2, 0),
        ),
      PlacedMesh(
        mesh: ParametricCuboid(size: Vector3(length, 0.05, 0.36)).toEditMesh(),
        at: Vector3(0, height - 0.025, 0),
      ),
    ]);

/// Two uprights and four shelves, open at the back.
EditMesh shelfUnit({
  double width = 0.8,
  double height = 1.8,
  double depth = 0.32,
  int shelves = 4,
}) => joinMeshes(<PlacedMesh>[
  for (final double sx in <double>[-width / 2, width / 2])
    PlacedMesh(
      mesh: ParametricCuboid(size: Vector3(0.02, height, depth)).toEditMesh(),
      at: Vector3(sx, height / 2, 0),
    ),
  for (var i = 0; i < shelves; i++)
    PlacedMesh(
      mesh: ParametricCuboid(
        size: Vector3(width - 0.02, 0.02, depth),
      ).toEditMesh(),
      // Evenly spaced from the floor to the top, both ends included:
      // a unit whose top shelf is not the top reads as unfinished.
      at: Vector3(0, height * (i + 1) / (shelves + 1), 0),
    ),
]);

/// A closed box on a plinth, with two doors and handles.
EditMesh cabinet({
  double width = 0.9,
  double height = 0.85,
  double depth = 0.45,
}) => joinMeshes(<PlacedMesh>[
  PlacedMesh(
    mesh: ParametricCuboid(
      size: Vector3(width - 0.06, 0.08, depth - 0.06),
    ).toEditMesh(),
    at: Vector3(0, 0.04, 0),
  ),
  PlacedMesh(
    mesh: ParametricCuboid(
      size: Vector3(width, height - 0.08, depth),
    ).toEditMesh(),
    at: Vector3(0, 0.08 + (height - 0.08) / 2, 0),
  ),
  for (final double side in <double>[-1, 1]) ...<PlacedMesh>[
    PlacedMesh(
      mesh: ParametricCuboid(
        size: Vector3(width / 2 - 0.01, height - 0.14, 0.02),
      ).toEditMesh(),
      at: Vector3(side * width / 4, 0.08 + (height - 0.08) / 2, depth / 2),
    ),
    PlacedMesh(
      mesh: const ParametricCylinder(
        radiusTop: 0.008,
        radiusBottom: 0.008,
        height: 0.1,
        segments: 10,
      ).toEditMesh(),
      at: Vector3(side * 0.05, 0.08 + (height - 0.08) / 2, depth / 2 + 0.03),
    ),
  ],
]);

// --------------------------------------------------------------- tableware

/// A turned cup with a handle.
EditMesh mug({double height = 0.095, double radius = 0.0475}) =>
    joinMeshes(<PlacedMesh>[
      PlacedMesh(
        mesh: ParametricLathe(
          profile: <Vector2>[
            Vector2(0.001, 0),
            Vector2(radius, 0),
            Vector2(radius, height),
            Vector2(radius - 0.004, height),
            // Back down the inside: a mug modelled as a solid cylinder is
            // a mug nobody can see into, and the inside is most of what a
            // material preview shows.
            Vector2(radius - 0.004, 0.006),
            Vector2(0.001, 0.006),
          ],
          segments: 28,
        ).toEditMesh(),
        at: Vector3.zero(),
      ),
      PlacedMesh(
        mesh: const ParametricTorus(
          radius: 0.028,
          tubeRadius: 0.006,
          segments: 20,
          tubeSegments: 10,
        ).toEditMesh(),
        at: Vector3(radius + 0.018, height * 0.55, 0),
        turn: Vector3(math.pi / 2, 0, 0),
      ),
    ]);

/// A waisted profile turned about its own axis.
EditMesh vase({double height = 0.28}) => ParametricLathe(
  profile: <Vector2>[
    Vector2(0.001, 0),
    Vector2(0.05, 0),
    Vector2(0.075, 0.06),
    Vector2(0.09, 0.13),
    Vector2(0.06, 0.2),
    Vector2(0.045, 0.25),
    Vector2(0.055, 0.28),
    Vector2(0.05, 0.28),
    Vector2(0.04, 0.25),
    Vector2(0.055, 0.19),
    Vector2(0.08, 0.13),
    Vector2(0.065, 0.06),
    Vector2(0.042, 0.008),
    Vector2(0.001, 0.008),
  ],
  segments: 32,
).toEditMesh();

/// A dinner plate with a rim and a footring.
EditMesh plate({double radius = 0.135}) => ParametricLathe(
  profile: <Vector2>[
    Vector2(0.001, 0.004),
    Vector2(radius * 0.25, 0.004),
    Vector2(radius * 0.3, 0),
    Vector2(radius * 0.34, 0),
    Vector2(radius * 0.38, 0.004),
    Vector2(radius * 0.8, 0.012),
    Vector2(radius, 0.026),
    Vector2(radius, 0.03),
    Vector2(radius * 0.78, 0.018),
    Vector2(radius * 0.3, 0.01),
    Vector2(0.001, 0.01),
  ],
  segments: 36,
).toEditMesh();

/// A shoulder, a neck and a lip.
EditMesh bottle({double height = 0.3}) => ParametricLathe(
  profile: <Vector2>[
    Vector2(0.001, 0),
    Vector2(0.037, 0),
    Vector2(0.0375, 0.005),
    Vector2(0.0375, 0.17),
    Vector2(0.03, 0.21),
    Vector2(0.0145, 0.245),
    Vector2(0.0145, 0.29),
    Vector2(0.016, 0.295),
    Vector2(0.016, 0.3),
    Vector2(0.012, 0.3),
    Vector2(0.012, 0.25),
    Vector2(0.026, 0.21),
    Vector2(0.033, 0.17),
    Vector2(0.033, 0.006),
    Vector2(0.001, 0.006),
  ],
  segments: 28,
).toEditMesh();

// ------------------------------------------------------------ architecture

/// A 900 by 2040 leaf in its frame, with a lever handle.
EditMesh door({double width = 0.9, double height = 2.04}) =>
    joinMeshes(<PlacedMesh>[
      for (final double side in <double>[-1, 1])
        PlacedMesh(
          mesh: ParametricCuboid(
            size: Vector3(0.06, height + 0.06, 0.12),
          ).toEditMesh(),
          at: Vector3(side * (width / 2 + 0.03), (height + 0.06) / 2, 0),
        ),
      PlacedMesh(
        mesh: ParametricCuboid(
          size: Vector3(width + 0.12, 0.06, 0.12),
        ).toEditMesh(),
        at: Vector3(0, height + 0.03, 0),
      ),
      PlacedMesh(
        mesh: ParametricCuboid(size: Vector3(width, height, 0.04)).toEditMesh(),
        at: Vector3(0, height / 2, 0),
      ),
      PlacedMesh(
        mesh: const ParametricCylinder(
          radiusTop: 0.009,
          radiusBottom: 0.009,
          height: 0.11,
          segments: 10,
        ).toEditMesh(),
        // At 1050 from the floor, which is where a handle is.
        at: Vector3(width / 2 - 0.07, 1.05, 0.05),
        turn: Vector3(0, 0, math.pi / 2),
      ),
    ]);

/// A casement with a mullion and a sill.
EditMesh window({double width = 1.2, double height = 1.4}) =>
    joinMeshes(<PlacedMesh>[
      for (final double side in <double>[-1, 1])
        PlacedMesh(
          mesh: ParametricCuboid(size: Vector3(0.05, height, 0.1)).toEditMesh(),
          at: Vector3(side * (width / 2 - 0.025), height / 2, 0),
        ),
      for (final double y in <double>[0.025, height - 0.025])
        PlacedMesh(
          mesh: ParametricCuboid(size: Vector3(width, 0.05, 0.1)).toEditMesh(),
          at: Vector3(0, y, 0),
        ),
      PlacedMesh(
        mesh: ParametricCuboid(
          size: Vector3(0.04, height - 0.1, 0.1),
        ).toEditMesh(),
        at: Vector3(0, height / 2, 0),
      ),
      // The sill projects, because a sill that does not is a line rather
      // than a ledge.
      PlacedMesh(
        mesh: ParametricCuboid(
          size: Vector3(width + 0.08, 0.03, 0.16),
        ).toEditMesh(),
        at: Vector3(0, -0.015, 0.03),
      ),
    ]);

// --------------------------------------------------------------- machinery

/// One part of a recipe: a mesh, where it goes, and how it is turned.
///
/// **A class rather than a record**, for one reason: most parts are not
/// turned at all, and a record's fields are all required — every leg of
/// every chair would carry `turn: null` to say nothing.
final class PlacedMesh {
  PlacedMesh({required this.mesh, required this.at, this.turn});

  final EditMesh mesh;

  /// Where the part's own origin lands.
  final Vector3 at;

  /// Yaw, pitch and roll in radians, applied in that order, or null for a
  /// part that stands as it was built.
  final Vector3? turn;
}

/// Half a sphere, open at the bottom — a pendant shade.
EditMesh _dome({required double radius, required double height}) {
  const int steps = 10;
  return ParametricLathe(
    profile: <Vector2>[
      for (var i = 0; i <= steps; i++)
        Vector2(
          math.sin(i * math.pi / 2 / steps) * radius,
          height - math.cos(i * math.pi / 2 / steps) * height,
        ),
    ],
    segments: 24,
  ).toEditMesh();
}

/// [parts], moved and turned into one mesh.
///
/// **A join rather than a boolean.** The parts of a chair do not intersect
/// in a way anybody has to resolve — a leg meets a seat and that is the
/// whole of it — and a boolean would spend a BSP per part to discover the
/// same. What this does is the honest thing: read every part's vertices
/// through its own transform, and re-face them into one mesh.
EditMesh joinMeshes(List<PlacedMesh> parts) {
  final points = <Vector3>[];
  final faces = <List<int>>[];
  for (final PlacedMesh part in parts) {
    final Matrix4 place = Matrix4.translation(part.at);
    if (part.turn case final Vector3 turn) {
      place.multiply(Matrix4.rotationY(turn.y));
      place.multiply(Matrix4.rotationX(turn.x));
      place.multiply(Matrix4.rotationZ(turn.z));
    }
    // Live vertices only, and remapped: a mesh that has had a face deleted
    // has gaps in its slots, and copying the gaps would make orphans.
    final Map<int, int> renumbered = <int, int>{};
    final EditMesh mesh = part.mesh;
    for (var v = 0; v < mesh.vertexSlotCount; v++) {
      if (!mesh.isVertexAlive(v)) continue;
      renumbered[v] = points.length;
      points.add(place.transformed3(mesh.positionOf(v)));
    }
    for (var f = 0; f < mesh.faceSlotCount; f++) {
      if (!mesh.isFaceAlive(f)) continue;
      final loop = <int>[];
      mesh.forEachVertex(f, (int v) => loop.add(renumbered[v]!));
      if (loop.length >= 3) faces.add(loop);
    }
  }
  return EditMesh.fromFaces(points, faces);
}
