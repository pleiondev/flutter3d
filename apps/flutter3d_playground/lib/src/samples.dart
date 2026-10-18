/// The documents the playground opens on, one of each kind it reads.
library;

/// A level: a floor, a wall, a ramp and a block in two materials, one lamp,
/// three entities and a prefab placed twice, the second time with an
/// override.
const String sampleLevel = r'''{
  "format": "f3d.level",
  "version": 5,
  "name": "courtyard",
  "materials": {
    "stone": { "baseColor": [0.55, 0.52, 0.48, 1.0], "roughness": 0.85 },
    "brick": { "baseColor": [0.62, 0.3, 0.22, 1.0], "roughness": 0.7 }
  },
  "brushes": [
    { "at": [0.0, -0.25, 0.0], "size": [12.0, 0.5, 12.0], "material": "stone" },
    { "at": [0.0, 1.5, -5.75], "size": [12.0, 3.0, 0.5], "material": "brick" },
    { "at": [-3.0, 0.5, -2.0], "size": [2.0, 1.0, 2.0], "material": "brick" },
    { "at": [3.0, 0.25, 1.0], "size": [3.0, 0.5, 2.0], "material": "stone" }
  ],
  "lights": [
    { "type": "point", "at": [0.0, 3.5, 0.0], "color": [1.0, 0.9, 0.75],
      "intensity": 60000.0, "range": 18.0 }
  ],
  "prefabs": {
    "lamp_post": {
      "entities": [
        { "id": "post0001", "type": "post", "at": [0.0, 0.0, 0.0] },
        { "id": "lamp0001", "type": "lamp", "at": [0.0, 1.8, 0.0] }
      ]
    }
  },
  "entities": [
    { "type": "player_spawn", "at": [0.0, 0.0, 4.0] },
    { "type": "pickup", "at": [3.0, 0.5, 1.0] },
    { "type": "exit", "at": [0.0, 0.0, -5.0] },
    { "type": "prefab", "at": [-5.0, 0.0, 3.0],
      "props": { "prefab": "lamp_post" } },
    { "type": "prefab", "at": [5.0, 0.0, 3.0],
      "props": { "prefab": "lamp_post",
                 "overrides": { "lamp0001": { "at": [0.0, 2.6, 0.0] } } } }
  ]
}
''';

/// A prefab on its own: its entities, drawn as one instance at the origin.
const String samplePrefab = r'''{
  "entities": [
    { "id": "base0001", "type": "post", "at": [0.0, 0.0, 0.0] },
    { "id": "arm00001", "type": "arm", "at": [0.6, 1.6, 0.0] },
    { "id": "arm00002", "type": "arm", "at": [-0.6, 1.6, 0.0] },
    { "id": "lamp0001", "type": "lamp", "at": [0.0, 2.2, 0.0] }
  ]
}
''';
