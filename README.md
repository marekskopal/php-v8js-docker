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
| 8.4 | cli     | alpine   | `8.4-cli-alpine`                          |
| 8.4 | fpm     | alpine   | `8.4-fpm-alpine`                          |
| 8.5 | cli     | trixie | `8.5-cli-trixie`, `8.5-cli`, `8.5`, `latest` |
| 8.5 | fpm     | trixie | `8.5-fpm-trixie`, `8.5-fpm`             |
| 8.5 | apache  | trixie | `8.5-apache-trixie`, `8.5-apache`       |
| 8.5 | cli     | alpine   | `8.5-cli-alpine`                          |
| 8.5 | fpm     | alpine   | `8.5-fpm-alpine`                          |

Tag shorthands follow the [official `php` image
convention](https://hub.docker.com/_/php): bare `<php>` and
`<php>-<variant>` resolve to the Debian/trixie variant.

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
| Debian    | Built from source via `depot_tools`          | **12.9.203** (configurable via `V8_VERSION` bake var) |
| Alpine    | Linked against Alpine's `nodejs-dev` package | Whatever Alpine 3.22's Node ships — currently **V8 13.6.233.17-node.44** (Node.js 24.14.1). Recorded at `/etc/v8.version` in the image. |

### Validated locally

The following were built end-to-end on a native arm64 host (Apple Silicon)
and exercised with `tests/smoke.php`:

| Image | V8 reported by `V8Js::V8_VERSION` | Result |
| ----- | --------------------------------- | ------ |
| `8.4-cli-trixie` (V8 12.9.203 from source) | `12.9.203` | smoke OK |
| `8.4-cli-alpine` (V8 from Node 24.14.1) | `13.6.233.17-node.44` | smoke OK |
| `8.5-cli-alpine` (V8 from Node 24.14.1) | `13.6.233.17-node.44` | smoke OK |

amd64 builds were not exercised locally (would require QEMU on an arm64
host, multi-hour V8 compile). They go through the same Dockerfile and
will run on native `ubuntu-24.04` in CI.

### Why 12.9.203 on Debian (not 14.x)

The user-facing requirement was "V8 12+, use the latest finalized major".
The latest finalized V8 major is currently 14 (15.x is the development
branch). However:

1. **phpv8/v8js does not currently build against V8 14.6+** — see open
   issue [phpv8/v8js#546](https://github.com/phpv8/v8js/issues/546).
   V8 14.6 removed `Local::Holder()` (now `HolderV2()`), changed
   `SetAlignedPointerInInternalField`'s signature to require an
   `EmbedderDataTypeTag`, and replaced `String::Write` with `WriteV2`.
   These need ~7 source patches in v8js itself.
2. **V8 13.x is plausibly compatible but untested** — phpv8/v8js's CI
   matrix only actively runs against V8 10.9.194 and V8 12.9.203.
3. **V8 12.9.203 is the highest version upstream actively tests**
   (`.github/workflows/build-test.yml` in phpv8/v8js).

To bump to V8 13 or a patched V8 14, override `V8_VERSION`:

```bash
docker buildx bake --set "*.args.V8_VERSION=13.1.104"
```

### Why Alpine uses `nodejs-dev` instead of `depot_tools`

V8's build system depends on Chromium's bundled clang toolchain and
assumes glibc. Building V8 on musl/Alpine via `depot_tools` is not
supported upstream and is not what phpv8/v8js's own CI does — their
Alpine job does `apk add nodejs-dev` and lets v8js link against the V8
that ships with Node.js. We follow the same approach.

The trade-off: the exact V8 minor on Alpine is determined by whichever
Node.js ships in Alpine 3.22 (currently Node 24.14.1, V8 13.6.233.17).
That happens to be *newer* than the Debian image's pinned V8 12.9.203,
and was confirmed working end-to-end (`new V8Js()`, `executeString`,
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

The V8 build script uses two non-default choices that turned out to be
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

A production-validated alternative (the path the Legito monolith uses
in prod) is to install **Clang 17** from `apt.llvm.org` on arm64 and
build with `is_clang = true`. That builds the full V8 source including
cctest. It's heavier (extra LLVM apt install, more build artifacts)
but it's exactly what Chromium upstream tests against — if you start
hitting subtle V8 codegen bugs with the GCC build, switch to Clang.
Reference: `infrastructure/legito_php/Dockerfile` (V8 11.8.144 +
LLVM 17 + `tools/dev/gm.py`).

V8 **11.8.144** is the version Legito ships in production. It's older
than this repo's default `V8_VERSION=12.9.203` but is the known-good
fallback if 12.9.203 ever regresses for you:

```bash
docker buildx bake --set "*.args.V8_VERSION=11.8.144"
```

## Known limitations / open questions

* **V8 12.9.203 is from 2024-09** and missing perf improvements from
  13/14. Track [v8js#546](https://github.com/phpv8/v8js/issues/546)
  for the V8 14 patch set; once merged, bump `V8_VERSION` here.
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
├── docker-bake.hcl              # bake matrix (all 10 tags)
├── images/
│   ├── debian/Dockerfile        # 3 variants × 2 PHP versions = 6 tags
│   └── alpine/Dockerfile        # 2 variants × 2 PHP versions = 4 tags
├── scripts/
│   ├── build-v8.sh              # depot_tools + gn + ninja (Debian only)
│   └── install-v8js.sh          # phpize + configure + make install
├── tests/smoke.php              # runtime sanity check
└── .github/workflows/release.yml
```

## License

MIT.
