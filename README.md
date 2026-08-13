# php-v8js Docker images

[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-marekskopal%2Fphp--v8js-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/marekskopal/php-v8js)
[![Image size](https://img.shields.io/docker/image-size/marekskopal/php-v8js/latest?label=latest%20size)](https://hub.docker.com/r/marekskopal/php-v8js/tags)
[![Pulls](https://img.shields.io/docker/pulls/marekskopal/php-v8js)](https://hub.docker.com/r/marekskopal/php-v8js)

Production-grade Docker images for PHP **8.4** and **8.5** with the
[phpv8/v8js](https://github.com/phpv8/v8js) extension and Composer 2. Images
are multi-arch (`linux/amd64` + `linux/arm64`, including Apple Silicon
Macs via Docker Desktop).

**Built images are published to Docker Hub at
[`marekskopal/php-v8js`](https://hub.docker.com/r/marekskopal/php-v8js)** —
see the [tag matrix](#tag-matrix) below for the full list of available
tags, or [browse all tags on Docker Hub](https://hub.docker.com/r/marekskopal/php-v8js/tags).

```bash
docker pull marekskopal/php-v8js:latest
```

## Tag matrix

| PHP | Variant | OS       | Tag                                       |
| --- | ------- | -------- | ----------------------------------------- |
| 8.4 | cli     | trixie | `8.4-cli-trixie`, `8.4-cli`, `8.4`      |
| 8.4 | fpm     | trixie | `8.4-fpm-trixie`, `8.4-fpm`             |
| 8.4 | apache  | trixie | `8.4-apache-trixie`, `8.4-apache`       |
| 8.4 | zts     | trixie | `8.4-zts-trixie`, `8.4-zts`             |
| 8.4 | cli     | alpine   | `8.4-cli-alpine`                          |
| 8.4 | fpm     | alpine   | `8.4-fpm-alpine`                          |
| 8.4 | zts     | alpine   | `8.4-zts-alpine`                          |
| 8.5 | cli     | trixie | `8.5-cli-trixie`, `8.5-cli`, `8.5`, `latest` |
| 8.5 | fpm     | trixie | `8.5-fpm-trixie`, `8.5-fpm`             |
| 8.5 | apache  | trixie | `8.5-apache-trixie`, `8.5-apache`       |
| 8.5 | zts     | trixie | `8.5-zts-trixie`, `8.5-zts`             |
| 8.5 | cli     | alpine   | `8.5-cli-alpine`                          |
| 8.5 | fpm     | alpine   | `8.5-fpm-alpine`                          |
| 8.5 | zts     | alpine   | `8.5-zts-alpine`                          |

Tag shorthands follow the [official `php` image
convention](https://hub.docker.com/_/php): bare `<php>` and
`<php>-<variant>` resolve to the Debian/trixie variant.

### `zts` (thread-safe) variant

The `cli`/`fpm`/`apache` images are **non-thread-safe (NTS)**, like the
upstream `php` image defaults. The `zts` variant is built on the official
`php:<v>-zts-*` base and ships a **thread-safe** `v8js.so` (extension dir
`…/no-debug-zts-…`). Use it when the host PHP is ZTS — most notably
[FrankenPHP](https://frankenphp.dev/), which embeds a ZTS PHP. An NTS `.so`
**cannot** load into a ZTS PHP (the TSRM ABI differs), which is the whole
reason this variant exists.

The Alpine `zts` image is purpose-built to have its extension copied into a
musl ZTS runtime. For FrankenPHP, copy the `.so` + loader and add Alpine's
`nodejs-libs` (which provides the `libnode` v8js links against):

```dockerfile
FROM marekskopal/php-v8js:8.5-zts-alpine AS v8js
FROM dunglas/frankenphp:1-php8.5-alpine
RUN apk add --no-cache nodejs-libs
COPY --from=v8js /usr/local/lib/php/extensions/no-debug-zts-20250925/v8js.so \
     /usr/local/lib/php/extensions/no-debug-zts-20250925/v8js.so
COPY --from=v8js /usr/local/etc/php/conf.d/v8js.ini \
     /usr/local/etc/php/conf.d/v8js.ini
```

The extension-dir suffix (`no-debug-zts-20250925`) is the Zend module API
stamp and must match between the two images — it is identical across all PHP
8.5.x patch releases, so a `.so` built on `8.5-zts-alpine` loads into any
FrankenPHP `php8.5` Alpine tag.

There is intentionally **no `apache-alpine` variant** — the upstream
`php` image does not provide one, and building Apache + `mod_php`
against musl from source would defeat the "stay on the upstream PHP
base" production principle.

## Quick start

```bash
# CLI
docker run --rm marekskopal/php-v8js:latest \
  php -r 'echo (new V8Js)->executeString("1+2"), PHP_EOL;'

# FPM behind nginx (Compose)
services:
  php:
    image: marekskopal/php-v8js:8.5-fpm
    volumes:
      - ./app:/var/www/html

# Apache
docker run --rm -p 8080:80 -v "$PWD/app":/var/www/html \
  marekskopal/php-v8js:8.5-apache
```

## V8 version policy

| OS family | V8 source                                    | Pinned version           |
| --------- | -------------------------------------------- | ------------------------ |
| Debian    | Built from source via `depot_tools`          | **13.3.415** (configurable via `V8_VERSION` bake var) |
| Alpine    | Linked against Alpine's `nodejs-dev` package | Whatever Alpine 3.22's Node ships — currently **V8 13.6.233.17-node.44** (Node.js 24.14.1). Recorded at `/etc/v8.version` in the image. |

### Validated locally

The following were built end-to-end on a native arm64 host (Apple Silicon)
and exercised with `tests/smoke.php`:

| Image | V8 reported by `V8Js::V8_VERSION` | Result |
| ----- | --------------------------------- | ------ |
| `8.4-cli-trixie` (V8 13.3.415 from source) | `13.3.415` | smoke OK — current pin, GCC 14 build, ~87 min for the V8 stage |
| `8.4-cli-alpine` (V8 from Node 24.14.1) | `13.6.233.17-node.44` | smoke OK |
| `8.5-cli-alpine` (V8 from Node 24.14.1) | `13.6.233.17-node.44` | smoke OK |
| `8.5-zts-alpine` (ZTS, V8 from Node) | `13.6.233.17-node.49` | `new V8Js()` OK; `.so` also cross-loads into FrankenPHP `php8.5-alpine` (ZTS) |

amd64 builds were not exercised locally (would require QEMU on an arm64
host, multi-hour V8 compile). They go through the same Dockerfile and
will run on native `ubuntu-24.04` in CI.

### Why 13.3.415 on Debian (not 13.9 / 14.x)

The requirement is "V8 12+, use the latest finalized major". V8 14 is
the latest finalized major (15.x is the development branch), but v8js
can't build against it — and within V8 13, `13.3.415` is the newest tag
this repo's GCC toolchain can actually compile on **linux/arm64**. Both
limits are upstream's, not this repo's.

**Why not 14.x** — phpv8/v8js does not build against V8 14.6+, see open
issue [phpv8/v8js#546](https://github.com/phpv8/v8js/issues/546). V8
14.6 removed `Local::Holder()` (now `HolderV2()`), changed
`SetAlignedPointerInInternalField`'s signature to require an
`EmbedderDataTypeTag`, and replaced `String::Write` with `WriteV2`.
Those need ~7 source patches in v8js itself. V8 13.x still has all
three (deprecated, not removed), and v8js at the pinned `V8JS_REF` uses
exactly `String::Write` and `SetAlignedPointerInInternalField` — so 13.x
compiles unpatched.

**Why not 13.4 – 13.9** — two upstream blockers, both arm64-only, both
found by actually running the build (each failure cost ~55 min of
compile before it surfaced):

1. **13.4+ has Clang-only NEON code.** V8 writes vector code that relies
   on Clang's lax NEON typing, which GCC 14 rejects outright:
   * `src/strings/string-hasher.cc` (from **13.4**) — `cannot convert
     ‘int16x8_t’ to ‘uint16x8_t’`, `‘int8x8_t’ to ‘uint64x1_t’`.
   * `src/objects/simd.cc` (from **13.7**) — passes a `uint8x16_t` into
     `vmovn_u16()`, which takes `uint16x8_t`, and assigns a
     `vshlq_n_u64` result to a `uint8x16_t`.

   In both cases exactly **one** object out of ~2140 fails; the rest of
   the tree is GCC-clean. There's no GN arg to inject
   `-flax-vector-conversions` — the pinned `build/config/compiler`
   declares no `extra_cflags`-style arg — so the only ways forward are
   Clang or patching V8.
2. **13.9 implements Temporal in Rust.** `//third_party/rust/temporal_capi`
   is unconditionally in the graph, and V8's DEPS ships
   `third_party/rust-toolchain` for `Linux_x64 / Mac / Mac_arm64 / Win`
   only — the Linux entry is conditioned on `host_os == "linux"` with
   no arm64 build. An arm64 container therefore gets an **x86-64**
   `rustc`/`bindgen`, which dies under `qemu-x86_64` with *"Could not
   open /lib64/ld-linux-x86-64.so.2"*. `enable_rust = false` alone then
   trips `assert(enable_rust)` in `build/rust/rust_target.gni`, so
   `v8_enable_temporal_support = false` is needed as well. `build-v8.sh`
   sets both (the Temporal arg conditionally — it isn't declared before
   13.9, and `gn gen` treats an undeclared arg as fatal), so 13.4–13.9
   are reachable if you solve blocker 1.

Note that **neither blocker exists on amd64**: the x86-64 Rust toolchain
runs natively there, and the NEON code is arm64-only. Both are arm64
traps that CI's `ubuntu-24.04` leg sails straight past — they only bite
on `ubuntu-24.04-arm`.

**Why 13.3.415 specifically** — it's the last tag before the NEON code
landed, verified rather than guessed: a diff of V8 12.9.203 (the
previously shipping pin) against 13.3.415 shows the same **two** files
including `<arm_neon.h>`, with zero NEON-related changes between them,
and no `string-hasher.cc` at all. Its `.gn` also still sets
`enable_rust = false` upstream — V8 flipped that to `true` later.

To pin a different V8, override `V8_VERSION`:

```bash
docker buildx bake --set "*.args.V8_VERSION=13.2.163"
```

Caveat: **upstream v8js CI does not test 13.x.** Its matrix
(`.github/workflows/build-test.yml`) runs V8 10.9.194 and 12.9.203; a
`13.1.104` row exists but is commented out.

### Why Alpine uses `nodejs-dev` instead of `depot_tools`

V8's build system depends on Chromium's bundled clang toolchain and
assumes glibc. Building V8 on musl/Alpine via `depot_tools` is not
supported upstream and is not what phpv8/v8js's own CI does — their
Alpine job does `apk add nodejs-dev` and lets v8js link against the V8
that ships with Node.js. We follow the same approach.

The trade-off: the exact V8 minor on Alpine is determined by whichever
Node.js ships in Alpine 3.22 (currently Node 24.14.1, V8 13.6.233.17).
That is the same V8 major as the Debian image's pinned V8 13.3.415, and
is in fact a slightly newer branch — Alpine escapes the arm64 GCC/NEON
ceiling described above precisely because it never compiles V8 itself.
It was confirmed working end-to-end (`new V8Js()`, `executeString`,
exception marshalling) during build validation. The V8 the extension
was linked against is recorded in `/etc/v8.version` and in the image's
`v8.source=alpine-nodejs` label.

### Pointer compression / sandbox flags

V8 has a runtime check: the embedder (v8js) must be compiled with the
same `V8_COMPRESS_POINTERS` / `V8_ENABLE_SANDBOX` settings as V8 itself,
or `new V8Js()` aborts with *"Embedder-vs-V8 build configuration
mismatch"*. The Dockerfiles handle this:

* Debian (depot_tools build) enables both, and passes the matching
  defines via `V8JS_CPPFLAGS`.
* Alpine (Node's V8) builds without either flag, so `V8JS_CPPFLAGS`
  is left empty.

If you bump `V8_VERSION` and the upstream Chromium build defaults
change, the build will catch the mismatch immediately because each
Dockerfile runs `tests/smoke.php` (which calls `new V8Js()`) before
exporting the runtime image.

## Building locally

You need Docker 24+ with buildx. To build all variants for your host
architecture only:

```bash
docker buildx bake --set "*.platform=linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
```

To build one variant:

```bash
docker buildx bake debian-cli-84
docker buildx bake alpine-fpm-85
```

To build and push the full multi-arch matrix (requires `docker login`):

```bash
docker buildx bake --push
```

> **Heads up:** building V8 from source for the first time takes
> **1–2 hours per architecture** on a fast machine. Subsequent builds
> hit the BuildKit cache and are minutes. CI uses the GitHub Actions
> cache backend (`type=gha`) which persists across runs.

## CI / publishing

`.github/workflows/release.yml` builds on every push to `main`, pull
request, and tag `v*`. Multi-arch publishing uses **native runners**
per architecture (`ubuntu-24.04` and `ubuntu-24.04-arm`) rather than
QEMU emulation, because emulated V8 builds time out at the 6-hour job
limit. The two per-arch digests are stitched into final multi-arch
tags by a separate `manifest` job.

Secrets required:
* `DOCKERHUB_USERNAME` — Docker Hub login
* `DOCKERHUB_TOKEN`    — Docker Hub access token (write:images)

## Smoke test

`tests/smoke.php` exercises:
* `V8Js` class load
* `executeString` integer return (`1+2 === 3`)
* JS → PHP object marshalling
* `V8JsScriptException` propagation from `throw`

It runs during the image build (in both the `ext-builder` and the
final runtime stage), so a broken extension fails the build instead of
the deploy.

To run it against a built image:

```bash
docker run --rm -v "$PWD/tests:/tests" marekskopal/php-v8js:latest \
  php /tests/smoke.php
```

## Build hardening: alternative toolchain on Debian

The V8 build script uses four non-default choices that turned out to be
needed for native arm64 builds with Debian trixie's GCC 14:

* **`is_clang = false` + skip cctest** — V8's arm64 test code
  (`test-assembler-arm64.cc`, `test-code-stub-assembler.cc`) uses C++23
  `42.15f16` numeric literals and Clang-syntax inline asm. GCC 14
  parses the literals but still rejects the inline asm syntax. The
  script invokes ninja only for the embedder targets
  (`v8 v8_libplatform v8_libbase`) so those test files never compile.
* **`use_sysroot = false`** — skips Chromium's vendored Debian sysroot
  download (which is amd64-only for `arm64.release` because that GN
  preset is a cross-compile simulator config) and uses the host's libc.
* **`enable_rust = false`** — V8 flips Rust on by default from 13.6
  (13.3.415's own `.gn` still has it off), but Chromium publishes no
  Linux arm64 Rust toolchain. Harmless at the current pin, and required
  the moment anyone bumps past it. See the version policy section above
  for the full failure mode.
* **`v8_enable_temporal_support = false`** — emitted only when the
  checked-out V8 declares it (13.9+). Temporal is the one thing in V8
  that actually needs Rust, and it's gated behind `--harmony-temporal`
  at runtime anyway.

A production-validated alternative (the path the Legito monolith uses
in prod) is to install **Clang 17** from `apt.llvm.org` on arm64 and
build with `is_clang = true`. That builds the full V8 source including
cctest. It's heavier (extra LLVM apt install, more build artifacts)
but it's exactly what Chromium upstream tests against — if you start
hitting subtle V8 codegen bugs with the GCC build, switch to Clang.
Reference: `infrastructure/legito_php/Dockerfile` (V8 11.8.144 +
LLVM 17 + `tools/dev/gm.py`).

Clang is also the only unpatched way past V8 13.4+ on arm64 (the
`string-hasher.cc` / `simd.cc` NEON code above). Note you cannot use
*Chromium's* clang there: like the
Rust toolchain, `third_party/llvm-build` is published for
`Linux_x64 / Mac / Mac_arm64 / Win` only, so an arm64 builder has to
supply its own — Debian trixie ships clang 19, against a V8 that
expects Chromium's clang 21.

V8 **11.8.144** is the version Legito ships in production. It's much
older than this repo's default `V8_VERSION=13.3.415` but is the
known-good fallback if 13.x ever regresses for you:

```bash
docker buildx bake --set "*.args.V8_VERSION=11.8.144"
```

## Known limitations / open questions

* **V8 13.3.415 is not tested by upstream v8js CI** (its matrix stops at
  12.9.203) and is built with GCC rather than Chromium's clang. It is
  smoke-tested locally on arm64 (see above); the amd64 leg is validated
  by the first CI run. Fall back to `V8_VERSION=13.2.163` or `12.9.203`
  if it breaks.
* **V8 13.4+ needs a Clang builder on arm64**, so this pin sits six
  branches behind the end of the 13 line. Moving forward means either
  re-tooling the Debian builder to Clang — Debian trixie's clang 19,
  since Chromium publishes no Linux arm64 clang — or carrying patches
  for `src/strings/string-hasher.cc` and `src/objects/simd.cc`. See the
  version policy section for the exact errors.
* **V8 14 is still out of reach.** Track
  [v8js#546](https://github.com/phpv8/v8js/issues/546) for the V8 14
  patch set; once merged, bump `V8_VERSION` here.
* **ARM64 V8 builds are unproven by upstream** — see
  [v8js#529](https://github.com/phpv8/v8js/issues/529). Builds *should*
  work on `ubuntu-24.04-arm` (native arm64, glibc), but expect to
  patch if V8's build system changes. Failures will surface in CI; the
  Debian Dockerfile's V8 stage is intentionally fail-fast.
* **PHP 8.5 is not yet covered by upstream v8js CI**. The PHP 8.4
  deprecation work in PR #545 should carry forward, but if 8.5
  introduces an API break, the smoke test will catch it at build time.
* **Alpine V8 version is not pinned** — it tracks Alpine's nodejs
  package, so an Alpine point release can shift V8. The build-time V8
  version is captured in the image label and at `/etc/v8.version`.

## File layout

```
.
├── docker-bake.hcl              # bake matrix (cli/fpm/apache/zts × OS × PHP)
├── images/
│   ├── debian/Dockerfile        # 4 variants (cli/fpm/apache/zts) × 2 PHP versions
│   └── alpine/Dockerfile        # 3 variants (cli/fpm/zts) × 2 PHP versions
├── scripts/
│   ├── build-v8.sh              # depot_tools + gn + ninja (Debian only)
│   └── install-v8js.sh          # phpize + configure + make install
├── tests/smoke.php              # runtime sanity check
└── .github/workflows/release.yml
```

## License

MIT.
