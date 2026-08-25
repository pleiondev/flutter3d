// Turns a downloaded model into one the game can load.
//
// Source models arrive in whatever the artist exported: an OBJ in centimetres
// with a million triangles and no tangents is normal. The game wants a small
// GLB in metres, centred on its own base, with a tangent basis — because the
// renderer's normal mapping reads TANGENT and a glTF without one produces a
// degenerate basis and a surface lit by noise.
//
// Kept in the repository rather than run once by hand so the path from the
// download to the asset is checkable, and so the next model takes a command
// rather than an afternoon.
//
// Usage:
//   node tool/prepare_model.mjs --in Key.OBJ --out assets/models/key.glb \
//        --triangles 2500 --height 0.3
//
// Requires network on first run: npx fetches gltf-transform and mikktspace.

import { NodeIO } from '@gltf-transform/core';
import { dedup, prune, weld, unweld, simplify, tangents }
  from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import { generateTangents } from 'mikktspace';
import { execFileSync } from 'node:child_process';
import { mkdirSync, existsSync } from 'node:fs';
import { dirname, extname } from 'node:path';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}

const input = arg('in');
const output = arg('out');
const targetTriangles = Number(arg('triangles', '3000'));
const targetHeight = Number(arg('height', '0'));

if (!input || !output) {
  console.error('need --in and --out');
  process.exit(1);
}

// obj2gltf first when the source is an OBJ: gltf-transform reads glTF only.
let glb = input;
if (extname(input).toLowerCase() === '.obj') {
  glb = join(tmpdir(), 'prepare_model_input.glb');
  execFileSync('npx', ['--yes', 'obj2gltf@3', '-i', input, '-o', glb,
                       '--binary'], { stdio: 'inherit' });
}

const io = new NodeIO();
const document = await io.read(glb);

const count = (doc) => doc.getRoot().listMeshes()
  .flatMap((m) => m.listPrimitives())
  .reduce((n, p) => n + (p.getIndices()?.getCount() ?? 0) / 3, 0);

await MeshoptSimplifier.ready;
await document.transform(
  dedup(),
  // Welding first, because a simplifier cannot collapse an edge whose two
  // sides are separate vertices — and an OBJ exported per face is entirely
  // separate vertices.
  weld(),
);

const before = count(document);
await document.transform(simplify({
  simplifier: MeshoptSimplifier,
  ratio: Math.min(1, targetTriangles / Math.max(before, 1)),
  error: 0.02,
}));

// Report what the simplifier achieved rather than what was asked for: it stops
// at the error bound, and a shape that is hard edges all the way down will not
// reach an aggressive target however politely it is asked.
console.log(`${before} -> ${count(document)} triangles ` +
            `(asked for ${targetTriangles})`);

// After simplification, so the basis matches the geometry that ships.
//
// Unwelded first and welded again after: MikkTSpace is defined on triangles
// with their own vertices, and refuses a welded primitive outright. Welding
// afterwards merges only vertices whose tangents agree, so the seams it has to
// keep, it keeps.
await document.transform(
  unweld(),
  tangents({ generateTangents, overwrite: true }),
  weld(),
);

// Scale and centre. A pickup authored 256 units tall has to become something
// a player can walk over, and it has to sit on its own origin or every level
// that places it needs a magic offset.
if (targetHeight > 0) {
  const scene = document.getRoot().getDefaultScene()
    ?? document.getRoot().listScenes()[0];
  let min = [Infinity, Infinity, Infinity];
  let max = [-Infinity, -Infinity, -Infinity];
  for (const mesh of document.getRoot().listMeshes()) {
    for (const primitive of mesh.listPrimitives()) {
      const position = primitive.getAttribute('POSITION');
      for (let i = 0; i < position.getCount(); i++) {
        const v = position.getElement(i, [0, 0, 0]);
        for (let k = 0; k < 3; k++) {
          min[k] = Math.min(min[k], v[k]);
          max[k] = Math.max(max[k], v[k]);
        }
      }
    }
  }
  const span = Math.max(max[1] - min[1], 1e-9);
  const scale = targetHeight / span;
  // Centred in x and z, resting on y = 0: what a level author means by "put it
  // here" is the point the thing stands on.
  const offset = [
    -(min[0] + max[0]) / 2,
    -min[1],
    -(min[2] + max[2]) / 2,
  ];
  for (const mesh of document.getRoot().listMeshes()) {
    for (const primitive of mesh.listPrimitives()) {
      const position = primitive.getAttribute('POSITION');
      const array = position.getArray().slice();
      for (let i = 0; i < position.getCount(); i++) {
        for (let k = 0; k < 3; k++) {
          array[i * 3 + k] = (array[i * 3 + k] + offset[k]) * scale;
        }
      }
      position.setArray(array);
    }
  }
  console.log(`scaled by ${scale.toFixed(5)} to ${targetHeight} m tall`);
}

// No quantization. It would halve the file, and the loader reads float
// accessors — a quantized mesh would arrive as a heap of very small integers.
//
// keepAttributes, because the source models have no textured material and
// prune's idea of an unused attribute is one no material samples. Without it
// the UVs and the tangents this script just generated are thrown away, and the
// only symptom is a model lit as though the normal map were blank.
await document.transform(prune({ keepAttributes: true }));

mkdirSync(dirname(output), { recursive: true });
await io.write(output, document);
console.log(`wrote ${output}`);
