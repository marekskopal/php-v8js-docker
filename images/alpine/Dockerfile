# syntax=docker/dockerfile:1.7
#
# Alpine image: links v8js against the V8 bundled in Alpine's `nodejs-dev`
# package. This intentionally diverges from the Debian build (which uses
# depot_tools). Rationale:
#
#   * V8's build system assumes glibc + Chromium's bundled clang sysroot;
#     building it on musl/Alpine via depot_tools is not supported upstream
#     (phpv8/v8js's own CI takes this same shortcut — see their build-test.yml
#     `alpine` job).
#   * Alpine 3.22's nodejs package ships V8 12.4+, satisfying the V8 12+
#     floor; the exact V8 minor is whatever Alpine's nodejs-dev provides at
#     build time. The `v8.version` label records what was used.

ARG PHP_VERSION=8.4
ARG PHP_VARIANT=cli
ARG OS_TAG=alpine
ARG V8JS_REF=8a39efa3
# Threading model of the PHP base used to COMPILE v8js. A `.so` built on an
# NTS base cannot load into a ZTS PHP (and vice versa) — the TSRM ABI differs.
# Keep this in lock-step with the runtime: `cli` for the NTS variants
# (cli/fpm), `zts` for the thread-safe variant. The bake file sets it.
ARG BUILDER_VARIANT=cli

# ---------------------------------------------------------------------------
# Stage 1: v8js extension builder.
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-${BUILDER_VARIANT}-${OS_TAG} AS ext-builder

ARG V8JS_REF

RUN apk add --no-cache --virtual .build-deps \
        autoconf \
        build-base \
        git \
        nodejs-dev \
        pkgconfig

COPY scripts/install-v8js.sh /usr/local/bin/install-v8js.sh
COPY tests/smoke.php /tmp/smoke.php

# Node.js's V8 is built WITHOUT pointer compression / sandbox — passing those
# defines would crash `new V8Js()` with "Embedder-vs-V8 build configuration
# mismatch". Leave V8JS_CPPFLAGS empty so we inherit Node's V8 config.
# V8_PREFIX is empty so configure auto-detects via system include/lib paths
# populated by nodejs-dev (which puts headers under /usr/include/node/).
RUN chmod +x /usr/local/bin/install-v8js.sh && \
    V8JS_REF=${V8JS_REF} V8_PREFIX= \
        /usr/local/bin/install-v8js.sh && \
    php /tmp/smoke.php && \
    php -r 'echo V8Js::V8_VERSION;' > /tmp/v8.version

# ---------------------------------------------------------------------------
# Stage 2: runtime. PHP_VARIANT chooses cli or fpm (no apache-alpine in the
# official PHP image set).
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-${PHP_VARIANT}-${OS_TAG} AS runtime

ARG PHP_VERSION
ARG PHP_VARIANT
ARG V8JS_REF

# v8js.so links against libnode (which embeds V8); the `nodejs-libs`
# subpackage provides libnode.so.X without the `node` CLI binary, keeping
# the runtime image smaller. `nodejs-dev` (build stage) pulled this in
# transitively; we install it explicitly here.
RUN apk add --no-cache nodejs-libs

COPY --from=ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=ext-builder /usr/local/etc/php/conf.d/v8js.ini /usr/local/etc/php/conf.d/v8js.ini
COPY --from=ext-builder /tmp/v8.version /etc/v8.version

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN php -r 'exit(class_exists("V8Js") ? 0 : 1);' && \
    composer --version > /dev/null

LABEL org.opencontainers.image.title="php-v8js" \
      org.opencontainers.image.description="PHP ${PHP_VERSION} (${PHP_VARIANT}) on Alpine with the v8js extension (linked against Alpine's nodejs V8) and Composer 2." \
      org.opencontainers.image.source="https://github.com/marekskopal/php-v8js-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="marekskopal" \
      org.opencontainers.image.base.name="docker.io/library/php:${PHP_VERSION}-${PHP_VARIANT}-${OS_TAG}" \
      php.version="${PHP_VERSION}" \
      php.variant="${PHP_VARIANT}" \
      v8.source="alpine-nodejs" \
      v8js.ref="${V8JS_REF}"
