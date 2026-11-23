#!/usr/bin/env bash
# M4 stage: golden-vector smoke of the ACCEPTED GF16 dot4 cubin.
# Owner-ordered gate chain: hash gate BEFORE launch; lane-scratch writes
# only; no foreign processes touched.
# Device selection (MEASURED, device_probe.log): the CUDA driver inside this
# WSL2 container exposes exactly ONE logical device (cuDeviceGetCount == 1),
# which IS the free physical RTX 3070 Laptop (physical nvidia-smi index 1,
# 15275 MiB free of 16384 MiB). Therefore the CUDA ordinal to use is 0;
# ordinal 1 fails with CUDA_ERROR_INVALID_DEVICE (101) and launches nothing.
# The physical GPU 0 (busy, ~14.5 GiB used) is not exposed to CUDA here and
# is never touched by this script.
set -u
LANE=/home/t27ssh/t27os/lanes/gf16-dot4-ptx-20261123T071500Z
M4="$LANE/m4_smoke"
EXPECTED_CUBIN_SHA=35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc

cd "$M4" || exit 9

echo "=== 0. context ==="
date -u +%Y-%m-%dT%H:%M:%SZ
uname -a

echo
echo "=== 1. hash gate BEFORE launch (owner step 4) ==="
sha256sum gf16_dot4_accepted.cubin
if command -v sha256sum >/dev/null; then
  GOT=$(sha256sum gf16_dot4_accepted.cubin | cut -d' ' -f1)
  if [ "$GOT" = "$EXPECTED_CUBIN_SHA" ]; then
    echo "HASH_GATE: PASS ($GOT)"
  else
    echo "HASH_GATE: FAIL got=$GOT want=$EXPECTED_CUBIN_SHA"
    echo "REFUSING TO LAUNCH"
    exit 10
  fi
fi

echo
echo "=== 2. free-GPU inventory (physical index 1 == CUDA ordinal 0) ==="
/usr/lib/wsl/lib/nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv 2>&1
FREE1=$(/usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i 1 2>/dev/null || echo 0)
echo "gpu1_free_mib=$FREE1"
if [ "${FREE1:-0}" -lt 64 ]; then
  echo "GPU_GATE: FAIL (free=${FREE1}MiB < 64MiB); REFUSING TO LAUNCH; preserve state"
  exit 11
fi
echo "GPU_GATE: PASS"

echo
echo "=== 3. build runner (driver API only) ==="
if gcc -O2 -I/usr/local/cuda/include cuda_smoke.c -o cuda_smoke -L/usr/lib/wsl/lib -lcuda 2> gcc_build.log; then
  echo "BUILD: gcc ok"
else
  echo "gcc fallback failed; trying nvcc"
  cat gcc_build.log
  nvcc -O2 -arch=sm_86 cuda_smoke.c -o cuda_smoke -lcuda 2> nvcc_build.log || { echo "BUILD: FAIL"; cat nvcc_build.log; exit 12; }
  echo "BUILD: nvcc ok"
fi

echo
echo "=== 4. golden smoke: n=8 adopted groups, grid ceil(n/256)=1, block 256x1x1 ==="
./cuda_smoke gf16_dot4_accepted.cubin gf16_dot4_a.bin gf16_dot4_b.bin 0 8 smoke
RUN_RC=$?
echo "runner_exit=$RUN_RC"

echo
echo "=== 5. post-run GPU state ==="
/usr/lib/wsl/lib/nvidia-smi --query-gpu=index,memory.used,utilization.gpu --format=csv 2>&1

echo
echo "=== 6. output completeness ==="
if [ -f smoke_c.bin ]; then
  echo "smoke_c.bin bytes: $(stat -c %s smoke_c.bin 2>/dev/null || stat -f %z smoke_c.bin)"
  xxd -e -g4 smoke_c.bin
else
  echo "smoke_c.bin MISSING"
fi
echo "M4_SMOKE_DONE rc=$RUN_RC"
