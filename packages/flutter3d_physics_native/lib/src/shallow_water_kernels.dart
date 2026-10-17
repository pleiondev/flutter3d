/// The core's shallow water substep (`csrc/src/f3d_shallow.c`, `substep`)
/// as kernels in the kernel language, for a water stepped on a GPU.
///
/// **The same scheme, pass for pass.** A substep there is four loops over
/// the grid, each written as one invocation per face or per cell here,
/// gathering where the C scatters, so every element is written by one
/// invocation and nothing needs an atomic:
///
///  1. the springs and outlets — left on the core, once a step
///     (`wells`), as is what bodies do to the water and what it does to
///     them;
///  2. the velocities carried along themselves: `ShallowAdvect`, every face
///     into `fa`;
///  2½. the eddies' viscosity in each cell, `ShallowEddies` into `eddies`, and
///     each face's velocity spread by it, `ShallowDiffuse` into `fb`;
///  3. the slope, the bed, the wind and the edges, `ShallowSlope`, from `fb`
///     and `fa` back into the state;
///  4. each column's share of what it can give, `ShallowOutflow`; each face
///     scaled by it and what it moves, `ShallowTransport` (into `flux`, with
///     what came in over an edge into `came` and what went over a lip into
///     `lip`); and each column's new depth, `ShallowSettle`.
///
/// **What differs from the C, and why it is within the tolerance**
/// (`doc/gpu_water.md`): a quotient, a square root and `pow` for the cube
/// root are a GPU's to a few ulp, where the core's cube root is its own
/// Newton iteration; a column's inflows are summed in face order round it
/// rather than in the grid's; an open edge reads the face inside it as it
/// stood before the slope, where the C reads it before or after by which
/// end of the loop it is at; the wind is the one at the water's origin; and
/// what crosses an edge is not counted in the volume's `lost`.
///
/// **Its buffers**, f32 each, named as the workload declares them: `params`
/// (`F3D_SHALLOW_EXTERNAL_PARAMS`), `state` — the depths, then the x faces'
/// velocities, then the z faces', as the core lays them out — `cells` —
/// ground, what bodies fill, roughness and walls, a cell each, one after
/// another — `fa`, `fb`, `flux` and `came` over the faces, `eddies` and
/// `share` over the cells, `lip` four reals a face, and `changes` as long
/// as `state`.
library;

/// How dry a column is still water, m: `F3D_SHALLOW_DRY`.
const String _dry = '0.0001';

/// What every kernel opens with: the grid's sizes and where each part of
/// the state starts.
const String _grid = '''
    let nx = i32(params[0]);
    let nz = i32(params[1]);
    let cell = params[2];
    let area = cell * cell;
    let n = nx * nz;
    let ux = nx + 1;
    let fu = ux * nz;
    let fw = nx * (nz + 1);
    let ub = n;
    let wb = n + fu;
    let gravity = params[3];
    let h = params[21];''';

/// The depth flux across x face ([i], [j]) into a new local [name]: its
/// velocity times the depth of the column it comes from.
String _qx(String name, String i, String j) =>
    '''
    var $name = 0.0;
    let ${name}v = state[ub + ($i) + ($j) * ux];
    if ${name}v > 0.0 {
      if ($i) > 0 { $name = ${name}v * state[($i) - 1 + ($j) * nx]; }
    } else {
      if ($i) < nx { $name = ${name}v * state[($i) + ($j) * nx]; }
    }''';

/// The same across z face ([i], [j]).
String _qz(String name, String i, String j) =>
    '''
    var $name = 0.0;
    let ${name}v = state[wb + ($i) + ($j) * nx];
    if ${name}v > 0.0 {
      if ($j) > 0 { $name = ${name}v * state[($i) + (($j) - 1) * nx]; }
    } else {
      if ($j) < nz { $name = ${name}v * state[($i) + ($j) * nx]; }
    }''';

/// The surface over cell [c]: ground, water, and what bodies fill of it.
String _surface(String c) => '(cells[$c] + state[$c] + cells[n + $c] / area)';

/// Manning's roughness of cell [c]: its own, or the water's.
String _rough(String c) =>
    'select(cells[2 * n + $c] < 0.0, params[6], cells[2 * n + $c])';

/// Whether cell [c] is a wall.
String _walled(String c) => '(cells[3 * n + $c] != 0.0)';

/// The depth crossing from [from] to [to] (−1 off the grid) into a new
/// local [name]: what stands above the higher bed, no more than there is.
String _crossing(String name, String from, String to) =>
    '''
    var $name = state[$from];
    if ($to) >= 0 {
      $name = clamp(${_surface(from)} - max(cells[$from], cells[$to]), 0.0, state[$from]);
    }''';

/// Whether the face from [a] to [b] is a free overfall.
String _brink(String a, String b) =>
    '(cells[$a] > cells[$b] && ${_surface(b)} < cells[$a])';

/// Edge [side]'s weight into a new local [name]: the conveyance h^(5/3)
/// of its wet cells, or minus how many cells it has that are not walls.
String _weight(String name, String side) =>
    '''
    var ${name}s = 0.0;
    var ${name}c = 0.0;
    let ${name}n = select(($side) < 2, nz, nx);
    for ${name}k in 0 .. ${name}n {
      var ${name}i = ${name}k;
      if ($side) == 0 { ${name}i = ${name}k * nx; }
      if ($side) == 1 { ${name}i = nx - 1 + ${name}k * nx; }
      if ($side) == 3 { ${name}i = ${name}k + (nz - 1) * nx; }
      if ${_walled('${name}i')} { continue; }
      ${name}c += 1.0;
      let ${name}h = state[${name}i];
      if ${name}h > $_dry {
        let ${name}r = pow(${name}h, 0.33333334);
        ${name}s += ${name}h * ${name}r * ${name}r;
      }
    }
    let $name = select(${name}s > 0.0, ${name}s, -${name}c);''';

/// The discharge through edge cell [c] of [side], m³/s, into a new local
/// [name], with the side's weight [weight].
String _share(String name, String side, String c, String weight) =>
    '''
    var $name = 0.0;
    let ${name}t = params[14 + ($side)];
    if !${_walled(c)} {
      if $weight < 0.0 {
        if ${name}t > 0.0 { $name = ${name}t / -$weight; }
      } else {
        let ${name}h = state[$c];
        if ${name}h > $_dry && $weight > 0.0 {
          let ${name}r = pow(${name}h, 0.33333334);
          $name = ${name}t * ${name}h * ${name}r * ${name}r / $weight;
        }
      }
    }''';

/// Which face invocation [id.x] is: its axis, its column and row, its
/// index among its axis's faces, and the edge cell and side when it is on
/// the edge (−1 for none).
const String _face = '''
    let gi = i32(id.x);
    if gi >= fu + fw { return; }
    let xf = gi < fu;
    let f = select(xf, gi, gi - fu);
    let i = select(xf, f % ux, f % nx);
    let j = select(xf, f / ux, f / nx);
    var side = -1;
    var ec = -1;
    if xf {
      if i == 0 { side = 0; ec = j * nx; }
      if i == nx { side = 1; ec = nx - 1 + j * nx; }
    } else {
      if j == 0 { side = 2; ec = i; }
      if j == nz { side = 3; ec = i + (nz - 1) * nx; }
    }
    let left = select(xf, select(i == 0, -1, i - 1 + j * nx), select(j == 0, -1, i + (j - 1) * nx));
    let right = select(xf, select(i == nx, -1, i + j * nx), select(j == nz, -1, i + j * nx));''';

/// Every kernel of the substep and its bookkeeping, one `compute` block
/// each, in the order a frame dispatches them.
final String shallowWaterKernels =
    '''
kernel 1

// The changes the core made, added: a depth never below none.
compute ShallowApply {
  workgroup 64;
  buffer state: f32[] read_write;
  buffer changes: f32[] read;
  buffer params: f32[] read;
  kernel {
    let at = id.x;
    if at >= len(state) { return; }
    let cellsCount = u32(params[0]) * u32(params[1]);
    var v = state[at] + changes[at];
    if at < cellsCount { v = max(v, 0.0); }
    state[at] = v;
  }
}

// What went over the lips, taken: nothing again.
compute ShallowClearLips {
  workgroup 64;
  buffer lip: f32[] read_write;
  kernel {
    let at = id.x;
    if at >= len(lip) { return; }
    lip[at] = 0.0;
  }
}

// 2. The velocities carried along themselves, conserving momentum.
compute ShallowAdvect {
  workgroup 64;
  buffer state: f32[] read;
  buffer fa: f32[] read_write;
  buffer params: f32[] read;
  kernel {
$_grid
    let gi = i32(id.x);
    if gi >= fu + fw { return; }
    let k = h / cell;
    if gi < fu {
      let i = gi % ux;
      let j = gi / ux;
      let f = gi;
      fa[gi] = state[ub + f];
      if i < 1 || i >= nx { return; }
      let depth = 0.5 * (state[i - 1 + j * nx] + state[i + j * nx]);
      if !(depth > $_dry) { return; }
      let uf = state[ub + f];
${_qx('qa', 'i - 1', 'j')}
${_qx('qb', 'i', 'j')}
${_qx('qc', 'i + 1', 'j')}
      let ql = 0.5 * (qa + qb);
      let qr = 0.5 * (qb + qc);
      let ul = select(ql > 0.0, state[ub + f - 1], uf);
      let ur = select(qr > 0.0, uf, state[ub + f + 1]);
      var a = qr * ur - ql * ul - uf * (qr - ql);
${_qz('za', 'i - 1', 'j + 1')}
${_qz('zb', 'i', 'j + 1')}
${_qz('zc', 'i - 1', 'j')}
${_qz('zd', 'i', 'j')}
      let qt = 0.5 * (za + zb);
      let qd = 0.5 * (zc + zd);
      var ut = uf;
      if !(qt > 0.0) && j + 1 < nz { ut = state[ub + f + ux]; }
      var ud = uf;
      if qd > 0.0 && j > 0 { ud = state[ub + f - ux]; }
      a += qt * ut - qd * ud - uf * (qt - qd);
      fa[gi] = uf - k * a / depth;
    } else {
      let f = gi - fu;
      let i = f % nx;
      let j = f / nx;
      fa[gi] = state[wb + f];
      if j < 1 || j >= nz { return; }
      let depth = 0.5 * (state[i + (j - 1) * nx] + state[i + j * nx]);
      if !(depth > $_dry) { return; }
      let wf = state[wb + f];
${_qz('za', 'i', 'j - 1')}
${_qz('zb', 'i', 'j')}
${_qz('zc', 'i', 'j + 1')}
      let qd = 0.5 * (za + zb);
      let qt = 0.5 * (zb + zc);
      let wd = select(qd > 0.0, state[wb + f - nx], wf);
      let wt = select(qt > 0.0, wf, state[wb + f + nx]);
      var a = qt * wt - qd * wd - wf * (qt - qd);
${_qx('qa', 'i + 1', 'j - 1')}
${_qx('qb', 'i + 1', 'j')}
${_qx('qc', 'i', 'j - 1')}
${_qx('qe', 'i', 'j')}
      let qr = 0.5 * (qa + qb);
      let ql = 0.5 * (qc + qe);
      var wr = wf;
      if !(qr > 0.0) && i + 1 < nx { wr = state[wb + f + 1]; }
      var wl = wf;
      if ql > 0.0 && i > 0 { wl = state[wb + f - 1]; }
      a += qr * wr - ql * wl - wf * (qr - ql);
      fa[gi] = wf - k * a / depth;
    }
  }
}

// 2½. The eddies' viscosity in each wet cell: Smagorinsky's, Fischer's and
// the fluid's own, held to what a substep allows.
compute ShallowEddies {
  workgroup 64;
  buffer state: f32[] read;
  buffer cells: f32[] read;
  buffer fa: f32[] read;
  buffer eddies: f32[] read_write;
  buffer params: f32[] read;
  kernel {
$_grid
    let c = i32(id.x);
    if c >= n { return; }
    eddies[c] = 0.0;
    if !(state[c] > $_dry) || ${_walled('c')} { return; }
    let i = c % nx;
    let j = c / nx;
    let mix = 0.15 * cell;
    let mostNu = 0.25 * cell * cell / h;
    let fluidNu = params[5] / params[4];
    let dux = (fa[i + 1 + j * ux] - fa[i + j * ux]) / cell;
    let dwz = (fa[fu + i + (j + 1) * nx] - fa[fu + i + j * nx]) / cell;
    var duz = 0.0;
    if j + 1 < nz && j > 0 {
      duz = (fa[i + (j + 1) * ux] - fa[i + (j - 1) * ux]) / (2.0 * cell);
    }
    var dwx = 0.0;
    if i + 1 < nx && i > 0 {
      dwx = (fa[fu + i + 1 + j * nx] - fa[fu + i - 1 + j * nx]) / (2.0 * cell);
    }
    let shear = sqrt(2.0 * (dux * dux + dwz * dwz) + (duz + dwx) * (duz + dwx));
    let d = state[c];
    let su = fa[i + j * ux] + fa[i + 1 + j * ux];
    let sw = fa[fu + i + j * nx] + fa[fu + i + (j + 1) * nx];
    let speed = sqrt(0.25 * su * su + 0.25 * sw * sw);
    let friction = ${_rough('c')} * speed * sqrt(gravity) / sqrt(pow(d, 0.33333334));
    let nu = mix * mix * shear + 0.15 * d * friction + fluidNu;
    eddies[c] = min(nu, mostNu);
  }
}

// 2½. Each face's velocity spread to its neighbours' by the eddies.
compute ShallowDiffuse {
  workgroup 64;
  buffer fa: f32[] read;
  buffer fb: f32[] read_write;
  buffer eddies: f32[] read;
  buffer params: f32[] read;
  kernel {
    let nx = i32(params[0]);
    let nz = i32(params[1]);
    let cell = params[2];
    let h = params[21];
    let ux = nx + 1;
    let fu = ux * nz;
    let fw = nx * (nz + 1);
    let gi = i32(id.x);
    if gi >= fu + fw { return; }
    let k = h / (cell * cell);
    let here = fa[gi];
    fb[gi] = here;
    if gi < fu {
      let i = gi % ux;
      let j = gi / ux;
      if i < 1 || i >= nx { return; }
      let nu = 0.5 * (eddies[i - 1 + j * nx] + eddies[i + j * nx]);
      if !(nu > 0.0) { return; }
      var down = here;
      if j > 0 { down = fa[gi - ux]; }
      var up = here;
      if j + 1 < nz { up = fa[gi + ux]; }
      let laplacian = fa[gi - 1] + fa[gi + 1] - 4.0 * here + down + up;
      fb[gi] = here + nu * k * laplacian;
    } else {
      let f = gi - fu;
      let i = f % nx;
      let j = f / nx;
      if j < 1 || j >= nz { return; }
      let nu = 0.5 * (eddies[i + (j - 1) * nx] + eddies[i + j * nx]);
      if !(nu > 0.0) { return; }
      var west = here;
      if i > 0 { west = fa[gi - 1]; }
      var east = here;
      if i + 1 < nx { east = fa[gi + 1]; }
      let laplacian = fa[gi - nx] + fa[gi + nx] - 4.0 * here + west + east;
      fb[gi] = here + nu * k * laplacian;
    }
  }
}

// 3. The slope, the bed and the wind, face by face; the edges as they
// are told.
compute ShallowSlope {
  workgroup 64;
  buffer state: f32[] read_write;
  buffer cells: f32[] read;
  buffer fa: f32[] read;
  buffer fb: f32[] read;
  buffer params: f32[] read;
  kernel {
$_grid
$_face
    let most = 0.5 * cell / h;
    let vb = select(xf, ub, wb);
    let v = fb[gi];
    if side >= 0 {
      let outwards = side == 1 || side == 3;
      let sign = select(outwards, 1.0, -1.0);
      var kind = i32(params[10 + side]);
      if ${_walled('ec')} { kind = 0; }
      var out = 0.0;
      if kind == 1 {
        var inner = 0.0;
        if xf && nx > 1 { inner = fb[select(i == 0, 1, nx - 1) + j * ux]; }
        if !xf && nz > 1 { inner = fb[fu + i + select(j == 0, 1, nz - 1) * nx]; }
        if state[ec] > $_dry {
          out = select(outwards, max(inner, 0.0), min(inner, 0.0));
        }
      } else if kind == 2 {
${_weight('wt', 'side')}
${_share('q', 'side', 'ec', 'wt')}
        let d = max(state[ec], $_dry);
        out = clamp(-sign * q / (d * cell), -most, most);
      } else if kind == 3 {
        let stage = params[14 + side] - params[18];
        let outside = max(stage - cells[ec], 0.0);
        let inside = ${_surface('ec')};
        let depth = 0.5 * (outside + state[ec]);
        var vel = sign * v;
        vel -= gravity * h * (max(stage, cells[ec]) - inside) / cell;
        if vel > 0.0 && !(state[ec] > $_dry) { vel = 0.0; }
        if vel < 0.0 && !(outside > $_dry) { vel = 0.0; }
        if depth > $_dry {
          let rn = ${_rough('ec')};
          let turbulent = gravity * rn * rn * abs(vel) / (depth * pow(depth, 0.33333334));
          let laminar = 3.0 * params[5] / (params[4] * depth * depth);
          vel /= 1.0 + h * max(turbulent, laminar);
        }
        out = sign * clamp(vel, -most, most);
      }
      state[vb + f] = out;
      return;
    }
    let a = left;
    let b = right;
    let da = state[a];
    let db = state[b];
    if ${_walled('a')} || ${_walled('b')} || (!(da > $_dry) && !(db > $_dry)) {
      state[vb + f] = 0.0;
      return;
    }
    let forward = ${_brink('a', 'b')};
    let backward = ${_brink('b', 'a')};
    if forward || backward {
      let from = select(forward, a, b);
      let to = select(forward, b, a);
${_crossing('over', 'from', 'to')}
      var vel = 0.0;
      if over > $_dry {
        let stride = select(xf, 1, nx);
        var hasBehind = false;
        if forward { hasBehind = select(xf, i > 1, j > 1); }
        if !forward { hasBehind = select(xf, i + 1 < nx, j + 1 < nz); }
        var behind = 0.0;
        if hasBehind { behind = select(forward, fa[gi - stride], -fa[gi + stride]); }
        vel = max(sqrt(gravity * over), behind);
      }
      vel = min(vel, most);
      state[vb + f] = select(forward, vel, -vel);
      return;
    }
    let ea = ${_surface('a')};
    let eb = ${_surface('b')};
    var vel = v - gravity * h * (eb - ea) / cell;
${_crossing('ab', 'a', 'b')}
${_crossing('ba', 'b', 'a')}
    if vel > 0.0 && !(ab > $_dry) { vel = 0.0; }
    if vel < 0.0 && !(ba > $_dry) { vel = 0.0; }
    let depth = 0.5 * (da + db);
    if depth > $_dry {
      let along = select(xf, params[8], params[9]);
      let across = select(xf, params[9], params[8]);
      let speed = sqrt(along * along + across * across);
      vel += h * params[7] * 0.0013 * speed * along / (params[4] * depth);
      let na = ${_rough('a')};
      let nb = ${_rough('b')};
      let n2 = 0.5 * (na * na + nb * nb);
      let h43 = depth * pow(depth, 0.33333334);
      let turbulent = gravity * n2 * abs(vel) / h43;
      let laminar = 3.0 * params[5] / (params[4] * depth * depth);
      vel /= 1.0 + h * max(turbulent, laminar);
    }
    state[vb + f] = clamp(vel, -most, most);
  }
}

// 4. Each column's share of what its faces would take out of it: all of
// it, or as much as it holds.
compute ShallowOutflow {
  workgroup 64;
  buffer state: f32[] read;
  buffer cells: f32[] read;
  buffer share: f32[] read_write;
  buffer params: f32[] read;
  kernel {
$_grid
    let c = i32(id.x);
    if c >= n { return; }
    let i = c % nx;
    let j = c / nx;
    var out = 0.0;
    let vl = state[ub + i + j * ux];
    if vl < 0.0 {
${_crossing('cl', 'c', 'select(i > 0, c - 1, -1)')}
      out += abs(vl) * cl * cell * h;
    }
    let vr = state[ub + i + 1 + j * ux];
    if vr > 0.0 {
${_crossing('cr', 'c', 'select(i + 1 < nx, c + 1, -1)')}
      out += abs(vr) * cr * cell * h;
    }
    let vd = state[wb + i + j * nx];
    if vd < 0.0 {
${_crossing('cd', 'c', 'select(j > 0, c - nx, -1)')}
      out += abs(vd) * cd * cell * h;
    }
    let vu = state[wb + i + (j + 1) * nx];
    if vu > 0.0 {
${_crossing('cu', 'c', 'select(j + 1 < nz, c + nx, -1)')}
      out += abs(vu) * cu * cell * h;
    }
    let has = state[c] * area;
    share[c] = select(out > has && out > 0.0, has / out, 1.0);
  }
}

// 4. Each face scaled by its column's share, and what it moves: into a
// column, off the grid, over a lip, or in from outside an edge.
compute ShallowTransport {
  workgroup 64;
  buffer state: f32[] read_write;
  buffer cells: f32[] read;
  buffer share: f32[] read;
  buffer flux: f32[] read_write;
  buffer came: f32[] read_write;
  buffer lip: f32[] read_write;
  buffer params: f32[] read;
  kernel {
$_grid
$_face
    flux[gi] = 0.0;
    came[gi] = 0.0;
    let vb = select(xf, ub, wb);
    var v = state[vb + f];
    if side >= 0 {
      let outwards = side == 1 || side == 3;
      let inwards = select(outwards, v < 0.0, v > 0.0);
      var kind = i32(params[10 + side]);
      if ${_walled('ec')} { kind = 0; }
      var into = 0.0;
      if kind == 2 && params[14 + side] > 0.0 {
${_weight('wt', 'side')}
${_share('q', 'side', 'ec', 'wt')}
        into = q * h;
      } else if kind == 3 && inwards {
        let outside = max(params[14 + side] - params[18] - cells[ec], 0.0);
        into = abs(v) * outside * cell * h;
      }
      if into > 0.0 {
        came[gi] = into;
        return;
      }
      if inwards || v == 0.0 { return; }
    }
    if v == 0.0 { return; }
    let forward = v > 0.0;
    let from = select(forward, left, right);
    let to = select(forward, right, left);
    if from < 0 { return; }
    v = v * share[from];
    state[vb + f] = v;
${_crossing('thick', 'from', 'to')}
    let moved = abs(v) * thick * cell * h;
    if !(moved > 0.0) { return; }
    flux[gi] = select(forward, moved, -moved);
    if to < 0 { return; }
    if ${_brink('from', 'to')} {
      let speed = abs(v);
      let fall = cells[from] + 0.5 * thick - ${_surface('to')};
      let reach = 0.5 * cell;
      if gravity * reach * reach < 2.0 * speed * speed * fall {
        let l = 4 * gi;
        lip[l] = lip[l] + moved;
        lip[l + 1] = lip[l + 1] + select(xf, v, 0.0) * moved;
        lip[l + 2] = lip[l + 2] + select(xf, 0.0, v) * moved;
        lip[l + 3] = f32(from);
        came[gi] = -1.0;
      }
    }
  }
}

// 4. Each column's depth after: what its faces brought in and took out,
// round it in order, never below none.
compute ShallowSettle {
  workgroup 64;
  buffer state: f32[] read_write;
  buffer flux: f32[] read;
  buffer came: f32[] read;
  buffer params: f32[] read;
  kernel {
$_grid
    let c = i32(id.x);
    if c >= n { return; }
    let i = c % nx;
    let j = c / nx;
    var next = state[c];
    let fl = i + j * ux;
    let fr = i + 1 + j * ux;
    let fd = fu + i + j * nx;
    let ft = fu + i + (j + 1) * nx;
    if came[fl] > 0.0 && i == 0 { next += came[fl] / area; }
    if flux[fl] > 0.0 && came[fl] != -1.0 { next += flux[fl] / area; }
    if flux[fl] < 0.0 { next -= -flux[fl] / area; }
    if came[fr] > 0.0 && i + 1 == nx { next += came[fr] / area; }
    if flux[fr] > 0.0 { next -= flux[fr] / area; }
    if flux[fr] < 0.0 && came[fr] != -1.0 { next += -flux[fr] / area; }
    if came[fd] > 0.0 && j == 0 { next += came[fd] / area; }
    if flux[fd] > 0.0 && came[fd] != -1.0 { next += flux[fd] / area; }
    if flux[fd] < 0.0 { next -= -flux[fd] / area; }
    if came[ft] > 0.0 && j + 1 == nz { next += came[ft] / area; }
    if flux[ft] > 0.0 { next -= flux[ft] / area; }
    if flux[ft] < 0.0 && came[ft] != -1.0 { next += -flux[ft] / area; }
    state[c] = max(next, 0.0);
  }
}
''';
