// Each width of the native pair loops (`src/pbf_lanes.h`) held to the
// scalar loop, on whatever processor runs it, and timed: for CI's x86-64,
// where the AVX2 and AVX-512 widths are real, which no arm64 machine can
// say. Built and run by the `native-lanes` job:
//
//   cc -O3 -fno-math-errno -Isrc src/pbf_kernels.c test/native/lanes_check.c -lm
//
// Exits 1 when a width differs from the scalar loop by more than a part in
// 10¹² of the largest value, which is summing in another order and nothing
// else.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
int32_t f3d_pbf_lanes(void); int32_t f3d_pbf_set_lanes(int32_t);
int32_t f3d_pbf_neighbours(const double*, int32_t, double, int32_t*, int32_t*, int32_t, int64_t*);
void f3d_pbf_densities(const double*, const int32_t*, const int32_t*, int32_t, const double*, double*);
void f3d_pbf_normals(const double*, const int32_t*, const int32_t*, int32_t, const double*, const double*, double*);
void f3d_pbf_forces(const double*, const int32_t*, const int32_t*, int32_t, const double*, const double*, const double*, const double*, const double*, double*, double);
void f3d_pbf_lambdas(const double*, const int32_t*, const int32_t*, int32_t, const double*, double*);
void f3d_pbf_deltas(const double*, const int32_t*, const int32_t*, int32_t, const double*, const double*, double*);
void f3d_pbf_viscosity(const double*, const double*, const int32_t*, const int32_t*, int32_t, const double*, double, double*);
#define N 2000
static double x[3*N], v[3*N], k[12], bef[3*N], aft[3*N];
static int32_t st[N+1], lst[N*200]; static int64_t scr[5*N];
typedef struct { double d[N], n[3*N], f[3*N], l[N], dl[3*N], vs[3*N]; } out_t;
static out_t o[9];
static void run(out_t* r) {
  f3d_pbf_densities(x, st, lst, N, k, r->d);
  f3d_pbf_normals(x, st, lst, N, k, r->d, r->n);
  for (int i=0;i<3*N;i++) r->f[i]=v[i];
  f3d_pbf_forces(x, st, lst, N, k, r->d, r->n, bef, aft, r->f, 1e-3);
  f3d_pbf_lambdas(x, st, lst, N, k, r->l);
  f3d_pbf_deltas(x, st, lst, N, k, r->l, r->dl);
  f3d_pbf_viscosity(x, v, st, lst, N, k, 0.1, r->vs);
}
static double rel(const double* a, const double* b, int n) {
  double m=0, s=0; for (int i=0;i<n;i++){ double e=fabs(a[i]-b[i]); if(e>m)m=e; if(fabs(b[i])>s)s=fabs(b[i]); } return s>0? m/s : m;
}
int main(void) {
  int failed = 0;
  srand(7); const double sp=0.001, h=2*sp;
  // A jittered block, with a few particles on top of each other.
  for (int i=0;i<N;i++){ int a=i%13,b=(i/13)%13,c=i/169; x[3*i]=a*sp*0.9+((rand()%1000)-500)*1e-7; x[3*i+1]=b*sp*0.9+((rand()%1000)-500)*1e-7; x[3*i+2]=c*sp*0.9+((rand()%1000)-500)*1e-7; for(int d=0;d<3;d++){v[3*i+d]=((rand()%1000)-500)*1e-4; bef[3*i+d]=-9.81*(d==1); aft[3*i+d]=0;} }
  x[3]=x[0]; x[4]=x[1]; x[5]=x[2];
  double m=1000*sp*sp*sp, H6=pow(h,6);
  k[0]=h;k[1]=h*h;k[2]=1000;k[3]=m;k[4]=m/1000;k[5]=0.072;k[6]=1e-4;k[7]=315/(64*M_PI*pow(h,9));k[8]=-45/(M_PI*H6);k[9]=32/(M_PI*pow(h,9));k[10]=H6;k[11]=k[7]*pow(h*h-0.09*h*h,3);
  int32_t cnt=f3d_pbf_neighbours(x,N,h,st,lst,N*200,scr);
  printf("default lanes %d, %d pairs (%.1f a particle)\n", f3d_pbf_lanes(), cnt, (double)cnt/N);
  int widths[4]={1,2,4,8};
  for (int w=0;w<4;w++){
    int got=f3d_pbf_set_lanes(widths[w]);
    if (got!=widths[w]) { printf("lanes %d: not on this processor\n", widths[w]); continue; }
    run(&o[widths[w]]);
    clock_t t=clock(); for(int r=0;r<50;r++) run(&o[widths[w]]); double ms=(double)(clock()-t)*1000/CLOCKS_PER_SEC/50;
    if (widths[w]==1) { printf("lanes 1: %.3f ms\n", ms); continue; }
    out_t* a=&o[widths[w]]; out_t* b=&o[1];
    double worst = rel(a->d,b->d,N);
    double e[5] = {rel(a->n,b->n,3*N), rel(a->f,b->f,3*N), rel(a->l,b->l,N), rel(a->dl,b->dl,3*N), rel(a->vs,b->vs,3*N)};
    for (int q=0;q<5;q++) if (e[q]>worst) worst=e[q];
    if (worst > 1e-12) failed = 1;
    printf("lanes %d: %.3f ms; against scalar: density %.1e normals %.1e forces %.1e lambda %.1e delta %.1e viscosity %.1e\n", widths[w], ms,
      rel(a->d,b->d,N), rel(a->n,b->n,3*N), rel(a->f,b->f,3*N), rel(a->l,b->l,N), rel(a->dl,b->dl,3*N), rel(a->vs,b->vs,3*N));
  }
  if (failed) printf("a width differs from the scalar loop\n");
  return failed;
}
