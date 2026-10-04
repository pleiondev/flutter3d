/*
 * The broadphase tree — P9, phase 4: a dynamic tree of boxes, as Box2D's
 * b2DynamicTree builds it, in three dimensions.
 *
 * Each body with a shape has a leaf holding a fat box — its own box grown
 * by F3D_FAT_MARGIN — so a body moving a little stays in its leaf and the
 * tree is not touched. A leaf goes in beside the node that costs least by
 * surface area, which is what a ray or a box searching the tree pays for,
 * and every node on the way back up is balanced by a rotation when one
 * side is two deeper than the other.
 *
 * The tree's shape depends on the order bodies arrive in, but nothing that
 * leaves the core does: the pairs it finds are sorted by slot, and a
 * contact depends only on the two shapes. So the tree is left out of a
 * snapshot and built again after a restore, and the restored world still
 * steps to the same bytes.
 */
#include "f3d_internal.h"

static F3dBox merge(F3dBox a, F3dBox b) {
  F3dBox m;
  m.lo = f3d_v3(f3d_min(a.lo.x, b.lo.x), f3d_min(a.lo.y, b.lo.y),
                f3d_min(a.lo.z, b.lo.z));
  m.hi = f3d_v3(f3d_max(a.hi.x, b.hi.x), f3d_max(a.hi.y, b.hi.y),
                f3d_max(a.hi.z, b.hi.z));
  return m;
}

/* Half the surface area, which orders boxes as the area does. */
static f3d_real area(F3dBox b) {
  const f3d_real x = b.hi.x - b.lo.x, y = b.hi.y - b.lo.y;
  const f3d_real z = b.hi.z - b.lo.z;
  return x * y + y * z + z * x;
}

static int contains(F3dBox outer, F3dBox inner) {
  return outer.lo.x <= inner.lo.x && outer.lo.y <= inner.lo.y &&
         outer.lo.z <= inner.lo.z && inner.hi.x <= outer.hi.x &&
         inner.hi.y <= outer.hi.y && inner.hi.z <= outer.hi.z;
}

static int is_leaf(const F3dTreeNode *n) { return n->child1 == -1; }

static int32_t max_i(int32_t a, int32_t b) { return a > b ? a : b; }

static int32_t allocate(F3dTree *tree) {
  if (tree->free_list == -1) {
    const uint32_t grown = tree->capacity == 0 ? 64u : tree->capacity * 2u;
    if (grown <= tree->capacity || grown > (uint32_t)INT32_MAX) return -1;
    F3dTreeNode *nodes = (F3dTreeNode *)f3d_realloc(
        tree->nodes, (size_t)grown * sizeof(F3dTreeNode));
    if (nodes == NULL) return -1;
    for (uint32_t i = tree->capacity; i < grown; i++) {
      f3d_zero(&nodes[i], sizeof nodes[i]);
      nodes[i].parent = i + 1u < grown ? (int32_t)(i + 1u) : -1;
      nodes[i].height = -1;
    }
    tree->nodes = nodes;
    tree->free_list = (int32_t)tree->capacity;
    tree->capacity = grown;
  }
  const int32_t id = tree->free_list;
  F3dTreeNode *n = &tree->nodes[id];
  tree->free_list = n->parent;
  n->parent = -1;
  n->child1 = n->child2 = -1;
  n->height = 0;
  n->slot = 0;
  return id;
}

static void release(F3dTree *tree, int32_t id) {
  tree->nodes[id].parent = tree->free_list;
  tree->nodes[id].height = -1;
  tree->free_list = id;
}

/* One rotation at [a] when one child is two deeper than the other; returns
 * the node now where [a] was. Erin Catto's, from Box2D. */
static int32_t balance(F3dTree *tree, int32_t ia) {
  F3dTreeNode *nodes = tree->nodes;
  F3dTreeNode *a = &nodes[ia];
  if (is_leaf(a) || a->height < 2) return ia;
  const int32_t ib = a->child1, ic = a->child2;
  F3dTreeNode *b = &nodes[ib], *c = &nodes[ic];
  const int32_t lean = c->height - b->height;
  if (lean > 1) {
    /* Raise c. */
    const int32_t i_f = c->child1, ig = c->child2;
    F3dTreeNode *f = &nodes[i_f], *g = &nodes[ig];
    c->child1 = ia;
    c->parent = a->parent;
    a->parent = ic;
    if (c->parent != -1) {
      if (nodes[c->parent].child1 == ia) {
        nodes[c->parent].child1 = ic;
      } else {
        nodes[c->parent].child2 = ic;
      }
    } else {
      tree->root = ic;
    }
    if (f->height > g->height) {
      c->child2 = i_f;
      a->child2 = ig;
      g->parent = ia;
      a->box = merge(b->box, g->box);
      c->box = merge(a->box, f->box);
      a->height = 1 + max_i(b->height, g->height);
      c->height = 1 + max_i(a->height, f->height);
    } else {
      c->child2 = ig;
      a->child2 = i_f;
      f->parent = ia;
      a->box = merge(b->box, f->box);
      c->box = merge(a->box, g->box);
      a->height = 1 + max_i(b->height, f->height);
      c->height = 1 + max_i(a->height, g->height);
    }
    return ic;
  }
  if (lean < -1) {
    /* Raise b. */
    const int32_t id = b->child1, ie = b->child2;
    F3dTreeNode *d = &nodes[id], *e = &nodes[ie];
    b->child1 = ia;
    b->parent = a->parent;
    a->parent = ib;
    if (b->parent != -1) {
      if (nodes[b->parent].child1 == ia) {
        nodes[b->parent].child1 = ib;
      } else {
        nodes[b->parent].child2 = ib;
      }
    } else {
      tree->root = ib;
    }
    if (d->height > e->height) {
      b->child2 = id;
      a->child1 = ie;
      e->parent = ia;
      a->box = merge(c->box, e->box);
      b->box = merge(a->box, d->box);
      a->height = 1 + max_i(c->height, e->height);
      b->height = 1 + max_i(a->height, d->height);
    } else {
      b->child2 = ie;
      a->child1 = id;
      d->parent = ia;
      a->box = merge(c->box, d->box);
      b->box = merge(a->box, e->box);
      a->height = 1 + max_i(c->height, d->height);
      b->height = 1 + max_i(a->height, e->height);
    }
    return ib;
  }
  return ia;
}

/* Refits and balances from [index] up to the root. */
static void climb(F3dTree *tree, int32_t index) {
  while (index != -1) {
    index = balance(tree, index);
    F3dTreeNode *n = &tree->nodes[index];
    const F3dTreeNode *c1 = &tree->nodes[n->child1];
    const F3dTreeNode *c2 = &tree->nodes[n->child2];
    n->height = 1 + max_i(c1->height, c2->height);
    n->box = merge(c1->box, c2->box);
    index = n->parent;
  }
}

int32_t f3d_tree_insert(F3dTree *tree, F3dBox box, uint32_t slot) {
  const int32_t leaf = allocate(tree);
  if (leaf == -1) return -1;
  tree->nodes[leaf].box = box;
  tree->nodes[leaf].slot = slot;
  tree->leaves++;
  if (tree->root == -1) {
    tree->root = leaf;
    return leaf;
  }
  /* The sibling: down from the root, at each node weighing a new parent
   * here against going on into either child, by the surface area each adds
   * — what goes in costs its own area, and every ancestor it widens costs
   * what it widens. */
  int32_t index = tree->root;
  while (!is_leaf(&tree->nodes[index])) {
    const F3dTreeNode *n = &tree->nodes[index];
    const f3d_real here = area(n->box);
    const f3d_real joined = area(merge(n->box, box));
    const f3d_real cost = F3D_R(2.0) * joined;
    const f3d_real inherited = F3D_R(2.0) * (joined - here);
    f3d_real child_cost[2];
    const int32_t children[2] = {n->child1, n->child2};
    for (int k = 0; k < 2; k++) {
      const F3dTreeNode *c = &tree->nodes[children[k]];
      const f3d_real grown = area(merge(c->box, box));
      child_cost[k] = (is_leaf(c) ? grown : grown - area(c->box)) + inherited;
    }
    if (cost < child_cost[0] && cost < child_cost[1]) break;
    index = child_cost[0] <= child_cost[1] ? children[0] : children[1];
  }
  const int32_t sibling = index;
  const int32_t old_parent = tree->nodes[sibling].parent;
  const int32_t parent = allocate(tree);
  if (parent == -1) {
    release(tree, leaf);
    tree->leaves--;
    return -1;
  }
  F3dTreeNode *nodes = tree->nodes; /* allocate may have moved them */
  nodes[parent].parent = old_parent;
  nodes[parent].box = merge(box, nodes[sibling].box);
  nodes[parent].height = nodes[sibling].height + 1;
  nodes[parent].child1 = sibling;
  nodes[parent].child2 = leaf;
  nodes[sibling].parent = parent;
  nodes[leaf].parent = parent;
  if (old_parent != -1) {
    if (nodes[old_parent].child1 == sibling) {
      nodes[old_parent].child1 = parent;
    } else {
      nodes[old_parent].child2 = parent;
    }
  } else {
    tree->root = parent;
  }
  climb(tree, nodes[leaf].parent);
  return leaf;
}

void f3d_tree_remove(F3dTree *tree, int32_t leaf) {
  F3dTreeNode *nodes = tree->nodes;
  tree->leaves--;
  if (leaf == tree->root) {
    tree->root = -1;
    release(tree, leaf);
    return;
  }
  const int32_t parent = nodes[leaf].parent;
  const int32_t grand = nodes[parent].parent;
  const int32_t sibling =
      nodes[parent].child1 == leaf ? nodes[parent].child2 : nodes[parent].child1;
  if (grand != -1) {
    if (nodes[grand].child1 == parent) {
      nodes[grand].child1 = sibling;
    } else {
      nodes[grand].child2 = sibling;
    }
    nodes[sibling].parent = grand;
    release(tree, parent);
    climb(tree, grand);
  } else {
    tree->root = sibling;
    nodes[sibling].parent = -1;
    release(tree, parent);
  }
  release(tree, leaf);
}

void f3d_tree_clear(F3dTree *tree) {
  f3d_free(tree->nodes);
  f3d_zero(tree, sizeof *tree);
  tree->root = -1;
  tree->free_list = -1;
}

void f3d_tree_query(const F3dTree *tree, F3dBox box,
                    int (*visit)(void *context, int32_t leaf), void *context) {
  if (tree->root == -1) return;
  /* A balanced tree of every body a computer can hold is under a hundred
   * deep, and a depth-first walk keeps one more than the depth waiting. */
  int32_t stack[256];
  int top = 0;
  stack[top++] = tree->root;
  while (top > 0) {
    const int32_t id = stack[--top];
    const F3dTreeNode *n = &tree->nodes[id];
    if (!f3d_box_overlap(n->box, box)) continue;
    if (is_leaf(n)) {
      if (!visit(context, id)) return;
    } else if (top + 2 <= 256) {
      stack[top++] = n->child2;
      stack[top++] = n->child1;
    }
  }
}

F3dBox f3d_box_of(const F3dWorld *world, const F3dSlot *s, f3d_real margin) {
  const F3dMat3 m = f3d_mat_of(s->orientation);
  F3dVec3 reach;
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      reach = f3d_v3(s->size.x, s->size.x, s->size.x);
      break;
    case F3D_SHAPE_CAPSULE: {
      const F3dVec3 axis = m.c[1];
      reach = f3d_v3(f3d_abs(axis.x) * s->size.y + s->size.x,
                     f3d_abs(axis.y) * s->size.y + s->size.x,
                     f3d_abs(axis.z) * s->size.y + s->size.x);
      break;
    }
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE: {
      /* A disc of radius r reaches r √(1 − a²) along a world axis whose
       * share of its own axis is a; the cylinder's and the cone's ends are
       * discs. Bounded here by the box round the shape's own box, which is
       * at most a few per cent larger and needs no root per axis. */
      const f3d_real r = s->size.x;
      const f3d_real h = s->shape == F3D_SHAPE_CYLINDER
                             ? s->size.y
                             : F3D_R(0.75) * s->size.y;
      const f3d_real hl[3] = {r, h, r};
      reach = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      for (int k = 0; k < 3; k++) {
        reach.x += f3d_abs(m.c[k].x) * hl[k];
        reach.y += f3d_abs(m.c[k].y) * hl[k];
        reach.z += f3d_abs(m.c[k].z) * hl[k];
      }
      break;
    }
    case F3D_SHAPE_HULL:
    case F3D_SHAPE_MESH: {
      /* The hull's or mesh's own box, turned: its centre may sit off the
       * origin. */
      F3dVec3 blo, bhi;
      if (s->shape == F3D_SHAPE_HULL && s->hull != 0 &&
          s->hull <= world->s.hull_count) {
        blo = world->hulls[s->hull - 1u].lo;
        bhi = world->hulls[s->hull - 1u].hi;
      } else if (s->shape == F3D_SHAPE_MESH && s->hull != 0 &&
                 s->hull <= world->s.mesh_count) {
        blo = world->meshes[s->hull - 1u].lo;
        bhi = world->meshes[s->hull - 1u].hi;
      } else {
        reach = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
        break;
      }
      const F3dVec3 c = f3d_scale(f3d_add(blo, bhi), F3D_R(0.5));
      const F3dVec3 hh = f3d_scale(f3d_sub(bhi, blo), F3D_R(0.5));
      const f3d_real hl[3] = {hh.x, hh.y, hh.z};
      const F3dVec3 shift = f3d_add(
          f3d_add(f3d_scale(m.c[0], c.x), f3d_scale(m.c[1], c.y)),
          f3d_scale(m.c[2], c.z));
      reach = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      for (int k = 0; k < 3; k++) {
        reach.x += f3d_abs(m.c[k].x) * hl[k];
        reach.y += f3d_abs(m.c[k].y) * hl[k];
        reach.z += f3d_abs(m.c[k].z) * hl[k];
      }
      const f3d_real grow = margin + s->rounding;
      reach = f3d_add(reach, f3d_v3(grow, grow, grow));
      F3dBox b;
      b.lo = f3d_sub(f3d_add(s->position, shift), reach);
      b.hi = f3d_add(f3d_add(s->position, shift), reach);
      return b;
    }
    default: {
      const f3d_real h[3] = {s->size.x, s->size.y, s->size.z};
      reach = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      for (int k = 0; k < 3; k++) {
        reach.x += f3d_abs(m.c[k].x) * h[k];
        reach.y += f3d_abs(m.c[k].y) * h[k];
        reach.z += f3d_abs(m.c[k].z) * h[k];
      }
      break;
    }
  }
  const f3d_real grow = margin + s->rounding;
  reach = f3d_add(reach, f3d_v3(grow, grow, grow));
  F3dBox b;
  b.lo = f3d_sub(s->position, reach);
  b.hi = f3d_add(s->position, reach);
  return b;
}

/* Room for a leaf index per slot of the arena. */
static int reserve_proxies(F3dWorld *world) {
  if (world->s.used <= world->proxy_capacity) return 1;
  uint32_t grown = world->proxy_capacity == 0 ? 64u : world->proxy_capacity;
  while (grown < world->s.used) grown *= 2u;
  int32_t *proxies =
      (int32_t *)f3d_realloc(world->proxies, (size_t)grown * sizeof(int32_t));
  if (proxies == NULL) return 0;
  for (uint32_t i = world->proxy_capacity; i < grown; i++) proxies[i] = -1;
  world->proxies = proxies;
  world->proxy_capacity = grown;
  return 1;
}

void f3d_update_proxies(F3dWorld *world, f3d_real dt) {
  if (!reserve_proxies(world)) return;
  F3dTree *tree = &world->tree;
  if (tree->capacity == 0 && tree->root == 0 && tree->free_list == 0) {
    tree->root = -1;
    tree->free_list = -1;
  }
  /* Half the contact margin on each body's side, so two leaves that do not
   * overlap are further apart than a contact reaches. */
  const f3d_real half = F3D_R(0.5) * world->s.contact_margin;
  for (uint32_t i = 0; i < world->s.used; i++) {
    const F3dSlot *s = &world->slots[i];
    int32_t *leaf = &world->proxies[i];
    const int wanted = s->live && s->shape != F3D_SHAPE_POINT;
    if (!wanted) {
      if (*leaf != -1) {
        f3d_tree_remove(tree, *leaf);
        *leaf = -1;
      }
      continue;
    }
    const F3dBox tight = f3d_swept_box(world, s, half, dt);
    if (*leaf != -1) {
      /* A slot taken by a new body keeps its old leaf only if the box still
       * fits: the leaf holds no handle, so it cannot go stale otherwise. */
      if (contains(tree->nodes[*leaf].box, tight)) continue;
      f3d_tree_remove(tree, *leaf);
      *leaf = -1;
    }
    F3dBox fat = tight;
    const F3dVec3 grow = f3d_v3(F3D_FAT_MARGIN, F3D_FAT_MARGIN, F3D_FAT_MARGIN);
    fat.lo = f3d_sub(fat.lo, grow);
    fat.hi = f3d_add(fat.hi, grow);
    *leaf = f3d_tree_insert(tree, fat, i);
  }
}

typedef struct Found {
  const F3dWorld *world;
  F3dBox box;
  F3dBody *out;
  uint32_t capacity;
  uint32_t count;
} Found;

static int found_one(void *context, int32_t leaf) {
  Found *f = (Found *)context;
  const uint32_t slot = f->world->tree.nodes[leaf].slot;
  const F3dSlot *s = &f->world->slots[slot];
  if (!f3d_box_overlap(f3d_box_of(f->world, s, F3D_R(0.0)), f->box)) return 1;
  /* Kept in slot order as they come, so the answer does not depend on the
   * tree's shape: an insertion into the sorted part found so far. */
  const F3dBody handle = f3d_handle_of(f->world, s);
  uint32_t at = f->count < f->capacity ? f->count : f->capacity;
  while (at > 0 && (uint32_t)(f->out[at - 1] & 0xffffffffu) > slot) at--;
  if (at < f->capacity) {
    const uint32_t last = f->count < f->capacity ? f->count : f->capacity - 1u;
    for (uint32_t k = last; k > at; k--) f->out[k] = f->out[k - 1];
    f->out[at] = handle;
  }
  f->count++;
  return 1;
}

F3dBox f3d_swept_box(const F3dWorld *world, const F3dSlot *s, f3d_real margin,
                     f3d_real dt) {
  F3dBox b = f3d_box_of(world, s, margin);
  if (!world->s.speculative || s->type != F3D_BODY_DYNAMIC ||
      (s->flags & F3D_FLAG_ASLEEP)) {
    return b;
  }
  const F3dVec3 move = f3d_scale(s->velocity, dt);
  b.lo = f3d_v3(f3d_min(b.lo.x, b.lo.x + move.x), f3d_min(b.lo.y, b.lo.y + move.y),
                f3d_min(b.lo.z, b.lo.z + move.z));
  b.hi = f3d_v3(f3d_max(b.hi.x, b.hi.x + move.x), f3d_max(b.hi.y, b.hi.y + move.y),
                f3d_max(b.hi.z, b.hi.z + move.z));
  return b;
}

f3d_real f3d_reach_of(const F3dWorld *world, const F3dSlot *s) {
  const F3dBox b = f3d_box_of(world, s, F3D_R(0.0));
  const F3dVec3 half = f3d_scale(f3d_sub(b.hi, b.lo), F3D_R(0.5));
  return f3d_sqrt(f3d_dot(half, half));
}

uint32_t f3d_world_query_box(F3dWorld *world, f3d_real lx, f3d_real ly,
                             f3d_real lz, f3d_real hx, f3d_real hy,
                             f3d_real hz, F3dBody *out, uint32_t capacity) {
  f3d_update_proxies(world, F3D_R(0.0));
  Found f;
  f.world = world;
  f.box.lo = f3d_v3(lx, ly, lz);
  f.box.hi = f3d_v3(hx, hy, hz);
  f.out = out;
  f.capacity = capacity;
  f.count = 0;
  f3d_tree_query(&world->tree, f.box, found_one, &f);
  return f.count;
}
