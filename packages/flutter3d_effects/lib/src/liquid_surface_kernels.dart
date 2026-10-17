/// A shallow water's surface built where the water is stepped: the kernels
/// `LiquidView` adds to the water's workload, so the surface is drawn from
/// a buffer the GPU wrote and nothing is read back to build it.
///
/// **The CPU's drawing, pass for pass** (`LiquidView._drawHeights` and
/// `_writeSurface`): `SurfaceHeights` decides each vertex's height — a wet
/// cell at its own surface, a dry one beside water level with the wet cells
/// round it, a perched or falling one as the lower water's bank, one with
/// no water near sunk under its ground — into `look` (three reals a cell:
/// the height, what it is, how far into the bank the water reaches); then
/// `SurfaceVertices` writes the vertex itself into `vertices` as
/// `writeVertex` lays one out: position, normal from the drawn slope, the
/// depth or edge in its first texture coordinate, the flow in its colour's
/// red and green, the froth in its blue.
///
/// They read the water's own buffers (`state`, `cells`, `params`), and
/// `view` (the origin x, y, z and the cell) and `air` (the bubbles' air
/// spread over each column, m³, which the view works out on the CPU from
/// the clouds the core has).
library;

/// What a cell's vertex is in `look`: under its ground and not drawn, the
/// water of its own cell, or the bank of water beside it.
const int surfaceSunk = 0, surfaceStanding = 1, surfaceBank = 2;

/// The surface kernels, one `compute` block each, after the water's.
const String liquidSurfaceKernels = '''
// Where each vertex is drawn: a wet cell at its own surface, a dry one
// beside water level with the wet cells round it, a perched or falling one
// as the lower water's bank, a dry one with no water near sunk.
compute SurfaceHeights {
  workgroup 64;
  buffer state: f32[] read;
  buffer cells: f32[] read;
  buffer look: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let nx = i32(params[0]);
    let nz = i32(params[1]);
    let cell = params[2];
    let n = nx * nz;
    let c = i32(id.x);
    if c >= n { return; }
    let i = c % nx;
    let j = c / nx;
    let area = cell * cell;
    let fall = 0.4 * cell;
    let perch = 0.15 * cell;
    let x0 = max(i - 1, 0);
    let x1 = min(i + 1, nx - 1);
    let z0 = max(j - 1, 0);
    let z1 = min(j + 1, nz - 1);
    let wetHere = state[c] > 0.004;
    let groundHere = cells[c];
    var lowest = 1.0e30;
    var perched = false;
    for z in z0 .. z1 + 1 {
      for x in x0 .. x1 + 1 {
        let m = x + z * nx;
        if !(state[m] > 0.004) { continue; }
        let s = cells[m] + state[m] + cells[n + m] / area;
        lowest = min(lowest, s);
        if wetHere && groundHere - s > perch { perched = true; }
      }
    }
    let surfaceHere = groundHere + state[c] + cells[n + c] / area;
    if wetHere && !perched && surfaceHere <= lowest + fall {
      look[3 * c] = surfaceHere;
      look[3 * c + 1] = 1.0;
      look[3 * c + 2] = 0.0;
      return;
    }
    var top = lowest + fall;
    if perched { top = groundHere - perch; }
    var sum = 0.0;
    var deep = 0.0;
    var wet = 0.0;
    for z in z0 .. z1 + 1 {
      for x in x0 .. x1 + 1 {
        let m = x + z * nx;
        if !(state[m] > 0.004) { continue; }
        let s = cells[m] + state[m] + cells[n + m] / area;
        if s > top { continue; }
        sum += s;
        deep += state[m];
        wet += 1.0;
      }
    }
    if wet == 0.0 {
      look[3 * c] = 0.0;
      look[3 * c + 1] = 0.0;
      look[3 * c + 2] = 0.0;
      return;
    }
    look[3 * c] = sum / wet;
    look[3 * c + 1] = 2.0;
    look[3 * c + 2] = max(deep / wet, 0.02) * (1.5 - wet / 8.0);
  }
}

// Each vertex as `writeVertex` lays it out: position, normal, depth or
// edge, tangent, flow and froth.
compute SurfaceVertices {
  workgroup 64;
  buffer state: f32[] read;
  buffer cells: f32[] read;
  buffer look: f32[] read;
  buffer air: f32[] read;
  buffer view: f32[] read;
  buffer vertices: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let nx = i32(params[0]);
    let nz = i32(params[1]);
    let cell = params[2];
    let n = nx * nz;
    let c = i32(id.x);
    if c >= n { return; }
    let i = c % nx;
    let j = c / nx;
    let ux = nx + 1;
    let fall = 0.4 * cell;
    let kind = look[3 * c + 1];
    let sunk = kind == 0.0;
    let here = look[3 * c];
    // The drawn height of a neighbour, level with this one where it is
    // sunk, off the grid or across a fall.
    var east = here;
    if i + 1 < nx && look[3 * (c + 1) + 1] != 0.0 && abs(look[3 * (c + 1)] - here) <= fall { east = look[3 * (c + 1)]; }
    var west = here;
    if i > 0 && look[3 * (c - 1) + 1] != 0.0 && abs(look[3 * (c - 1)] - here) <= fall { west = look[3 * (c - 1)]; }
    var north = here;
    if j + 1 < nz && look[3 * (c + nx) + 1] != 0.0 && abs(look[3 * (c + nx)] - here) <= fall { north = look[3 * (c + nx)]; }
    var south = here;
    if j > 0 && look[3 * (c - nx) + 1] != 0.0 && abs(look[3 * (c - nx)] - here) <= fall { south = look[3 * (c - nx)]; }
    var gx = 0.0;
    var gz = 0.0;
    if !sunk {
      gx = -(east - west) / (2.0 * cell);
      gz = -(north - south) / (2.0 * cell);
    }
    let unit = 1.0 / sqrt(gx * gx + 1.0 + gz * gz);
    let depth = state[c];
    let ground = cells[c];
    var edge = 0.0;
    if kind == 1.0 {
      edge = depth;
    } else if kind == 2.0 {
      let over = here - ground;
      edge = select(over > 0.0, -look[3 * c + 2], over);
    }
    var froth = 0.0;
    if depth > 0.004 {
      froth = clamp(air[c] / (max(depth, 0.05) * cell * cell) / 0.03, 0.0, 1.0);
    }
    let flowX = 0.5 * (state[n + i + j * ux] + state[n + i + 1 + j * ux]);
    let wbase = n + ux * nz;
    let flowZ = 0.5 * (state[wbase + i + j * nx] + state[wbase + i + (j + 1) * nx]);
    let k = 16 * c;
    vertices[k] = view[0] + (f32(i) + 0.5) * cell;
    vertices[k + 1] = view[1] + select(sunk, ground - 0.2 * cell, here);
    vertices[k + 2] = view[2] + (f32(j) + 0.5) * cell;
    vertices[k + 3] = gx * unit;
    vertices[k + 4] = unit;
    vertices[k + 5] = gz * unit;
    vertices[k + 6] = edge;
    vertices[k + 7] = 0.0;
    vertices[k + 8] = 1.0;
    vertices[k + 9] = 0.0;
    vertices[k + 10] = 0.0;
    vertices[k + 11] = 1.0;
    vertices[k + 12] = 0.5 + flowX / 8.0;
    vertices[k + 13] = 0.5 + flowZ / 8.0;
    vertices[k + 14] = froth;
    vertices[k + 15] = 1.0;
  }
}
''';
