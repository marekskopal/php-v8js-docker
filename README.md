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
| Debian    | Built from source via `depot_tools` + Debian clang | **13.9.210** (configurable via `V8_VERSION` bake var) |
| Alpine    | Linked against Alpine's `nodejs-dev` package | Whatever Alpine 3.22's Node ships — currently **V8 13.6.233.17-node.44** (Node.js 24.14.1). Recorded at `/etc/v8.version` in the image. |

### Validated locally

The following were built end-to-end on a native arm64 host (Apple Silicon)
and exercised with `tests/smoke.php`:

| Image | V8 reported by `V8Js::V8_VERSION` | Result |
| ----- | --------------------------------- | ------ |
| `8.4-cli-trixie` (V8 13.9.210 from source) | `13.9.210` | smoke OK — current pin, Debian clang 19 build |
| `8.4-cli-trixie` (V8 13.3.415 from source) | `13.3.415` | smoke OK — previous pin, GCC 14 build (~87 min for the V8 stage). Still the highest tag GCC can build; see below |
| `8.4-cli-alpine` (V8 from Node 24.14.1) | `13.6.233.17-node.44` | smoke OK |
| `8.5-cli-alpine` (V8 from Node 24.14.1) | `13.6.233.17-node.44` | smoke OK |
| `8.5-zts-alpine` (ZTS, V8 from Node) | `13.6.233.17-node.49` | `new V8Js()` OK; `.so` also cross-loads into FrankenPHP `php8.5-alpine` (ZTS) |

amd64 builds were not exercised locally (would require QEMU on an arm64
host, multi-hour V8 compile). They go through the same Dockerfile and
will run on native `ubuntu-24.04` in CI.

### Why 13.9.210 on Debian (not 14.x)

The requirement is "V8 12+, use the latest finalized major". V8 14 is
the latest finalized major (15.x is the development branch), but v8js
can't build against it, so the pin is the tip of the last V8 **13**
branch — `13.9.210` (Chrome 139's V8).

**Why not 14.x** — phpv8/v8js does not build against V8 14.6+, see open
issue [phpv8/v8js#546](https://github.com/phpv8/v8js/issues/546). V8
14.6 removed `Local::Holder()` (now `HolderV2()`), changed
`SetAlignedPointerInInternalField`'s signature to require an
`EmbedderDataTypeTag`, and replaced `String::Write` with `WriteV2`.
Those need ~7 source patches in v8js itself. V8 13.x still has all
three (deprecated, not removed), and v8js at the pinned `V8JS_REF` uses
exactly `String::Write` and `SetAlignedPointerInInternalField` — so 13.x
compiles unpatched.

**Why the Debian builder uses clang, not GCC** — V8 13.4+ cannot be
built with GCC on arm64 at all. Two files write vector code that relies
on Clang's lax NEON typing, which GCC 14 rejects outright:

* `src/strings/string-hasher.cc` (from **13.4**) — `cannot convert
  ‘int16x8_t’ to ‘uint16x8_t’`, `‘int8x8_t’ to ‘uint64x1_t’`.
* `src/objects/simd.cc` (from **13.7**) — passes a `uint8x16_t` into
  `vmovn_u16()`, which takes `uint16x8_t`, and assigns a `vshlq_n_u64`
  result to a `uint8x16_t`.

In both cases exactly **one** object out of ~2150 fails; the rest of the
tree is GCC-clean. There is no GN arg to inject
`-flax-vector-conversions` (the pinned `build/config/compiler` declares
no `extra_cflags`-style arg), so the choice is Clang or patching V8.
`13.3.415` is the last GCC-buildable tag if you need that route —
set `V8_TOOLCHAIN=gcc` and pin it.

Using Clang on Debian means the *distro* Clang: Chromium publishes its
own bundle for `Linux_x64 / Mac / Mac_arm64 / Win` only, with **no Linux
arm64 build**. Five things were needed to make that work, all handled by
`build-v8.sh` and the Dockerfile:

1. `clang_base_path = "/usr"` — point GN at Debian's clang instead of
   `//third_party/llvm-build/Release+Asserts`. This also skips a
   `clang_revision`/`clang_version` consistency assert that only fires
   for the bundled toolchain.
2. `clang_version` — Chromium hardcodes its bundle's `"21"`, and the
   value drives `-resource-dir` and `libclang_rt` paths. `build-v8.sh`
   detects the installed major version instead of hardcoding it.
3. `clang_use_chrome_plugins = false` — the plugins are `.so`s built
   against Chromium's clang.
4. **compiler-rt layout** — Debian's `libclang-rt-dev` ships
   `lib/linux/libclang_rt.builtins-<arch>.a`; Chromium links
   `lib/<triple>/libclang_rt.builtins.a` (LLVM's newer per-target
   layout). Without a symlink the first `.so` link fails with *"missing
   and no known rule to make it"*.
5. **LLVM binutils** — `build/toolchain/gcc_solink_wrapper.py` shells
   out to unversioned `/usr/bin/llvm-readelf` and `llvm-nm`; Debian
   installs only `-<version>` suffixed names, so those get symlinked too.

Clang 19 (trixie's default) builds V8 13.9.210 fine despite the tree
expecting Chromium's clang 21 — the only fallout is ~1500
`unknown warning option '-Wno-nontrivial-memcall'` notes, harmless
because `treat_warnings_as_errors = false`.

**Rust / Temporal is still disabled.** From 13.9 the Temporal API is
implemented in Rust (`//third_party/rust/temporal_capi`), and V8's DEPS
ships `third_party/rust-toolchain` for `Linux_x64 / Mac / Mac_arm64 /
Win` only — the Linux entry is conditioned on `host_os == "linux"` with
no arm64 build. An arm64 container therefore gets an **x86-64**
`rustc`/`bindgen` that dies under `qemu-x86_64` with *"Could not open
/lib64/ld-linux-x86-64.so.2"*. Clang does not help here, so
`build-v8.sh` sets `enable_rust = false` plus
`v8_enable_temporal_support = false` (the latter only when the checked
out V8 declares it — it doesn't before 13.9, and `gn gen` treats an
undeclared arg as fatal). Consequence: **`Temporal` is not compiled
into these images.** Upstream gates it behind `--harmony-temporal` at
runtime anyway, and excludes the arg on architectures without a Rust
toolchain for exactly this reason.

Note the NEON and Rust problems are both **arm64-only** — the x86-64
Rust toolchain runs natively on amd64 and the NEON code is arm64-only,
so CI's `ubuntu-24.04` leg sails past both. They only bite on
`ubuntu-24.04-arm`.

To pin a different V8, override `V8_VERSION`:

```bash
docker buildx bake --set "*.args.V8_VERSION=13.8.260"
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
That is a slightly older branch than the Debian image's pinned V8
13.9.210, and it sidesteps every toolchain problem described above
because it never compiles V8 itself. It was confirmed working
end-to-end (`new V8Js()`, `executeString`,
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

## Build hardening: toolchain choices on Debian

The V8 build script makes five non-default GN choices. `V8_TOOLCHAIN`
(`clang` by default, `gcc` accepted) selects the compiler; the clang
plumbing is detailed in the version policy section above.

* **`is_clang = true` + `clang_base_path` + `clang_version` +
  `clang_use_chrome_plugins = false`** — build with Debian's clang,
  because Chromium ships no Linux arm64 clang bundle and V8 13.4+ needs
  Clang semantics for its NEON code. Also **skip cctest**: V8's arm64
  test code (`test-assembler-arm64.cc`, `test-code-stub-assembler.cc`)
  needs C++23 `42.15f16` literals and Clang-syntax inline asm, so the
  script invokes ninja only for the embedder targets
  (`v8 v8_libplatform v8_libbase`) and those files never compile.
* **`use_sysroot = false`** — skips Chromium's vendored Debian sysroot
  download (which is amd64-only for `arm64.release` because that GN
  preset is a cross-compile simulator config) and uses the host's libc.
* **`use_custom_libcxx = false`** — link against system libstdc++,
  matching v8js's LDFLAGS expectation.
* **`enable_rust = false`** — V8 flips Rust on by default from 13.6, but
  Chromium publishes no Linux arm64 Rust toolchain.
* **`v8_enable_temporal_support = false`** — emitted only when the
  checked-out V8 declares it (13.9+). Temporal is the one part of V8
  that actually needs Rust, and it's gated behind `--harmony-temporal`
  at runtime anyway.

`V8_TOOLCHAIN=gcc` is the escape hatch if the distro clang ever breaks,
but it only reaches **V8 13.3.415** — 13.4+ fails on the NEON code.

For reference, the Legito monolith builds V8 11.8.144 in prod with
**Clang 17** from `apt.llvm.org` and `tools/dev/gm.py`
(`infrastructure/legito_php/Dockerfile`). Pulling clang from
`apt.llvm.org` instead of Debian is the route to try if trixie's clang
version ever lags what a newer V8 needs — `build-v8.sh` reads the major
version from `clang --version`, so a newer LLVM works without edits as
long as `/usr/lib/llvm-<N>` is laid out the usual way.

V8 **11.8.144** is the version Legito ships in production. It's much
older than this repo's default `V8_VERSION=13.9.210` but is the
known-good fallback if 13.x ever regresses for you (use it with
`V8_TOOLCHAIN=gcc` or clang — both work at that vintage):

```bash
docker buildx bake --set "*.args.V8_VERSION=11.8.144"
```

## Known limitations / open questions

* **V8 13.9.210 is not tested by upstream v8js CI** (its matrix stops at
  12.9.203), and it's built with Debian's clang rather than Chromium's
  bundled one. It is smoke-tested locally on arm64 (see above); the
  amd64 leg is validated by the first CI run. Fall back to
  `V8_VERSION=13.3.415 V8_TOOLCHAIN=gcc` or `12.9.203` if it breaks.
* **`Temporal` is not available in these images.** Its V8 implementation
  is Rust-based and Chromium ships no Linux arm64 Rust toolchain, so
  `v8_enable_temporal_support = false`. It would need `--harmony-temporal`
  at runtime regardless. To get it you'd have to supply an arm64 Rust
  toolchain (e.g. Debian's `rustc` via `rust_sysroot_absolute`) — untried
  here.
* **The clang build depends on Debian's LLVM layout.** Two symlinks
  bridge it to what Chromium expects (compiler-rt per-target directory,
  unversioned `llvm-*` binutils). A future Debian LLVM reorganisation
  would break the V8 stage — loudly, at build time, not silently.
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
