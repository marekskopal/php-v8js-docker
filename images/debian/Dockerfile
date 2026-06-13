# syntax=docker/dockerfile:1.7
#
# Debian (trixie / Debian 13) image: builds V8 from source via depot_tools,
# then the v8js PHP extension, then assembles a slim runtime on the official
# PHP base.

ARG PHP_VERSION=8.4
ARG PHP_VARIANT=cli
ARG OS_TAG=trixie
# Threading model of the PHP base used to COMPILE v8js. A `.so` built on an
# NTS base cannot load into a ZTS PHP (and vice versa) — the TSRM ABI differs.
# Keep this in lock-step with the runtime: `cli` for the NTS variants
# (cli/fpm/apache), `zts` for the thread-safe variant. The bake file sets it.
ARG BUILDER_VARIANT=cli
ARG V8_VERSION=12.9.203
# Pinned to the head of phpv8/v8js's php8 branch as of 2026-04-19 (the merge
# of PR #545: PHP 8.4 deprecation fixes and memory-leak patches).
ARG V8JS_REF=8a39efa3
ARG V8_PREFIX=/opt/v8

# ---------------------------------------------------------------------------
# Stage 1: V8 builder. Intentionally based on debian:trixie-slim (not the
# PHP image) so the cache layer is shared between PHP 8.4 and 8.5 builds.
# ---------------------------------------------------------------------------
FROM debian:${OS_TAG}-slim AS v8-builder

ARG V8_VERSION
ARG V8_PREFIX
ARG TARGETARCH

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        build-essential \
        ca-certificates \
        curl \
        git \
        libglib2.0-dev \
        patchelf \
        pkg-config \
        python3 \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/build-v8.sh /usr/local/bin/build-v8.sh
RUN chmod +x /usr/local/bin/build-v8.sh && \
    V8_VERSION=${V8_VERSION} V8_PREFIX=${V8_PREFIX} TARGETARCH=${TARGETARCH} \
        /usr/local/bin/build-v8.sh

# ---------------------------------------------------------------------------
# Stage 2: v8js extension builder. BUILDER_VARIANT selects the threading model
# of the PHP base: `cli` (NTS) yields a .so ABI-compatible with cli/fpm/apache
# (they share headers within a PHP minor); `zts` yields the thread-safe build.
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-${BUILDER_VARIANT}-${OS_TAG} AS ext-builder

ARG V8JS_REF
ARG V8_PREFIX

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        build-essential \
        ca-certificates \
        git \
        libglib2.0-0 \
        pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY --from=v8-builder ${V8_PREFIX} ${V8_PREFIX}
COPY scripts/install-v8js.sh /usr/local/bin/install-v8js.sh
COPY tests/smoke.php /tmp/smoke.php
# build-v8.sh enables pointer compression + sandbox in V8's args.gn; the
# extension MUST be compiled with the matching defines or `new V8Js()` aborts.
RUN chmod +x /usr/local/bin/install-v8js.sh && \
    V8JS_REF=${V8JS_REF} \
    V8_PREFIX=${V8_PREFIX} \
    V8JS_CPPFLAGS="-DV8_COMPRESS_POINTERS -DV8_ENABLE_SANDBOX" \
        /usr/local/bin/install-v8js.sh && \
    php /tmp/smoke.php

# ---------------------------------------------------------------------------
# Stage 3: runtime. PHP_VARIANT chooses cli / fpm / apache (Debian-only).
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-${PHP_VARIANT}-${OS_TAG} AS runtime

ARG V8_PREFIX
ARG V8_VERSION
ARG V8JS_REF
ARG PHP_VERSION
ARG PHP_VARIANT

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=v8-builder ${V8_PREFIX}/lib ${V8_PREFIX}/lib
RUN echo "${V8_PREFIX}/lib" > /etc/ld.so.conf.d/v8.conf && ldconfig

COPY --from=ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=ext-builder /usr/local/etc/php/conf.d/v8js.ini /usr/local/etc/php/conf.d/v8js.ini

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Verify the assembled runtime actually loads the extension. Catches RPATH /
# ld.so.conf regressions before the image is pushed.
RUN php -r 'exit(class_exists("V8Js") ? 0 : 1);' && \
    composer --version > /dev/null

LABEL org.opencontainers.image.title="php-v8js" \
      org.opencontainers.image.description="PHP ${PHP_VERSION} (${PHP_VARIANT}) on Debian ${OS_TAG} with the v8js extension and Composer 2." \
      org.opencontainers.image.source="https://github.com/marekskopal/php-v8js-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="marekskopal" \
      org.opencontainers.image.base.name="docker.io/library/php:${PHP_VERSION}-${PHP_VARIANT}-${OS_TAG}" \
      php.version="${PHP_VERSION}" \
      php.variant="${PHP_VARIANT}" \
      v8.version="${V8_VERSION}" \
      v8js.ref="${V8JS_REF}"
