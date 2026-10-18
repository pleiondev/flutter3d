/// The visual systems' steps — particles, debris, cloth and the fluid tank
/// — as kernels in the kernel language, for a system stepped on a GPU.
///
/// **What the core's own steps do, pass for pass.** Each kernel is the
/// loop of `csrc/src/f3d_particles.c`, `f3d_debris.c`, `f3d_cloth.c` or
/// `f3d_fluid.c` written as one invocation per element: the same order of
/// passes, the same arithmetic in the same order where the language lets
/// it be. They are data here, beside the systems they step, because the
/// core draws nothing and opens no device: a package that may speak to the
/// hardware layer hands them to it as a `ComputeWorkload`
/// (`flutter3d_effects`), and the hardware layer says where they run.
///
/// **Where they differ from the core, and why that is within the
/// tolerance** (`doc/gpu_water.md`, *The visual systems*): a quotient and
/// a square root are a GPU's to its rounding; the debris' and the fluid's
/// neighbours are found through a grid built with `atomicExchange`, so a
/// cell's are summed in the order the invocations happened to insert them;
/// the cloth's colours are solved one dispatch each, in the core's order,
/// with nothing summed in an order the GPU picks.
///
/// **Their buffers**, by the names the kernels bind them under, each laid
/// out as the constants below say; a parameter that is a count is written
/// as a float and read back with `u32()`.
library;

/// Floats a particle slot takes: position xyz and the life left, then the
/// velocity xyz and a spare.
const int particleSlotFloats = 8;

/// Floats of the particles' parameters: gravity xyz, a spare, the wind xyz,
/// a spare, drag, the floor, restitution, friction, the step, and three
/// spares.
const int particleParamFloats = 16;

/// The particles' step: `ParticleStep` over `slots` with `params`, one
/// invocation a slot, run once per step.
const String particleKernels = '''
kernel 1

// f3d_particles_step: gravity, the drift towards the wind, the move, and
// the floor, for every living slot.
compute ParticleStep {
  workgroup 64;
  buffer slots: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(len(slots)) / 8 { return; }
    let o = i * 8;
    let life = slots[o + 3];
    if !(life > 0.0) { return; }
    let dt = params[12];
    var vx = slots[o + 4] + params[0] * dt;
    var vy = slots[o + 5] + params[1] * dt;
    var vz = slots[o + 6] + params[2] * dt;
    let keep = 1.0 / (1.0 + params[8] * dt);
    vx = params[4] + (vx - params[4]) * keep;
    vy = params[5] + (vy - params[5]) * keep;
    vz = params[6] + (vz - params[6]) * keep;
    let x = slots[o] + vx * dt;
    var y = slots[o + 1] + vy * dt;
    let z = slots[o + 2] + vz * dt;
    if y < params[9] {
      y = params[9];
      if vy < 0.0 { vy = -vy * params[10]; }
      let slide = 1.0 - params[11];
      vx = vx * slide;
      vz = vz * slide;
    }
    slots[o] = x;
    slots[o + 1] = y;
    slots[o + 2] = z;
    slots[o + 3] = life - dt;
    slots[o + 4] = vx;
    slots[o + 5] = vy;
    slots[o + 6] = vz;
    slots[o + 7] = 0.0;
  }
}
''';

/// Floats a body of debris takes: position xyz and radius, velocity xyz
/// and one over the mass, spin xyz and one over the inertia, and the
/// orientation xyzw.
const int debrisBodyFloats = 16;

/// Floats of the debris' parameters: gravity xyz and the substep;
/// friction, restitution, and what damping keeps of the velocity and the
/// spin; the speed limit, one over the grid's cell, two spares; the slots,
/// the grid's cells, the still shapes and a spare.
const int debrisParamFloats = 16;

/// Floats a still shape takes: a plane's normal and offset with nought
/// after, or a box's centre, a spare, its half extents and one.
const int debrisStaticFloats = 8;

/// The most still shapes debris lands on.
const int debrisMaxStatics = 64;

/// The empty cell of the debris' and the fluid's grids.
const int gridNone = 4294967295;

/// The cell of a point's coordinate [x] into a new local [name], the grid's
/// [scale] one over its cell.
String _coord(String name, String x, String scale) =>
    'let $name = i32(floor(clamp($x * $scale, -1e9, 1e9)));';

/// The grid's hash of cell ([x], [y], [z]) into a new local [name], over
/// [cells] cells, a power of two.
String _hash(String name, String x, String y, String z, String cells) =>
    'let $name = ((u32($x) * 73856093u) ^ (u32($y) * 19349663u) ^ '
    '(u32($z) * 83492791u)) & ($cells - 1u);';

/// Body [o]'s fields into locals prefixed [p].
String _body(String p, String o) =>
    '''
    let ${p}px = bodies[$o];
    let ${p}py = bodies[$o + 1];
    let ${p}pz = bodies[$o + 2];
    let ${p}r = bodies[$o + 3];
    let ${p}vx = bodies[$o + 4];
    let ${p}vy = bodies[$o + 5];
    let ${p}vz = bodies[$o + 6];
    let ${p}im = bodies[$o + 7];
    let ${p}wx = bodies[$o + 8];
    let ${p}wy = bodies[$o + 9];
    let ${p}wz = bodies[$o + 10];
    let ${p}ii = bodies[$o + 11];''';

const List<String> _bodyFields = <String>[
  'px', 'py', 'pz', 'r', 'vx', 'vy', 'vz', 'im', 'wx', 'wy', 'wz', 'ii', //
];

/// Locals prefixed [p], each [whenTrue]'s field where [condition] holds and
/// [whenFalse]'s where it does not.
String _pickBody(
  String p,
  String condition,
  String whenTrue,
  String whenFalse,
) => [
  for (final f in _bodyFields)
    '    let $p$f = select($condition, $whenTrue$f, $whenFalse$f);',
].join('\n');

/// The contact between bodies prefixed [lo] and [hi] into `{t}nx`,
/// `{t}ny`, `{t}nz` and `{t}gap`: touch_pair.
String _touchPair(String t, String lo, String hi) =>
    '''
    let ${t}dx = ${lo}px - ${hi}px;
    let ${t}dy = ${lo}py - ${hi}py;
    let ${t}dz = ${lo}pz - ${hi}pz;
    let ${t}len = sqrt(${t}dx * ${t}dx + ${t}dy * ${t}dy + ${t}dz * ${t}dz);
    var ${t}nx = 0.0;
    var ${t}ny = 1.0;
    var ${t}nz = 0.0;
    if ${t}len > 0.0 {
      ${t}nx = ${t}dx * (1.0 / ${t}len);
      ${t}ny = ${t}dy * (1.0 / ${t}len);
      ${t}nz = ${t}dz * (1.0 / ${t}len);
    }
    let ${t}gap = ${t}len - ${lo}r - ${hi}r;''';

/// The contact between body [b] and still shape [k] into `{t}nx`, `{t}ny`,
/// `{t}nz` and `{t}gap`: touch_still.
String _touchStill(String t, String b, String k) =>
    '''
    let ${t}s = $k * 8;
    var ${t}nx = 0.0;
    var ${t}ny = 0.0;
    var ${t}nz = 0.0;
    var ${t}gap = 0.0;
    if statics[${t}s + 7] == 0.0 {
      ${t}nx = statics[${t}s];
      ${t}ny = statics[${t}s + 1];
      ${t}nz = statics[${t}s + 2];
      ${t}gap = ${b}px * ${t}nx + ${b}py * ${t}ny + ${b}pz * ${t}nz - statics[${t}s + 3] - ${b}r;
    } else {
      let ${t}cx = statics[${t}s];
      let ${t}cy = statics[${t}s + 1];
      let ${t}cz = statics[${t}s + 2];
      let ${t}hx = statics[${t}s + 4];
      let ${t}hy = statics[${t}s + 5];
      let ${t}hz = statics[${t}s + 6];
      let ${t}dx = ${b}px - clamp(${b}px, ${t}cx - ${t}hx, ${t}cx + ${t}hx);
      let ${t}dy = ${b}py - clamp(${b}py, ${t}cy - ${t}hy, ${t}cy + ${t}hy);
      let ${t}dz = ${b}pz - clamp(${b}pz, ${t}cz - ${t}hz, ${t}cz + ${t}hz);
      let ${t}len = sqrt(${t}dx * ${t}dx + ${t}dy * ${t}dy + ${t}dz * ${t}dz);
      if ${t}len > 0.0 {
        ${t}nx = ${t}dx * (1.0 / ${t}len);
        ${t}ny = ${t}dy * (1.0 / ${t}len);
        ${t}nz = ${t}dz * (1.0 / ${t}len);
        ${t}gap = ${t}len - ${b}r;
      } else {
        let ${t}ex = ${t}hx - abs(${b}px - ${t}cx);
        let ${t}ey = ${t}hy - abs(${b}py - ${t}cy);
        let ${t}ez = ${t}hz - abs(${b}pz - ${t}cz);
        var ${t}axis = 0;
        var ${t}best = ${t}ex;
        if ${t}ey < ${t}best { ${t}best = ${t}ey; ${t}axis = 1; }
        if ${t}ez < ${t}best { ${t}best = ${t}ez; ${t}axis = 2; }
        if ${t}axis == 0 { ${t}nx = select(${b}px < ${t}cx, -1.0, 1.0); }
        if ${t}axis == 1 { ${t}ny = select(${b}py < ${t}cy, -1.0, 1.0); }
        if ${t}axis == 2 { ${t}nz = select(${b}pz < ${t}cz, -1.0, 1.0); }
        ${t}gap = -${t}best - ${b}r;
      }
    }''';

/// The impulse on [lo] of the contact `{t}` into `{q}x`, `{q}y`, `{q}z`,
/// [nLo] and [nHi] the two bodies' contact counts; [still] for a contact
/// with a still shape, where [hi] is not read. impulse().
String _impulse(
  String q,
  String t,
  String lo,
  String nLo,
  String hi,
  String nHi, {
  required bool still,
}) {
  // surface(b, n): v + cross(w, n · −r).
  String surface(String b, String s, String sign) =>
      '''
    let ${s}ax = $sign${t}nx * -${b}r;
    let ${s}ay = $sign${t}ny * -${b}r;
    let ${s}az = $sign${t}nz * -${b}r;
    let ${s}x = ${b}vx + (${b}wy * ${s}az - ${b}wz * ${s}ay);
    let ${s}y = ${b}vy + (${b}wz * ${s}ax - ${b}wx * ${s}az);
    let ${s}z = ${b}vz + (${b}wx * ${s}ay - ${b}wy * ${s}ax);''';
  return '''
    var ${q}x = 0.0;
    var ${q}y = 0.0;
    var ${q}z = 0.0;
    let ${q}reach = ${still ? '${lo}r' : '0.25 * (${lo}r + ${hi}r)'};
    if ${t}gap <= ${q}reach {
${surface(lo, '${q}sl', '')}
      var ${q}rx = ${q}slx;
      var ${q}ry = ${q}sly;
      var ${q}rz = ${q}slz;
${still ? '' : '''
${surface(hi, '${q}sh', '-')}
      ${q}rx = ${q}rx - ${q}shx;
      ${q}ry = ${q}ry - ${q}shy;
      ${q}rz = ${q}rz - ${q}shz;'''}
      let ${q}vn = ${q}rx * ${t}nx + ${q}ry * ${t}ny + ${q}rz * ${t}nz;
      let ${q}h = params[3];
      var ${q}goal = min(max(-${t}gap - 0.0005, 0.0) * 0.8 / ${q}h, 3.0);
      if ${t}gap > 0.0 { ${q}goal = -${t}gap / ${q}h; }
      if ${q}vn < -1.0 && ${t}gap <= 0.0005 {
        ${q}goal = max(${q}goal, -params[5] * ${q}vn);
      }
      let ${q}dvn = ${q}goal - ${q}vn;
      if ${q}dvn > 0.0 {
        let ${q}wl = ${lo}im * f32($nLo);
        let ${q}wh = ${still ? '0.0' : '${hi}im * f32($nHi)'};
        let ${q}pn = ${q}dvn / (${q}wl + ${q}wh);
        ${q}x = ${t}nx * ${q}pn;
        ${q}y = ${t}ny * ${q}pn;
        ${q}z = ${t}nz * ${q}pn;
        let ${q}tx = ${q}rx - ${t}nx * ${q}vn;
        let ${q}ty = ${q}ry - ${t}ny * ${q}vn;
        let ${q}tz = ${q}rz - ${t}nz * ${q}vn;
        let ${q}slide = sqrt(${q}tx * ${q}tx + ${q}ty * ${q}ty + ${q}tz * ${q}tz);
        if ${q}slide > 0.0 {
          var ${q}k = (${lo}im + ${lo}r * ${lo}r * ${lo}ii) * f32($nLo);
${still ? '' : '          ${q}k = ${q}k + (${hi}im + ${hi}r * ${hi}r * ${hi}ii) * f32($nHi);'}
          let ${q}pt = min(${q}slide / ${q}k, params[4] * ${q}pn);
          ${q}x = ${q}x - ${q}tx * (${q}pt / ${q}slide);
          ${q}y = ${q}y - ${q}ty * (${q}pt / ${q}slide);
          ${q}z = ${q}z - ${q}tz * (${q}pt / ${q}slide);
        }
      }
    }''';
}

/// What the debris' contact passes share: the body's cell, a walk of the
/// 27 cells round it, each cell's list, and every other body met there
/// whose cell is that one; then the still shapes. [pair] is what is done
/// with a pair met, [stillShape] with a still shape, both with the body as
/// `b` and the other as `o`, the contact as `t`.
String _gather(String pair, String stillShape) =>
    '''
${_body('b', 'i * 16')}
    if !(br > 0.0) { return; }
    let scale = params[9];
    let cells = u32(params[13]);
    let capacity = u32(params[12]);
    ${_coord('cx', 'bpx', 'scale')}
    ${_coord('cy', 'bpy', 'scale')}
    ${_coord('cz', 'bpz', 'scale')}
    for gx in cx - 1 .. cx + 2 {
      for gy in cy - 1 .. cy + 2 {
        for gz in cz - 1 .. cz + 2 {
          ${_hash('cell', 'gx', 'gy', 'gz', 'cells')}
          var j = atomicLoad(head, cell);
          for walk in 0u .. capacity {
            if j == ${gridNone}u { break; }
            let after = next[j];
${_body('o', 'i32(j) * 16')}
            ${_coord('ox', 'opx', 'scale')}
            ${_coord('oy', 'opy', 'scale')}
            ${_coord('oz', 'opz', 'scale')}
            // Another cell sharing this one's hash: met there.
            if i32(j) != i && ox == gx && oy == gy && oz == gz {
              let lower = u32(i) < j;
${_pickBody('lo', 'lower', 'b', 'o')}
${_pickBody('hi', 'lower', 'o', 'b')}
${_touchPair('t', 'lo', 'hi')}
$pair
            }
            j = after;
          }
        }
      }
    }
    for k in 0 .. i32(params[14]) {
${_touchStill('t', 'b', 'k')}
$stillShape
    }''';

/// The debris' passes, a substep each: `DebrisClearCells`,
/// `DebrisGravityGrid`, `DebrisCountContacts`, then `DebrisSolve` and
/// `DebrisAdopt` between its iterations, and `DebrisIntegrate`.
final String debrisKernels =
    '''
kernel 2

// Every cell of the grid empty.
compute DebrisClearCells {
  workgroup 64;
  buffer head: u32[] atomic;
  buffer params: f32[] read;
  kernel {
    if id.x >= u32(params[13]) { return; }
    atomicStore(head, id.x, ${gridNone}u);
  }
}

// Gravity and the speed limit, and each body put in its cell's list.
compute DebrisGravityGrid {
  workgroup 64;
  buffer bodies: f32[] read_write;
  buffer head: u32[] atomic;
  buffer next: u32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[12]) { return; }
    let o = i * 16;
    if !(bodies[o + 3] > 0.0) { return; }
    let h = params[3];
    var vx = bodies[o + 4] + params[0] * h;
    var vy = bodies[o + 5] + params[1] * h;
    var vz = bodies[o + 6] + params[2] * h;
    let speed2 = vx * vx + vy * vy + vz * vz;
    if speed2 > params[8] * params[8] {
      let scale = params[8] / sqrt(speed2);
      vx = vx * scale;
      vy = vy * scale;
      vz = vz * scale;
    }
    bodies[o + 4] = vx;
    bodies[o + 5] = vy;
    bodies[o + 6] = vz;
    ${_coord('cx', 'bodies[o]', 'params[9]')}
    ${_coord('cy', 'bodies[o + 1]', 'params[9]')}
    ${_coord('cz', 'bodies[o + 2]', 'params[9]')}
    ${_hash('cell', 'cx', 'cy', 'cz', 'u32(params[13])')}
    next[i] = atomicExchange(head, cell, u32(i));
  }
}

// How many contacts each body has, which its impulses are shared over.
compute DebrisCountContacts {
  workgroup 64;
  buffer bodies: f32[] read;
  buffer head: u32[] atomic;
  buffer next: u32[] read;
  buffer statics: f32[] read;
  buffer contacts: u32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[12]) { return; }
    var count = 0u;
${_gather('''
              if tgap <= 0.25 * (lor + hir) { count = count + 1u; }''', '''
      if tgap <= br { count = count + 1u; }''')}
    contacts[i] = count;
  }
}

// One iteration's impulses on each body, from the motion its contacts
// stood at, into its motion.
compute DebrisSolve {
  workgroup 64;
  buffer bodies: f32[] read;
  buffer head: u32[] atomic;
  buffer next: u32[] read;
  buffer statics: f32[] read;
  buffer contacts: u32[] read;
  buffer motion: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[12]) { return; }
    var dvx = bodies[i * 16 + 4];
    var dvy = bodies[i * 16 + 5];
    var dvz = bodies[i * 16 + 6];
    var dwx = bodies[i * 16 + 8];
    var dwy = bodies[i * 16 + 9];
    var dwz = bodies[i * 16 + 10];
${_gather('''
              let nlo = contacts[select(lower, u32(i), j)];
              let nhi = contacts[select(lower, j, u32(i))];
${_impulse('q', 't', 'lo', 'nlo', 'hi', 'nhi', still: false)}
              let sign = select(lower, 1.0, -1.0);
              let mx = qx * sign;
              let my = qy * sign;
              let mz = qz * sign;
              dvx = dvx + mx * bim;
              dvy = dvy + my * bim;
              dvz = dvz + mz * bim;
              let ax = tnx * sign * -br;
              let ay = tny * sign * -br;
              let az = tnz * sign * -br;
              dwx = dwx + (ay * mz - az * my) * bii;
              dwy = dwy + (az * mx - ax * mz) * bii;
              dwz = dwz + (ax * my - ay * mx) * bii;''', '''
${_impulse('q', 't', 'b', 'contacts[i]', 'b', '0u', still: true)}
      dvx = dvx + qx * bim;
      dvy = dvy + qy * bim;
      dvz = dvz + qz * bim;
      let ax = tnx * -br;
      let ay = tny * -br;
      let az = tnz * -br;
      dwx = dwx + (ay * qz - az * qy) * bii;
      dwy = dwy + (az * qx - ax * qz) * bii;
      dwz = dwz + (ax * qy - ay * qx) * bii;''')}
    let m = i * 8;
    motion[m] = dvx;
    motion[m + 1] = dvy;
    motion[m + 2] = dvz;
    motion[m + 4] = dwx;
    motion[m + 5] = dwy;
    motion[m + 6] = dwz;
  }
}

// The last iteration's motion taken as the bodies' own, for the next.
compute DebrisAdopt {
  workgroup 64;
  buffer bodies: f32[] read_write;
  buffer motion: f32[] read;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[12]) || !(bodies[i * 16 + 3] > 0.0) { return; }
    bodies[i * 16 + 4] = motion[i * 8];
    bodies[i * 16 + 5] = motion[i * 8 + 1];
    bodies[i * 16 + 6] = motion[i * 8 + 2];
    bodies[i * 16 + 8] = motion[i * 8 + 4];
    bodies[i * 16 + 9] = motion[i * 8 + 5];
    bodies[i * 16 + 10] = motion[i * 8 + 6];
  }
}

// Damping, the move, and the turn, renormalised.
compute DebrisIntegrate {
  workgroup 64;
  buffer bodies: f32[] read_write;
  buffer motion: f32[] read;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[12]) { return; }
    let o = i * 16;
    if !(bodies[o + 3] > 0.0) { return; }
    let h = params[3];
    let vx = motion[i * 8] * params[6];
    let vy = motion[i * 8 + 1] * params[6];
    let vz = motion[i * 8 + 2] * params[6];
    let wx = motion[i * 8 + 4] * params[7];
    let wy = motion[i * 8 + 5] * params[7];
    let wz = motion[i * 8 + 6] * params[7];
    let qx = bodies[o + 12];
    let qy = bodies[o + 13];
    let qz = bodies[o + 14];
    let qw = bodies[o + 15];
    let k = 0.5 * h;
    var rx = qx + k * (wx * qw + wy * qz - wz * qy);
    var ry = qy + k * (wy * qw + wz * qx - wx * qz);
    var rz = qz + k * (wz * qw + wx * qy - wy * qx);
    var rw = qw - k * (wx * qx + wy * qy + wz * qz);
    let norm = sqrt(rx * rx + ry * ry + rz * rz + rw * rw);
    rx = rx / norm;
    ry = ry / norm;
    rz = rz / norm;
    rw = rw / norm;
    bodies[o] = bodies[o] + vx * h;
    bodies[o + 1] = bodies[o + 1] + vy * h;
    bodies[o + 2] = bodies[o + 2] + vz * h;
    bodies[o + 4] = vx;
    bodies[o + 5] = vy;
    bodies[o + 6] = vz;
    bodies[o + 8] = wx;
    bodies[o + 9] = wy;
    bodies[o + 10] = wz;
    bodies[o + 12] = rx;
    bodies[o + 13] = ry;
    bodies[o + 14] = rz;
    bodies[o + 15] = rw;
  }
}
''';

/// Floats a point of cloth takes in `position`, `previous` and
/// `velocity`: xyz and one over its mass (velocity: a spare).
const int clothPointFloats = 4;

/// Floats of the cloth's parameters: gravity xyz and the substep; the wind
/// xyz and what drag keeps of the difference; what damping keeps, one over
/// the substep squared, the floor raised by the thickness, the thickness;
/// the friction, three spares; the points, the balls, two spares.
const int clothParamFloats = 20;

/// The most balls cloth is kept off.
const int clothMaxBalls = 16;

/// The cloth's passes, a substep each: `ClothPredict`; for each colour of
/// the core's colouring in order, `ClothSolve` then `ClothNextColour`; and
/// `ClothCollide`. `ClothPredict` starts the colours over. `edges` is the
/// colouring as the core hands it — two point indices, the rest length and
/// the compliance, four floats an edge, colour by colour — and `colours`
/// each colour's first edge and its count.
const String clothKernels = '''
kernel 1

// Each point moved by gravity and the wind, damped, its last place kept.
compute ClothPredict {
  workgroup 64;
  buffer position: f32[] read_write;
  buffer previous: f32[] read_write;
  buffer velocity: f32[] read_write;
  buffer colour: u32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i == 0 { colour[0] = 0u; }
    if i >= i32(params[16]) { return; }
    let o = i * 4;
    let px = position[o];
    let py = position[o + 1];
    let pz = position[o + 2];
    let pw = position[o + 3];
    previous[o] = px;
    previous[o + 1] = py;
    previous[o + 2] = pz;
    previous[o + 3] = pw;
    if pw == 0.0 { return; }
    let h = params[3];
    var vx = velocity[o] + params[0] * h;
    var vy = velocity[o + 1] + params[1] * h;
    var vz = velocity[o + 2] + params[2] * h;
    vx = params[4] + (vx - params[4]) * params[7];
    vy = params[5] + (vy - params[5]) * params[7];
    vz = params[6] + (vz - params[6]) * params[7];
    vx = vx * params[8];
    vy = vy * params[8];
    vz = vz * params[8];
    velocity[o] = vx;
    velocity[o + 1] = vy;
    velocity[o + 2] = vz;
    velocity[o + 3] = 0.0;
    position[o] = px + vx * h;
    position[o + 1] = py + vy * h;
    position[o + 2] = pz + vz * h;
  }
}

// The colour colour[0] says: no two of its edges share a point.
compute ClothSolve {
  workgroup 64;
  buffer position: f32[] read_write;
  buffer edges: f32[] read;
  buffer colours: u32[] read;
  buffer colour: u32[] read;
  buffer params: f32[] read;
  kernel {
    let c = colour[0];
    if id.x >= colours[c * 2u + 1u] { return; }
    let e = i32(colours[c * 2u] + id.x) * 4;
    let a = i32(u32(edges[e])) * 4;
    let b = i32(u32(edges[e + 1])) * 4;
    let rest = edges[e + 2];
    let compliance = edges[e + 3];
    let aw = position[a + 3];
    let bw = position[b + 3];
    let w = aw + bw + compliance * params[9];
    if !(w > 0.0) { return; }
    let dx = position[a] - position[b];
    let dy = position[a + 1] - position[b + 1];
    let dz = position[a + 2] - position[b + 2];
    let dist = sqrt(dx * dx + dy * dy + dz * dz);
    if !(dist > 0.0) { return; }
    let lambda = (rest - dist) / w;
    let nx = dx * (1.0 / dist);
    let ny = dy * (1.0 / dist);
    let nz = dz * (1.0 / dist);
    position[a] = position[a] + nx * (aw * lambda);
    position[a + 1] = position[a + 1] + ny * (aw * lambda);
    position[a + 2] = position[a + 2] + nz * (aw * lambda);
    position[b] = position[b] + nx * (-bw * lambda);
    position[b + 1] = position[b + 1] + ny * (-bw * lambda);
    position[b + 2] = position[b + 2] + nz * (-bw * lambda);
  }
}

// On to the next colour.
compute ClothNextColour {
  workgroup 1;
  buffer colour: u32[] read_write;
  kernel {
    if id.x == 0u { colour[0] = colour[0] + 1u; }
  }
}

// The balls and the floor pushed out of, with friction, and the velocity
// taken from where each point went.
compute ClothCollide {
  workgroup 64;
  buffer position: f32[] read_write;
  buffer previous: f32[] read;
  buffer velocity: f32[] read_write;
  buffer balls: f32[] read;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[16]) { return; }
    let o = i * 4;
    let pw = position[o + 3];
    if pw == 0.0 {
      velocity[o] = 0.0;
      velocity[o + 1] = 0.0;
      velocity[o + 2] = 0.0;
      velocity[o + 3] = 0.0;
      return;
    }
    var x = position[o];
    var y = position[o + 1];
    var z = position[o + 2];
    let wx = previous[o];
    let wy = previous[o + 1];
    let wz = previous[o + 2];
    for k in 0 .. i32(params[17]) {
      let bx = balls[k * 4];
      let by = balls[k * 4 + 1];
      let bz = balls[k * 4 + 2];
      let dx = x - bx;
      let dy = y - by;
      let dz = z - bz;
      let dist = sqrt(dx * dx + dy * dy + dz * dz);
      let reach = balls[k * 4 + 3] + params[11];
      if !(dist < reach) { continue; }
      var nx = 0.0;
      var ny = 1.0;
      var nz = 0.0;
      if dist > 0.0 {
        nx = dx * (1.0 / dist);
        ny = dy * (1.0 / dist);
        nz = dz * (1.0 / dist);
      }
      x = bx + nx * reach;
      y = by + ny * reach;
      z = bz + nz * reach;
      let mx = x - wx;
      let my = y - wy;
      let mz = z - wz;
      let along = -(mx * nx + my * ny + mz * nz);
      let sx = mx + nx * along;
      let sy = my + ny * along;
      let sz = mz + nz * along;
      x = x + sx * -params[12];
      y = y + sy * -params[12];
      z = z + sz * -params[12];
    }
    if y < params[10] {
      y = params[10];
      let mx = x - wx;
      let mz = z - wz;
      x = x + mx * -params[12];
      z = z + mz * -params[12];
    }
    position[o] = x;
    position[o + 1] = y;
    position[o + 2] = z;
    let inv = 1.0 / params[3];
    velocity[o] = (x - wx) * inv;
    velocity[o + 1] = (y - wy) * inv;
    velocity[o + 2] = (z - wz) * inv;
    velocity[o + 3] = 0.0;
  }
}
''';

/// Floats a particle of the fluid takes in each of its buffers: xyz and a
/// fourth (in `position` the density over the rest density; in `lam` the
/// density itself second).
const int fluidParticleFloats = 4;

/// Floats of the fluid's parameters: gravity xyz and the substep; the
/// kernel's width, poly6's and spiky's constants, the rest density; the
/// tank's low corner (less a margin), one over the grid's cell; its high
/// corner, the viscosity; the relaxation, the spacing, two spares; the
/// particles, the grid's cells, two spares; the tank's walls, low and
/// high, each with a spare.
const int fluidParamFloats = 32;

/// poly6(r²) into a new local [name].
String _poly6(String name, String r2) =>
    '''
    var $name = 0.0;
    let ${name}d = params[4] * params[4] - $r2;
    if ${name}d > 0.0 { $name = params[5] * ${name}d * ${name}d * ${name}d; }''';

/// The walls' density and push at ([px], [py], [pz]) into `wd`, `wpx`,
/// `wpy` and `wpz`: walls(), still layers past each wall within reach.
String _walls(String px, String py, String pz) {
  final out = StringBuffer('''
    var wd = 0.0;
    var wpx = 0.0;
    var wpy = 0.0;
    var wpz = 0.0;
    let ws = params[17];
    let wh = params[4];''');
  const axes = <String>['x', 'y', 'z'];
  final p = <String>[px, py, pz];
  for (var axis = 0; axis < 3; axis++) {
    for (var side = 0; side < 2; side++) {
      final w = 'w$axis$side';
      final off = side == 0
          ? '${p[axis]} - params[${24 + axis}]'
          : 'params[${28 + axis}] - ${p[axis]}';
      out.write('''

    var ${w}n = 0.0;
    var ${w}z = $off + ws * 0.5;
    for ${w}k in 0 .. 64 {
      if !(${w}z < wh) { break; }
      for ${w}i in -2 .. 3 {
        for ${w}j in -2 .. 3 {
          let ${w}r2 = f32(${w}i * ${w}i + ${w}j * ${w}j) * ws * ws + ${w}z * ${w}z;
          if !(${w}r2 < wh * wh) { continue; }
${_poly6('${w}p', '${w}r2')}
          wd = wd + ${w}p;
          let ${w}r = sqrt(${w}r2);
          let ${w}q = wh - ${w}r;
          ${w}n = ${w}n + params[6] * ${w}q * ${w}q / ${w}r * ${w}z;
        }
      }
      ${w}z = ${w}z + ws;
    }
    wp${axes[axis]} = wp${axes[axis]} + ${side == 0 ? '' : '-'}${w}n;''');
    }
  }
  return out.toString();
}

/// A walk over particle `i`'s neighbours in the 27 cells round its own,
/// doing [visit] with each other particle `j` within reach, `dx`, `dy`,
/// `dz` from it, `r2` and `r` its distance squared and its distance.
String _neighbours(String visit) =>
    '''
    let px = predicted[i * 4];
    let py = predicted[i * 4 + 1];
    let pz = predicted[i * 4 + 2];
    let cells = u32(params[21]);
    let count = u32(params[20]);
    for gx in link[i * 4 + 1] - 1 .. link[i * 4 + 1] + 2 {
      for gy in link[i * 4 + 2] - 1 .. link[i * 4 + 2] + 2 {
        for gz in link[i * 4 + 3] - 1 .. link[i * 4 + 3] + 2 {
          ${_hash('cell', 'gx', 'gy', 'gz', 'cells')}
          var j = atomicLoad(head, cell);
          for walk in 0u .. count {
            if j == ${gridNone}u { break; }
            let l = i32(j) * 4;
            let after = u32(link[l]);
            if link[l + 1] == gx && link[l + 2] == gy && link[l + 3] == gz {
              let dx = px - predicted[l];
              let dy = py - predicted[l + 1];
              let dz = pz - predicted[l + 2];
              let r2 = dx * dx + dy * dy + dz * dz;
              if r2 < params[4] * params[4] {
                let r = sqrt(r2);
$visit
              }
            }
            j = after;
          }
        }
      }
    }''';

/// spiky(d, r) into `{name}x`, `{name}y`, `{name}z`.
String _spiky(String name, String dx, String dy, String dz, String r) =>
    '''
    var ${name}x = 0.0;
    var ${name}y = 0.0;
    var ${name}z = 0.0;
    if $r > 0.0 && $r < params[4] {
      let ${name}k = params[4] - $r;
      let ${name}s = params[6] * ${name}k * ${name}k / $r;
      ${name}x = $dx * ${name}s;
      ${name}y = $dy * ${name}s;
      ${name}z = $dz * ${name}s;
    }''';

/// The fluid tank's passes, a substep each: `FluidClearCells`,
/// `FluidPredict`; `FluidDensity`, `FluidSpread` and `FluidAdoptSpread`
/// for each iteration; then `FluidVelocity`, `FluidSmooth` and
/// `FluidFinish`.
final String fluidKernels =
    '''
kernel 2

compute FluidClearCells {
  workgroup 64;
  buffer head: u32[] atomic;
  buffer params: f32[] read;
  kernel {
    if id.x >= u32(params[21]) { return; }
    atomicStore(head, id.x, ${gridNone}u);
  }
}

// Gravity, the move predicted, and each particle put in its cell's list.
compute FluidPredict {
  workgroup 64;
  buffer position: f32[] read;
  buffer predicted: f32[] read_write;
  buffer velocity: f32[] read_write;
  buffer head: u32[] atomic;
  buffer link: i32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    let o = i * 4;
    let h = params[3];
    let vx = velocity[o] + params[0] * h;
    let vy = velocity[o + 1] + params[1] * h;
    let vz = velocity[o + 2] + params[2] * h;
    let px = position[o] + vx * h;
    let py = position[o + 1] + vy * h;
    let pz = position[o + 2] + vz * h;
    velocity[o] = vx;
    velocity[o + 1] = vy;
    velocity[o + 2] = vz;
    velocity[o + 3] = 0.0;
    predicted[o] = px;
    predicted[o + 1] = py;
    predicted[o + 2] = pz;
    predicted[o + 3] = 0.0;
    ${_coord('cx', 'px', 'params[11]')}
    ${_coord('cy', 'py', 'params[11]')}
    ${_coord('cz', 'pz', 'params[11]')}
    ${_hash('cell', 'cx', 'cy', 'cz', 'u32(params[21])')}
    link[o] = i32(atomicExchange(head, cell, u32(i)));
    link[o + 1] = cx;
    link[o + 2] = cy;
    link[o + 3] = cz;
  }
}

// Each particle's density, and the multiplier that pulls it to rest.
compute FluidDensity {
  workgroup 64;
  buffer predicted: f32[] read;
  buffer head: u32[] atomic;
  buffer link: i32[] read;
  buffer lam: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    let rest = params[7];
    var density = 0.0;
    var gx2 = 0.0;
    var gy2 = 0.0;
    var gz2 = 0.0;
    var g2 = 0.0;
${_neighbours('''
${_poly6('k6', 'r2')}
                density = density + k6;
                if i32(j) != i {
${_spiky('s', 'dx', 'dy', 'dz', 'r')}
                  let sgx = sx * (1.0 / rest);
                  let sgy = sy * (1.0 / rest);
                  let sgz = sz * (1.0 / rest);
                  gx2 = gx2 + sgx;
                  gy2 = gy2 + sgy;
                  gz2 = gz2 + sgz;
                  g2 = g2 + (sgx * sgx + sgy * sgy + sgz * sgz);
                }''')}
${_walls('px', 'py', 'pz')}
    density = density + wd;
    gx2 = gx2 + wpx * (1.0 / rest);
    gy2 = gy2 + wpy * (1.0 / rest);
    gz2 = gz2 + wpz * (1.0 / rest);
    let crowd = max(density / rest - 1.0, 0.0);
    let lambda = -crowd / (g2 + (gx2 * gx2 + gy2 * gy2 + gz2 * gz2) + params[16]);
    lam[i * 4] = lambda;
    lam[i * 4 + 1] = density;
  }
}

// Each particle moved by its own multiplier and its neighbours', held in
// the tank.
compute FluidSpread {
  workgroup 64;
  buffer predicted: f32[] read;
  buffer head: u32[] atomic;
  buffer link: i32[] read;
  buffer lam: f32[] read;
  buffer scratch: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    var tx = 0.0;
    var ty = 0.0;
    var tz = 0.0;
    let li = lam[i * 4];
${_neighbours('''
                if i32(j) != i {
${_spiky('s', 'dx', 'dy', 'dz', 'r')}
                  let both = li + lam[l];
                  tx = tx + sx * both;
                  ty = ty + sy * both;
                  tz = tz + sz * both;
                }''')}
${_walls('px', 'py', 'pz')}
    tx = tx + wpx * (li + li);
    ty = ty + wpy * (li + li);
    tz = tz + wpz * (li + li);
    let inv = 1.0 / params[7];
    scratch[i * 4] = clamp(px + tx * inv, params[8], params[12]);
    scratch[i * 4 + 1] = clamp(py + ty * inv, params[9], params[13]);
    scratch[i * 4 + 2] = clamp(pz + tz * inv, params[10], params[14]);
    scratch[i * 4 + 3] = 0.0;
  }
}

compute FluidAdoptSpread {
  workgroup 64;
  buffer predicted: f32[] read_write;
  buffer scratch: f32[] read;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    predicted[i * 4] = scratch[i * 4];
    predicted[i * 4 + 1] = scratch[i * 4 + 1];
    predicted[i * 4 + 2] = scratch[i * 4 + 2];
    predicted[i * 4 + 3] = scratch[i * 4 + 3];
  }
}

// The velocity from where each particle went.
compute FluidVelocity {
  workgroup 64;
  buffer position: f32[] read;
  buffer predicted: f32[] read;
  buffer velocity: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    let inv = 1.0 / params[3];
    velocity[i * 4] = (predicted[i * 4] - position[i * 4]) * inv;
    velocity[i * 4 + 1] = (predicted[i * 4 + 1] - position[i * 4 + 1]) * inv;
    velocity[i * 4 + 2] = (predicted[i * 4 + 2] - position[i * 4 + 2]) * inv;
    velocity[i * 4 + 3] = 0.0;
  }
}

// The viscosity: each velocity drawn towards its neighbours'.
compute FluidSmooth {
  workgroup 64;
  buffer predicted: f32[] read;
  buffer velocity: f32[] read;
  buffer head: u32[] atomic;
  buffer link: i32[] read;
  buffer scratch: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    var tx = 0.0;
    var ty = 0.0;
    var tz = 0.0;
    let rest = params[7];
${_neighbours('''
                if i32(j) != i {
${_poly6('k6', 'r2')}
                  let k = k6 / rest;
                  tx = tx + (velocity[l] - velocity[i * 4]) * k;
                  ty = ty + (velocity[l + 1] - velocity[i * 4 + 1]) * k;
                  tz = tz + (velocity[l + 2] - velocity[i * 4 + 2]) * k;
                }''')}
    scratch[i * 4] = velocity[i * 4] + tx * params[15];
    scratch[i * 4 + 1] = velocity[i * 4 + 1] + ty * params[15];
    scratch[i * 4 + 2] = velocity[i * 4 + 2] + tz * params[15];
    scratch[i * 4 + 3] = 0.0;
  }
}

// The step taken: the velocity smoothed, the position where it went, and
// its density over the rest density beside it.
compute FluidFinish {
  workgroup 64;
  buffer position: f32[] read_write;
  buffer predicted: f32[] read;
  buffer velocity: f32[] read_write;
  buffer scratch: f32[] read;
  buffer lam: f32[] read;
  buffer params: f32[] read;
  kernel {
    let i = i32(id.x);
    if i >= i32(params[20]) { return; }
    velocity[i * 4] = scratch[i * 4];
    velocity[i * 4 + 1] = scratch[i * 4 + 1];
    velocity[i * 4 + 2] = scratch[i * 4 + 2];
    velocity[i * 4 + 3] = 0.0;
    position[i * 4] = predicted[i * 4];
    position[i * 4 + 1] = predicted[i * 4 + 1];
    position[i * 4 + 2] = predicted[i * 4 + 2];
    position[i * 4 + 3] = lam[i * 4 + 1] / params[7];
  }
}
''';
