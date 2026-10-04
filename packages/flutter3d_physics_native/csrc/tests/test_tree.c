/*
 * The broadphase tree, tested in C — P9, phase 4: its invariants after
 * every kind of change, its balance where a naive tree degenerates, its
 * queries against trying every box, leaves that stay put while their body
 * moves inside them, and a world that rebuilds it after a restore.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static F3dBox box_at(double x, double y, double z, double h) {
  F3dBox b;
  b.lo = f3d_v3((f3d_real)(x - h), (f3d_real)(y - h), (f3d_real)(z - h));
  b.hi = f3d_v3((f3d_real)(x + h), (f3d_real)(y + h), (f3d_real)(z + h));
  return b;
}

static int encloses(F3dBox outer, F3dBox inner) {
  return outer.lo.x <= inner.lo.x && outer.lo.y <= inner.lo.y &&
         outer.lo.z <= inner.lo.z && inner.hi.x <= outer.hi.x &&
         inner.hi.y <= outer.hi.y && inner.hi.z <= outer.hi.z;
}

/* Every link, box and height, below [id]; returns the leaves under it. */
static uint32_t valid(const F3dTree *t, int32_t id, int32_t parent, int *ok) {
  const F3dTreeNode *n = &t->nodes[id];
  if (n->parent != parent) *ok = 0;
  if (n->child1 == -1) {
    if (n->child2 != -1 || n->height != 0) *ok = 0;
    return 1;
  }
  const F3dTreeNode *a = &t->nodes[n->child1], *b = &t->nodes[n->child2];
  if (!encloses(n->box, a->box) || !encloses(n->box, b->box)) *ok = 0;
  const int32_t hi = a->height > b->height ? a->height : b->height;
  if (n->height != 1 + hi) *ok = 0;
  if (abs(a->height - b->height) > 1) *ok = 0;
  return valid(t, n->child1, id, ok) + valid(t, n->child2, id, ok);
}

static int tree_valid(const F3dTree *t) {
  int ok = 1;
  const uint32_t leaves = t->root == -1 ? 0 : valid(t, t->root, -1, &ok);
  return ok && leaves == t->leaves;
}

static double uniform(unsigned *state) {
  *state = *state * 1664525u + 1013904223u;
  return (*state >> 8) / 16777216.0;
}

typedef struct Hits {
  uint32_t slots[4096];
  uint32_t count;
  const F3dTree *tree;
} Hits;

static int hit(void *context, int32_t leaf) {
  Hits *h = (Hits *)context;
  h->slots[h->count++] = h->tree->nodes[leaf].slot;
  return 1;
}

static int by_value(const void *a, const void *b) {
  const uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
  return x < y ? -1 : x > y;
}

static void test_balanced_and_valid(void) {
  /* Boxes in a row along x, each further than the last: a tree that only
   * appends would be a list a thousand deep. Balanced, it stays within a
   * small multiple of log₂ n. */
  enum { N = 1024 };
  F3dTree t;
  memset(&t, 0, sizeof t);
  t.root = -1;
  t.free_list = -1;
  static int32_t leaves[N];
  for (int i = 0; i < N; i++) {
    leaves[i] = f3d_tree_insert(&t, box_at(i, 0, 0, 0.4), (uint32_t)i);
    CHECK(leaves[i] >= 0);
  }
  CHECK(tree_valid(&t));
  CHECK(t.nodes[t.root].height <= 2 * 10 + 2);
  /* Half taken out, every other one: still a valid, balanced tree. */
  for (int i = 0; i < N; i += 2) f3d_tree_remove(&t, leaves[i]);
  CHECK(t.leaves == N / 2);
  CHECK(tree_valid(&t));
  CHECK(t.nodes[t.root].height <= 2 * 9 + 2);
  /* Freed nodes are used again before the tree grows. */
  const uint32_t capacity = t.capacity;
  for (int i = 0; i < N; i += 2) {
    leaves[i] = f3d_tree_insert(&t, box_at(i, 3, 0, 0.4), (uint32_t)i);
  }
  CHECK(t.capacity == capacity);
  CHECK(tree_valid(&t));
  /* All out: empty. */
  for (int i = 0; i < N; i++) f3d_tree_remove(&t, leaves[i]);
  CHECK(t.root == -1 && t.leaves == 0);
  f3d_tree_clear(&t);
}

static void test_queries_find_every_box(void) {
  /* Two thousand boxes of every size scattered over a hundred metres, and
   * two hundred queries: each finds exactly the boxes trying every one
   * finds. */
  enum { N = 2000 };
  static F3dBox boxes[N];
  F3dTree t;
  memset(&t, 0, sizeof t);
  t.root = -1;
  t.free_list = -1;
  unsigned seed = 7u;
  for (int i = 0; i < N; i++) {
    boxes[i] = box_at(uniform(&seed) * 100, uniform(&seed) * 20,
                      uniform(&seed) * 100, 0.1 + uniform(&seed) * 2);
    f3d_tree_insert(&t, boxes[i], (uint32_t)i);
  }
  CHECK(tree_valid(&t));
  static Hits hits;
  int all = 1;
  for (int q = 0; q < 200; q++) {
    const F3dBox probe = box_at(uniform(&seed) * 100, uniform(&seed) * 20,
                                uniform(&seed) * 100, 1 + uniform(&seed) * 5);
    hits.count = 0;
    hits.tree = &t;
    f3d_tree_query(&t, probe, hit, &hits);
    qsort(hits.slots, hits.count, sizeof(uint32_t), by_value);
    uint32_t expected = 0;
    for (int i = 0; i < N; i++) {
      if (!f3d_box_overlap(boxes[i], probe)) continue;
      all &= expected < hits.count && hits.slots[expected] == (uint32_t)i;
      expected++;
    }
    all &= expected == hits.count;
  }
  CHECK(all);
  f3d_tree_clear(&t);
}

static void test_world_tree(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  F3dBody bodies[50];
  for (int i = 0; i < 50; i++) {
    bodies[i] = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)(i % 10) * 3,
                                0, (f3d_real)(i / 10) * 3, 1);
    f3d_body_set_shape(w, bodies[i], F3D_SHAPE_SPHERE, F3D_R(0.5), 0, 0);
  }
  /* A point has no leaf. */
  const F3dBody point = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(w->tree.leaves == 50);
  CHECK(w->proxies[(uint32_t)point] == -1);
  CHECK(tree_valid(&w->tree));
  /* A box query, in slot order, the lowest slots first when the room is
   * short. */
  F3dBody out[8];
  CHECK(f3d_world_query_box(w, -1, -1, -1, F3D_R(3.5), 1, F3D_R(3.5), out, 8) == 4);
  CHECK(out[0] == bodies[0] && out[1] == bodies[1] && out[2] == bodies[10] &&
        out[3] == bodies[11]);
  CHECK(f3d_world_query_box(w, -1, -1, -1, 100, 1, 100, out, 3) == 50);
  CHECK(out[0] == bodies[0] && out[1] == bodies[1] && out[2] == bodies[2]);
  CHECK(f3d_world_query_box(w, 200, 0, 0, 201, 1, 1, out, 8) == 0);
  /* A body moving a few centimetres stays in its leaf; one leaving it
   * gets a new one, and one destroyed loses its own. */
  /* By its box, not its index: a leaf taken out and put back can land in
   * the node it left. */
  const F3dBox fat = w->tree.nodes[w->proxies[(uint32_t)bodies[5]]].box;
  f3d_body_set_velocity(w, bodies[5], F3D_R(0.6), 0, 0);
  /* Two steps: the leaves are brought up to date at a step's start, before
   * the body moves. */
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  const F3dBox same = w->tree.nodes[w->proxies[(uint32_t)bodies[5]]].box;
  CHECK(memcmp(&fat, &same, sizeof fat) == 0);
  for (int i = 0; i < 30; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  f3d_body_destroy(w, bodies[7]);
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(w->tree.leaves == 49);
  CHECK(tree_valid(&w->tree));
  /* Restored, the tree is built again, and the world steps on as the one
   * it came from. */
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, snap, size);
  F3dWorld *v = f3d_world_create();
  f3d_world_restore(v, snap, size);
  CHECK(v->tree.leaves == 0);
  for (int i = 0; i < 60; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_world_step(v, F3D_R(1.0 / 60.0));
  }
  CHECK(v->tree.leaves == 49);
  uint8_t *a = (uint8_t *)malloc(size), *b = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_size(v) == size);
  f3d_world_snapshot_write(w, a, size);
  f3d_world_snapshot_write(v, b, size);
  CHECK(memcmp(a, b, size) == 0);
  free(snap);
  free(a);
  free(b);
  f3d_world_destroy(w);
  f3d_world_destroy(v);
}

static void test_moving_the_ground_wakes_what_sleeps_on_it(void) {
  /* A crate asleep on a fixed plank: the plank lifted away by hand, the
   * crate wakes and falls. */
  F3dWorld *w = f3d_world_create();
  const F3dBody plank = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, plank, F3D_SHAPE_BOX, 2, F3D_R(0.5), 2);
  const F3dBody crate = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.5), 0, 1);
  f3d_body_set_shape(w, crate, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5));
  for (int i = 0; i < 120; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(f3d_body_is_asleep(w, crate));
  f3d_body_set_position(w, plank, 10, F3D_R(-0.5), 0);
  for (int i = 0; i < 30; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, crate));
  f3d_real p[3];
  f3d_body_get_position(w, crate, p);
  CHECK(p[1] < 0);
  f3d_world_destroy(w);
}

static void test_many_bodies_few_pairs(void) {
  /* Four thousand balls a metre apart in a grid, none touching: the step
   * finds no pairs and makes no contacts — the tree, not a sweep that
   * meets everything in a column. */
  enum { N = 4000 };
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  for (int i = 0; i < N; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)(i % 20),
                                      (f3d_real)((i / 20) % 10),
                                      (f3d_real)(i / 200), 1);
    f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.3), 0, 0);
  }
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(w->s.manifold_count == 0);
  CHECK(w->tree.leaves == N);
  CHECK(tree_valid(&w->tree));
  f3d_world_destroy(w);
}

int main(void) {
  test_balanced_and_valid();
  test_queries_find_every_box();
  test_world_tree();
  test_moving_the_ground_wakes_what_sleeps_on_it();
  test_many_bodies_few_pairs();
  return finish();
}
