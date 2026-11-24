/* M4 probe: enumerate CUDA devices visible inside WSL2 (driver API only). */
#include <cuda.h>
#include <stdio.h>

int main(void)
{
    CUresult r = cuInit(0);
    if (r != CUDA_SUCCESS) { printf("cuInit -> %d\n", (int)r); return 1; }
    int count = -1;
    if (cuDeviceGetCount(&count) != CUDA_SUCCESS) { printf("cuDeviceGetCount failed\n"); return 1; }
    printf("device_count=%d\n", count);
    for (int i = 0; i < count; i++) {
        CUdevice d;
        char name[128] = "?";
        size_t total = 0, free_b = 0;
        if (cuDeviceGet(&d, i) != CUDA_SUCCESS) { printf("dev %d: cuDeviceGet failed\n", i); continue; }
        cuDeviceGetName(name, sizeof(name), d);
        CUcontext ctx;
        if (cuCtxCreate_v2(&ctx, 0, d) == CUDA_SUCCESS) {
            cuMemGetInfo_v2(&free_b, &total);
            cuCtxDestroy_v2(ctx);
        }
        printf("dev %d: %s free=%.0f MiB total=%.0f MiB\n", i, name,
               (double)free_b / 1048576.0, (double)total / 1048576.0);
    }
    return 0;
}
