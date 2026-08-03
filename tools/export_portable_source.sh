#!/usr/bin/env bash
set -euo pipefail

WORK="$PWD/export-work"
OUT="$PWD/export-output"
ROOT="$OUT/S8Plus_ALice_FULL_SOURCE_PORTABLE"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

cat configs/v55_chunks/part{00..11}.b64 > "$WORK/V55_CONFIG.b64"
echo 'dacf46588d375e8b3e1943b950260f8c40bacb10f79db143bf0bd4b3488ff2c2  export-work/V55_CONFIG.b64' | sha256sum -c -
base64 -d "$WORK/V55_CONFIG.b64" > "$WORK/V55_CONFIG.gz"
echo '7ca6bc454a72d88477ac94b6baa1185c193339c72d64e3c401a0c94a958b45cf  export-work/V55_CONFIG.gz' | sha256sum -c -
gzip -dc "$WORK/V55_CONFIG.gz" > "$WORK/V55_BASELINE.config"
echo '25534172654cc2ef053bc2b2580dc8e0d647a921624ad7bdea54024f07672c07  export-work/V55_BASELINE.config' | sha256sum -c -

git clone --depth 1 --single-branch --branch sep-16.1 https://github.com/boloaimer/exynos-8895.git "$WORK/kernel"
test "$(git -C "$WORK/kernel" rev-parse HEAD)" = 'dcdaf6878e7f9497e1d90e25980decfa5d684f74'
git -C "$WORK/kernel" config user.name alice-export
git -C "$WORK/kernel" config user.email alice-export@users.noreply.github.com
git -C "$WORK/kernel" fetch --depth 2 origin f1c5b91a788f38214f04ab22563d0bceac7c2c17
git -C "$WORK/kernel" revert --no-edit f1c5b91a788f38214f04ab22563d0bceac7c2c17
git -C "$WORK/kernel" rev-parse HEAD > "$WORK/KSU_HOOK_COMPAT_COMMIT.txt"

git -C "$WORK/kernel" remote add susfs-port https://github.com/fnr1r/android_kernel_samsung_universal8895.git
git -C "$WORK/kernel" fetch --depth 2 susfs-port 7bc44731088e0e004345fcd71eac0fbf877849c1
set +e
git -C "$WORK/kernel" cherry-pick 7bc44731088e0e004345fcd71eac0fbf877849c1 > "$WORK/SUSFS_PORT_LOG.txt" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cd "$WORK/kernel"
  git rm -f .gitmodules
  git checkout --ours fs/devpts/inode.c
  git add fs/devpts/inode.c
  python3 -c "from pathlib import Path; p=Path('kernel/sys.c'); s=p.read_text(); a=s.index('<<<<<<< HEAD'); b=s.index('=======',a); m='>>>>>>> 7bc447310 (feat: add susfs4ksu)'; c=s.index(m,b); ours=s[a+len('<<<<<<< HEAD'):b]; theirs=s[b+len('======='):c]; p.write_text(s[:a]+ours+theirs+s[c+len(m):])"
  git add kernel/sys.c
  test -z "$(git diff --name-only --diff-filter=U)"
  GIT_EDITOR=true git cherry-pick --continue >> "$WORK/SUSFS_PORT_LOG.txt" 2>&1
  cd - >/dev/null
fi

rm -rf "$WORK/kernel/susfs4ksu"
git clone --no-checkout https://gitlab.com/simonpunk/susfs4ksu.git "$WORK/kernel/susfs4ksu"
git -C "$WORK/kernel/susfs4ksu" fetch --depth 1 origin 2404aebaeee041c8e0e06ca4636dc87b984c2428
git -C "$WORK/kernel/susfs4ksu" checkout --detach FETCH_HEAD
test "$(git -C "$WORK/kernel/susfs4ksu" rev-parse HEAD)" = '2404aebaeee041c8e0e06ca4636dc87b984c2428'

sed -i '/fetch-latest-kernelsu\.sh/d' "$WORK/kernel/scripts/Kbuild.include"
! grep -q 'fetch-latest-kernelsu.sh' "$WORK/kernel/scripts/Kbuild.include"
git clone --no-checkout https://github.com/fnr1r/KernelSU.git "$WORK/ksu"
git -C "$WORK/ksu" fetch --depth 1 origin ee03fa5bdd1eece21b15581b3bccd06c9d30afc1
git -C "$WORK/ksu" checkout --detach FETCH_HEAD
test "$(git -C "$WORK/ksu" rev-parse HEAD)" = 'ee03fa5bdd1eece21b15581b3bccd06c9d30afc1'
rm -rf "$WORK/kernel/drivers/kernelsu"
mkdir -p "$WORK/kernel/drivers/kernelsu"
cp -a "$WORK/ksu/kernel/." "$WORK/kernel/drivers/kernelsu/"
python3 tools/backport_trace_hex_str.py "$WORK/kernel"

mkdir -p "$WORK/kernel/out"
cp "$WORK/V55_BASELINE.config" "$WORK/kernel/out/.config"
export ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu-
"$WORK/kernel/scripts/config" --file "$WORK/kernel/out/.config" -e OVERLAY_FS -e KSU -e KSU_SUSFS
"$WORK/kernel/scripts/config" --file "$WORK/kernel/out/.config" -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT
"$WORK/kernel/scripts/config" --file "$WORK/kernel/out/.config" -e KSU_SUSFS_SUS_OVERLAYFS -e KSU_SUSFS_TRY_UMOUNT -e KSU_SUSFS_SPOOF_UNAME
"$WORK/kernel/scripts/config" --file "$WORK/kernel/out/.config" -e KSU_SUSFS_ENABLE_LOG -d KSU_SUSFS_SUS_SU
make -C "$WORK/kernel" O=out olddefconfig
cp "$WORK/kernel/out/.config" "$WORK/kernel/arch/arm64/configs/alice_dream2lte_susfs_defconfig"
grep -q '^CONFIG_KSU_SUSFS=y' "$WORK/kernel/out/.config"
grep -q '^CONFIG_KSU_SUSFS_SUS_PATH=y' "$WORK/kernel/out/.config"
grep -q '^# CONFIG_KSU_SUSFS_SUS_SU is not set' "$WORK/kernel/out/.config"

mkdir -p "$ROOT/.github/workflows" "$ROOT/scripts" "$ROOT/manifests" "$ROOT/evidence" "$ROOT/repack"
rsync -a --delete --exclude='.git' --exclude='out' "$WORK/kernel/" "$ROOT/kernel/"
rm -rf "$ROOT/kernel/susfs4ksu/.git" "$ROOT/kernel/drivers/kernelsu/.git"
cp tools/backport_trace_hex_str.py "$ROOT/scripts/"
cp "$WORK/V55_BASELINE.config" "$ROOT/manifests/"
cp "$WORK/KSU_HOOK_COMPAT_COMMIT.txt" "$WORK/SUSFS_PORT_LOG.txt" "$ROOT/evidence/"

cat > "$ROOT/SOURCE_MANIFEST.json" <<'JSON'
{
  "device": "Samsung Galaxy S8 Plus dream2lte",
  "kernel": "Linux 4.4.302",
  "base_repository": "boloaimer/exynos-8895",
  "base_branch": "sep-16.1",
  "base_commit": "dcdaf6878e7f9497e1d90e25980decfa5d684f74",
  "susfs_port_commit": "7bc44731088e0e004345fcd71eac0fbf877849c1",
  "susfs_source_commit": "2404aebaeee041c8e0e06ca4636dc87b984c2428",
  "kernelsu_commit": "ee03fa5bdd1eece21b15581b3bccd06c9d30afc1",
  "defconfig": "alice_dream2lte_susfs_defconfig",
  "sus_su": false,
  "profile": "full SUSFS except SUS_SU",
  "reference_successful_run": 110
}
JSON

cat > "$ROOT/scripts/build.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-none-linux-gnu-}"
make -C "$ROOT/kernel" O="$ROOT/out" alice_dream2lte_susfs_defconfig
make -C "$ROOT/kernel" O="$ROOT/out" -j"${JOBS:-2}" Image
test -s "$ROOT/out/arch/arm64/boot/Image"
sha256sum "$ROOT/out/arch/arm64/boot/Image"
SH
chmod +x "$ROOT/scripts/build.sh"

cat > "$ROOT/.github/workflows/build-portable-kernel.yml" <<'YAML'
name: Build portable S8 Plus kernel
on:
  workflow_dispatch:
  push:
    branches: [main, master]
    paths:
      - 'kernel/**'
      - 'scripts/**'
      - '.github/workflows/build-portable-kernel.yml'
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-22.04
    timeout-minutes: 150
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y bc bison build-essential cpio flex git libelf-dev libssl-dev lz4 python3 rsync xz-utils zip
      - name: Install pinned Arm GNU Toolchain 13.3.Rel1
        run: |
          curl -L --retry 5 --retry-delay 3 -o arm-gnu.tar.xz https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
          tar -xf arm-gnu.tar.xz
          GCC_PATH="$(find "$PWD" -type f -name aarch64-none-linux-gnu-gcc -print -quit)"
          test -n "$GCC_PATH"
          echo "$(dirname "$GCC_PATH")" >> "$GITHUB_PATH"
          "$GCC_PATH" --version
      - name: Verify locked profile
        run: |
          grep -q '^CONFIG_KSU_SUSFS=y' kernel/arch/arm64/configs/alice_dream2lte_susfs_defconfig
          grep -q '^CONFIG_KSU_SUSFS_SUS_PATH=y' kernel/arch/arm64/configs/alice_dream2lte_susfs_defconfig
          grep -q '^# CONFIG_KSU_SUSFS_SUS_SU is not set' kernel/arch/arm64/configs/alice_dream2lte_susfs_defconfig
          ! grep -q 'fetch-latest-kernelsu.sh' kernel/scripts/Kbuild.include
      - name: Build
        run: JOBS=2 scripts/build.sh | tee BUILD_LOG.txt
      - name: Verify output
        run: |
          test -s out/arch/arm64/boot/Image
          test -s out/vmlinux
          test -s out/System.map
          test -s out/fs/susfs.o
          test -s out/drivers/kernelsu/kernelsu.o
          grep -iq susfs out/System.map
          cp out/arch/arm64/boot/Image Image-dream2lte-susfs
          cp out/System.map System.map-dream2lte-susfs
          sha256sum Image-dream2lte-susfs System.map-dream2lte-susfs kernel/arch/arm64/configs/alice_dream2lte_susfs_defconfig > SHA256SUMS.txt
      - uses: actions/upload-artifact@v4
        with:
          name: S8Plus-portable-kernel-build
          path: |
            Image-dream2lte-susfs
            System.map-dream2lte-susfs
            SHA256SUMS.txt
            BUILD_LOG.txt
          retention-days: 14
YAML

cat > "$ROOT/README_VI.md" <<'MD'
# S8Plus ALice – Full portable source

Snapshot source hoàn chỉnh để tiếp tục build kernel Samsung Galaxy S8 Plus `dream2lte`.

## Đã tích hợp

- Linux 4.4.302, source V55-compatible.
- KernelSU fork đã pin.
- SUSFS 1.4.2 và các hook đã port vào source.
- Bật toàn bộ profile SUSFS yêu cầu, trừ `SUS_SU`.
- Defconfig: `kernel/arch/arm64/configs/alice_dream2lte_susfs_defconfig`.
- Đã loại cơ chế tự tải KernelSU mới trong lúc build.

## Đưa lên GitHub khác

```bash
git init
git add .
git commit -m "Import S8Plus ALice full source"
git branch -M main
git remote add origin https://github.com/USERNAME/REPOSITORY.git
git push -u origin main
```

Sau đó vào **Actions → Build portable S8 Plus kernel → Run workflow**.
Workflow dùng source ngay trong repo mới, không phụ thuộc `hyo4402/gpttest`.

## Build thủ công

Cài Arm GNU Toolchain 13.3.Rel1 và đặt `aarch64-none-linux-gnu-gcc` trong `PATH`:

```bash
JOBS=2 scripts/build.sh
```

Output: `out/arch/arm64/boot/Image`.

## Lưu ý

Đây là snapshot source không chứa lịch sử Git của repo nguồn. Boot/runtime vẫn phải kiểm tra trên máy `dream2lte` thật. Không bật `SUS_SU` trên integration manual-hook này.
MD

cat > "$ROOT/.gitignore" <<'EOF'
/out/
*.o
*.cmd
*.tmp
*.log
arm-gnu*
EOF

find "$ROOT" -type f -print0 | sort -z | xargs -0 sha256sum > "$ROOT/SHA256SUMS_ALL_FILES.txt"
(cd "$OUT" && zip -qry -y S8Plus_ALice_FULL_SOURCE_PORTABLE_20260803.zip S8Plus_ALice_FULL_SOURCE_PORTABLE)
sha256sum "$OUT/S8Plus_ALice_FULL_SOURCE_PORTABLE_20260803.zip" > "$OUT/SOURCE_ZIP_SHA256.txt"
unzip -t "$OUT/S8Plus_ALice_FULL_SOURCE_PORTABLE_20260803.zip" | tail -n 2
