#!/bin/sh
# Build V8 as shared libraries and install to ${V8_PREFIX}.
#
# Inputs (env vars):
#   V8_VERSION   git tag/ref to check out (e.g. 13.3.415)
#   V8_PREFIX    install prefix (e.g. /opt/v8)
#   TARGETARCH   Docker buildx-supplied target arch (amd64 or arm64). Falls
#                back to host arch via `uname -m` when unset.
#   V8_JOBS      ninja parallelism (defaults to nproc).
#
# Why we don't use `tools/dev/v8gen.py`:
#   * `v8gen.py arm64.release` selects an mb.py preset that builds a SIMULATOR
#     (target_cpu=x64, v8_target_cpu=arm64). That's intended for x64 Chromium
#     developers testing arm64 codegen — it's not a native arm64 build, and it
#     demands a Chromium sysroot (`debian_bullseye_amd64-sysroot`) that isn't
#     present in our slim Debian builder.
#   * Writing args.gn ourselves keeps the build hermetically described in
#     this repo and works identically on amd64 and arm64.
#
# Plain `set -eu` — pipefail isn't portable to dash (Debian /bin/sh) and the
# script has no pipelines whose intermediate exit codes we care about.
set -eu

: "${V8_VERSION:?V8_VERSION is required}"
: "${V8_PREFIX:=/opt/v8}"
: "${V8_JOBS:=$(nproc)}"

arch="${TARGETARCH:-$(uname -m)}"
case "$arch" in
    amd64|x86_64)   v8_cpu="x64" ;;
    arm64|aarch64)  v8_cpu="arm64" ;;
    *) echo "ERROR: unsupported arch '$arch'" >&2; exit 1 ;;
esac

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cd "$work_dir"
git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$work_dir/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0

fetch --no-history v8
cd v8
git fetch --depth=1 origin "refs/tags/${V8_VERSION}:refs/tags/${V8_VERSION}"
git checkout "tags/${V8_VERSION}"
gclient sync -D --no-history --shallow

out_dir="out.gn/${v8_cpu}.release"
mkdir -p "$out_dir"

# Write args.gn explicitly. Key choices:
#   * is_component_build = true   → ship a few small .so files, not one
#                                   monolithic libv8.a worth gigabytes
#   * use_custom_libcxx = false   → link against system libstdc++, matching
#                                   v8js's LDFLAGS expectation
#   * use_sysroot = false         → don't fetch Chromium's vendored Debian
#                                   sysroot; build against the host's libc
#                                   (this is what makes arm64 native work)
#   * is_clang = false            → use the host's gcc/g++ (trixie ships
#                                   gcc 14). Upstream only tests clang, so
#                                   this is the first thing to flip if a V8
#                                   bump stops compiling — see the README's
#                                   "Build hardening" section. Setting true
#                                   means apt-installing clang (Chromium
#                                   publishes no Linux arm64 build of its
#                                   own). This is also what caps V8 at 13.3
#                                   here: from 13.4 (string-hasher.cc) and
#                                   13.7 (simd.cc) V8's arm64 NEON code
#                                   relies on Clang's lax vector typing,
#                                   which GCC rejects.
#   * enable_rust = false +       → V8 13.x's own .gn sets enable_rust = true,
#     v8_enable_temporal_support      and its DEPS ships third_party/rust-toolchain
#     = false                         for Linux_x64 / Mac / Mac_arm64 / Win only
#                                   (the Linux entry is conditioned on
#                                   `host_os == "linux"`, with no arm64 build).
#                                   On linux/arm64 that means an x86-64 rustc +
#                                   bindgen land in the checkout and die under
#                                   qemu-x86_64 with "Could not open
#                                   /lib64/ld-linux-x86-64.so.2".
#                                   Since 13.9 the Temporal API is implemented
#                                   in Rust (//third_party/rust/temporal_capi),
#                                   so enable_rust = false alone trips an
#                                   assert in build/rust/rust_target.gni —
#                                   Temporal has to go too. Upstream added that
#                                   arg for the same reason ("some
#                                   architectures don't have Rust toolchains in
#                                   Chromium" — gni/v8.gni), and Temporal is
#                                   unreachable without --harmony-temporal at
#                                   runtime regardless. Nothing else in the
#                                   embedder libs needs Rust.
#   * treat_warnings_as_errors = false → tolerate toolchain drift (upstream
#                                        does the same in their CI)
#   * v8_enable_pointer_compression / v8_enable_sandbox = true → the
#                                   v8js Dockerfile sets matching CPPFLAGS
# v8_enable_temporal_support only exists from V8 13.9 on, and `gn gen` treats an
# undeclared arg in args.gn as a hard error — so emit it only when the checked
# out tree declares it. Keeps this script usable across 13.3…13.9+.
if grep -q "v8_enable_temporal_support" gni/v8.gni; then
    temporal_arg="v8_enable_temporal_support = false"
else
    temporal_arg="# v8_enable_temporal_support: not declared by this V8 version"
fi

cat > "${out_dir}/args.gn" <<EOF
is_debug = false
is_component_build = true
use_custom_libcxx = false
use_sysroot = false
is_clang = false
enable_rust = false
${temporal_arg}
treat_warnings_as_errors = false
symbol_level = 0
target_cpu = "${v8_cpu}"
v8_target_cpu = "${v8_cpu}"
v8_enable_pointer_compression = true
v8_enable_sandbox = true
EOF

# buildtools/linux64/gn is the gn binary depot_tools ships (an x86_64 ELF).
# Inside a linux/arm64 container running on Docker Desktop, binfmt_misc +
# qemu-user transparently emulate it. The emulation overhead is negligible
# compared to the multi-hour ninja phase.
buildtools/linux64/gn gen "$out_dir"

# Build only the embedder-facing targets, not V8's internal test binaries.
# Two arm64 test files (test-assembler-arm64.cc and test-code-stub-assembler.cc)
# use C++23 `42.15f16` literals and Clang-syntax inline asm, neither of which
# Debian trixie's GCC 14 accepts. They're compiled into the
# `cctest` executable, not libv8.so — skipping them is harmless for an
# embedder. Build time drops too: ~3000 objects instead of ~4000.
ninja -j "$V8_JOBS" -C "$out_dir" v8 v8_libplatform v8_libbase

install -d "${V8_PREFIX}/lib" "${V8_PREFIX}/include"
cp "${out_dir}"/lib*.so "${V8_PREFIX}/lib/"
cp "${out_dir}"/*_blob.bin "${V8_PREFIX}/lib/"
cp "${out_dir}/icudtl.dat" "${V8_PREFIX}/lib/"
cp -R include/. "${V8_PREFIX}/include/"

# RPATH so the runtime loader finds sibling V8 libs without LD_LIBRARY_PATH.
if command -v patchelf >/dev/null; then
    for so in "${V8_PREFIX}"/lib/*.so; do
        patchelf --set-rpath '$ORIGIN' "$so"
    done
fi

install -d "${V8_PREFIX}/lib/pkgconfig"
cat > "${V8_PREFIX}/lib/pkgconfig/v8.pc" <<EOF
prefix=${V8_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: v8
Description: Google V8 JavaScript engine
Version: ${V8_VERSION}
Libs: -L\${libdir} -lv8 -lv8_libplatform -lv8_libbase
Cflags: -I\${includedir} -DV8_COMPRESS_POINTERS -DV8_ENABLE_SANDBOX
EOF

echo "V8 ${V8_VERSION} (${v8_cpu}) installed to ${V8_PREFIX}"
