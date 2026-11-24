/* GF16 dot4 golden-vector smoke on GPU 1 (win11-3070, WSL2, CUDA 12.4).
 * M4 stage 1 of LAMB_LABS_GF16_GPU_CORRECTNESS: launch the ACCEPTED cubin
 * over the M1-verified ABI, synchronize, read back the full output, dump it
 * as machine-readable hex. CPU-only oracle/comparator lives in .t27 (M2/M3);
 * this runner does NOT compare, does NOT judge correctness, and records raw
 * evidence only.
 *
 * ABI (evidence/vertical_stack/HOST_ABI.md, verified):
 *   kernel  gf16_dot4
 *   params  (p_a u64, p_b u64, p_c u64, p_n u32)
 *   grid_x = (n + 255) / 256, block 256x1x1, smem 0, stream 0
 *   A/B     8 bytes per group (two LE u32 lane words), C 4 bytes per group
 *
 * Every CUDA call is checked; any non-CUDA_SUCCESS aborts with a nonzero
 * exit code and prints the failed call name.
 */
#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *g_last_call = "none";

#define CUDA_CHECK(expr)                                                   \
    do {                                                                   \
        CUresult _r = (expr);                                              \
        g_last_call = #expr;                                               \
        if (_r != CUDA_SUCCESS) {                                          \
            const char *s = NULL;                                          \
            cuGetErrorString(_r, &s);                                      \
            fprintf(stderr, "CUDA_ERR %s -> %d (%s)\n", g_last_call,       \
                    (int)_r, s ? s : "?");                                 \
            return 1;                                                      \
        }                                                                  \
    } while (0)

static unsigned char *read_bin(const char *path, size_t expect, const char *what)
{
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "CUDA_ERR open_%s -> cannot open %s\n", what, path); return NULL; }
    unsigned char *buf = (unsigned char *)malloc(expect);
    size_t got = fread(buf, 1, expect, f);
    fclose(f);
    if (got != expect) {
        fprintf(stderr, "CUDA_ERR read_%s -> got %zu want %zu\n", what, got, expect);
        free(buf);
        return NULL;
    }
    return buf;
}

static unsigned char *read_file_all(const char *path, size_t *len_out, const char *what)
{
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "CUDA_ERR open_%s -> cannot open %s\n", what, path); return NULL; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fprintf(stderr, "CUDA_ERR size_%s -> %ld\n", what, sz); fclose(f); return NULL; }
    unsigned char *buf = (unsigned char *)malloc((size_t)sz);
    size_t got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if ((long)got != sz) { fprintf(stderr, "CUDA_ERR read_%s\n", what); free(buf); return NULL; }
    *len_out = (size_t)sz;
    return buf;
}

int main(int argc, char **argv)
{
    if (argc != 7) {
        fprintf(stderr, "usage: %s <cubin> <a.bin> <b.bin> <gpu_ordinal> <n_groups> <out_prefix>\n", argv[0]);
        return 2;
    }
    const char *cubin_path = argv[1];
    const char *a_path = argv[2];
    const char *b_path = argv[3];
    int dev_ordinal = atoi(argv[4]);
    unsigned n_groups = (unsigned)atoi(argv[5]);
    const char *out_prefix = argv[6];
    const size_t A_BYTES = n_groups * 8;
    const size_t B_BYTES = n_groups * 8;
    const size_t C_BYTES = n_groups * 4;

    unsigned char *cubin = NULL, *ha = NULL, *hb = NULL;
    size_t cubin_len = 0;
    CUdevice dev;
    CUcontext ctx = NULL;
    CUmodule mod = NULL;
    CUfunction fn = NULL;
    CUdeviceptr da = 0, db = 0, dc = 0;
    unsigned char *hc = (unsigned char *)malloc(C_BYTES);
    int rc = 1;

    cubin = read_file_all(cubin_path, &cubin_len, "cubin");
    ha = read_bin(a_path, A_BYTES, "a");
    hb = read_bin(b_path, B_BYTES, "b");
    if (!cubin || !ha || !hb || !hc) goto cleanup;

    CUDA_CHECK(cuInit(0));
    CUDA_CHECK(cuDeviceGet(&dev, dev_ordinal));
    CUDA_CHECK(cuCtxCreate_v2(&ctx, 0, dev));
    CUDA_CHECK(cuModuleLoadData(&mod, cubin));
    CUDA_CHECK(cuModuleGetFunction(&fn, mod, "gf16_dot4"));
    CUDA_CHECK(cuMemAlloc_v2(&da, A_BYTES));
    CUDA_CHECK(cuMemAlloc_v2(&db, B_BYTES));
    CUDA_CHECK(cuMemAlloc_v2(&dc, C_BYTES));
    CUDA_CHECK(cuMemcpyHtoD_v2(da, ha, A_BYTES));
    CUDA_CHECK(cuMemcpyHtoD_v2(db, hb, B_BYTES));
    {
        unsigned nn = n_groups;
        /* ABI: gid = ctaid.x*256 + tid.x must cover p_n; grid may exceed p_n. Derived from n_groups = p_n. */
        unsigned gx = (n_groups + 255u) / 256u;
        void *args[4] = { &da, &db, &dc, &nn };
        CUDA_CHECK(cuLaunchKernel(fn, gx, 1, 1, 256, 1, 1, 0, NULL, args, NULL));
    }
    CUDA_CHECK(cuCtxSynchronize());
    CUDA_CHECK(cuMemcpyDtoH_v2(hc, dc, C_BYTES));

    {
        char p[512];
        FILE *o;
        unsigned g;
        snprintf(p, sizeof(p), "%s_c.bin", out_prefix);
        o = fopen(p, "wb");
        if (!o) { fprintf(stderr, "CUDA_ERR write_out\n"); goto cleanup; }
        fwrite(hc, 1, C_BYTES, o);
        fclose(o);
    }
    printf("GPU_RUN_OK cubin_bytes=%zu n=%u dev=%d\n", cubin_len, n_groups, dev_ordinal);
    {
        unsigned g;
        for (g = 0; g < n_groups; g++) {
            unsigned char *p = hc + g * 4;
            unsigned w = (unsigned)p[0] | ((unsigned)p[1] << 8)
                       | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
            printf("C%u:%08X\n", g, w);
        }
    }
    rc = 0;

cleanup:
    if (da) cuMemFree_v2(da);
    if (db) cuMemFree_v2(db);
    if (dc) cuMemFree_v2(dc);
    if (mod) cuModuleUnload(mod);
    if (ctx) cuCtxDestroy_v2(ctx);
    free(cubin); free(ha); free(hb); free(hc);
    return rc;
}
