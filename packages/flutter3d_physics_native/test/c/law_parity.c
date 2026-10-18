/*
 * The C side of test/law_parity_test.dart: runs the programs a corpus file
 * holds through the core's interpreter, and writes every answer's bits, so
 * the Dart test holds them to the Dart interpreter's. Built by that test
 * twice, with f3d_real a float and with it a double.
 *
 * The corpus, little-endian:
 *   u32 programs, then for each: u32 kind (0 a program run on inputs, 1 a
 *   law set on a body), u32 length, the bytecode, u32 runs, then for each
 *   run: kind 0, the inputs' numbers as f64 (as many as the program reads);
 *   kind 1, one f64, the body's temperature.
 * Writes one line a run: the answer's numbers as 16 hex digits each, or
 * "refused" for a program the core would not load or a law it would not
 * set.
 */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "f3d_physics.h"

static uint32_t u32(FILE *f) {
  unsigned char b[4];
  if (fread(b, 1, 4, f) != 4) exit(2);
  return (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}

static double f64(FILE *f) {
  unsigned char b[8];
  if (fread(b, 1, 8, f) != 8) exit(2);
  uint64_t u = 0;
  for (int i = 7; i >= 0; i--) u = (u << 8) | b[i];
  double d;
  memcpy(&d, &u, 8);
  return d;
}

static void hex(double d) {
  uint64_t u;
  memcpy(&u, &d, 8);
  printf("%016" PRIx64, u);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  FILE *f = fopen(argv[1], "rb");
  if (f == NULL) return 2;
  const uint32_t programs = u32(f);
  for (uint32_t p = 0; p < programs; p++) {
    const uint32_t kind = u32(f);
    const uint32_t length = u32(f);
    uint8_t *bytes = (uint8_t *)malloc(length > 0 ? length : 1);
    if (bytes == NULL || fread(bytes, 1, length, f) != length) return 2;
    const uint32_t runs = u32(f);
    if (kind == 0) {
      F3dProgram *program = f3d_program_load(bytes, length);
      uint32_t lanes = 0;
      for (uint32_t i = 0; i < f3d_program_input_count(program); i++) {
        lanes += f3d_program_input_width(program, i);
      }
      double inputs[64], out[4];
      for (uint32_t r = 0; r < runs; r++) {
        for (uint32_t i = 0; i < lanes; i++) inputs[i] = f64(f);
        const uint32_t wrote = f3d_program_run(program, inputs, out);
        if (program == NULL) printf("refused");
        for (uint32_t i = 0; i < wrote; i++) {
          if (i > 0) printf(" ");
          hex(out[i]);
        }
        printf("\n");
      }
      f3d_program_free(program);
    } else {
      for (uint32_t r = 0; r < runs; r++) {
        const double temperature = f64(f);
        F3dWorld *w = f3d_world_create();
        const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
        F3dMaterial m;
        f3d_material_preset(F3D_MATERIAL_STEEL, &m);
        f3d_body_set_material(w, b, &m);
        f3d_world_set_gravity(w, 0, 0, 0);
        f3d_body_set_temperature(w, b, (f3d_real)temperature);
        if (!f3d_body_set_law(w, b, F3D_LAW_SPECIFIC_HEAT, bytes, length)) {
          printf("refused\n");
        } else {
          f3d_world_step(w, (f3d_real)(1.0 / 60.0));
          f3d_body_get_material(w, b, &m);
          hex((double)m.specific_heat);
          printf("\n");
        }
        f3d_world_destroy(w);
      }
    }
    free(bytes);
  }
  fclose(f);
  return 0;
}
