#!/bin/sh
# Portable POSIX sh — runs under dash (Debian /bin/sh) and busybox ash
# (Alpine /bin/sh) without a bash dependency.
#
# Build the phpv8/v8js PHP extension against an existing V8 install.
#
# Inputs (env vars):
#   V8JS_REF             git ref to check out from phpv8/v8js (commit pinned
#                        for reproducibility).
#   V8_PREFIX            install prefix of V8. Pass an empty string (or "/usr")
#                        to skip --with-v8js and let configure auto-detect
#                        system-installed V8 (Alpine nodejs-dev case).
#   V8JS_CPPFLAGS        extra CPPFLAGS passed to configure. MUST match the
#                        flags V8 itself was compiled with — chiefly
#                        V8_COMPRESS_POINTERS / V8_ENABLE_SANDBOX. Wrong
#                        values produce a runtime "Embedder-vs-V8 build
#                        configuration mismatch" abort at first
#                        `new V8Js()`. Debian (depot_tools) → use both.
#                        Alpine (Node's V8) → leave empty.
#   V8JS_LDFLAGS_EXTRA   extra LDFLAGS appended after the defaults.
#   INI_DIR              php conf.d directory for the loader file.

# Plain `set -eu` — pipefail isn't portable to dash (Debian /bin/sh).
set -eu

: "${V8JS_REF:?V8JS_REF is required}"
V8_PREFIX="${V8_PREFIX:-}"
V8JS_CPPFLAGS="${V8JS_CPPFLAGS:-}"
V8JS_LDFLAGS_EXTRA="${V8JS_LDFLAGS_EXTRA:-}"
INI_DIR="${INI_DIR:-/usr/local/etc/php/conf.d}"

src_dir="$(mktemp -d)"
trap 'rm -rf "$src_dir"' EXIT

git clone --depth=50 https://github.com/phpv8/v8js.git "$src_dir"
cd "$src_dir"
git checkout "$V8JS_REF"

phpize

configure_args=""
ldflags="-lstdc++"
if [ -n "$V8_PREFIX" ] && [ "$V8_PREFIX" != "/usr" ]; then
    configure_args="--with-v8js=$V8_PREFIX"
    ldflags="-L${V8_PREFIX}/lib -Wl,-rpath,${V8_PREFIX}/lib $ldflags"
fi
if [ -n "$V8JS_LDFLAGS_EXTRA" ]; then
    ldflags="$ldflags $V8JS_LDFLAGS_EXTRA"
fi

# Quote everything; configure treats the args as VAR=VALUE settings.
if [ -n "$V8JS_CPPFLAGS" ]; then
    ./configure $configure_args \
        LDFLAGS="$ldflags" \
        CPPFLAGS="$V8JS_CPPFLAGS"
else
    ./configure $configure_args \
        LDFLAGS="$ldflags"
fi

make -j"$(nproc)"
make install

install -d "$INI_DIR"
cat > "${INI_DIR}/v8js.ini" <<EOF
extension=v8js.so
EOF

# Smoke test: load the extension to surface link errors at build time, not
# at first-customer-request time. Does NOT instantiate V8Js — that's the job
# of tests/smoke.php (which the Dockerfiles run as a separate RUN, so an
# ABI/pointer-compression mismatch fails fast with a clear context).
php -d extension=v8js.so -r 'if (!class_exists("V8Js")) { fwrite(STDERR, "v8js loaded but V8Js class missing\n"); exit(1); } echo "v8js OK, V8 " . V8Js::V8_VERSION . PHP_EOL;'
