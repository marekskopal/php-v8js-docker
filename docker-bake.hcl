# docker buildx bake matrix for the php-v8js image set.
#
# Convention for tags mirrors the official `php` image:
#   <php>-<variant>-<os>     e.g. 8.4-fpm-bookworm   (always available)
#   <php>-<variant>          e.g. 8.4-fpm           (Debian shorthand, like upstream php image)
#   <php>                    e.g. 8.4               (cli, Debian — latest within the minor)
#   latest                   = newest PHP + cli + Debian
#
# Usage:
#   docker buildx bake                  # build everything for the default platforms
#   docker buildx bake debian-cli       # one target group
#   docker buildx bake --push           # push tagged images to the registry

variable "REGISTRY" { default = "docker.io" }
variable "REPO"     { default = "marekskopal/php-v8js" }
variable "V8_VERSION" { default = "12.9.203" }

# Pinned to phpv8/v8js php8 @ 8a39efa3 (PR #545 merge: PHP 8.4 + memory-leak
# fixes). Bump deliberately, not "latest", so images are reproducible.
variable "V8JS_REF" { default = "8a39efa3" }

variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}

# Which PHP minor is considered "current" — gets the bare :latest and :<php>
# convenience tags. Bump this when a new PHP minor is added.
variable "LATEST_PHP" { default = "8.5" }

variable "PHP_VERSIONS" {
  default = ["8.4", "8.5"]
}

function "img" {
  params = [tag]
  result = "${REGISTRY}/${REPO}:${tag}"
}

# Extra tags applied to the Debian-bookworm-cli image of LATEST_PHP only.
function "extra_latest_tags" {
  params = [php, variant, os]
  result = (php == LATEST_PHP && variant == "cli" && os == "bookworm") ? [img("latest")] : []
}

# Debian "shorthand" tag (e.g. :8.4-cli) only for the bookworm row, since
# bookworm is the default for the upstream php image. cli also gets bare :<php>.
function "debian_shorthand_tags" {
  params = [php, variant, os]
  result = (os != "bookworm") ? [] : (variant == "cli" ? [img("${php}-${variant}"), img(php)] : [img("${php}-${variant}")])
}

group "default" {
  targets = ["debian", "alpine"]
}

group "debian" {
  targets = ["debian-cli", "debian-fpm", "debian-apache"]
}

group "alpine" {
  targets = ["alpine-cli", "alpine-fpm"]
}

target "_common" {
  context    = "."
  platforms  = PLATFORMS
  pull       = true
  # Use the GitHub Actions cache backend when running in CI; falls back to
  # inline cache otherwise. Override via BUILDX_BAKE_ENTITLEMENTS=… as needed.
  cache-from = ["type=gha"]
  cache-to   = ["type=gha,mode=max"]
}

target "_debian" {
  inherits   = ["_common"]
  dockerfile = "images/debian/Dockerfile"
  args = {
    OS_TAG     = "bookworm"
    V8_VERSION = V8_VERSION
    V8JS_REF   = V8JS_REF
  }
}

target "_alpine" {
  inherits   = ["_common"]
  dockerfile = "images/alpine/Dockerfile"
  args = {
    OS_TAG   = "alpine"
    V8JS_REF = V8JS_REF
  }
}

target "debian-cli" {
  inherits = ["_debian"]
  name     = "debian-cli-${replace(php, ".", "")}"
  matrix   = { php = PHP_VERSIONS }
  args = {
    PHP_VERSION = php
    PHP_VARIANT = "cli"
  }
  tags = concat(
    [img("${php}-cli-bookworm")],
    debian_shorthand_tags(php, "cli", "bookworm"),
    extra_latest_tags(php, "cli", "bookworm"),
  )
}

target "debian-fpm" {
  inherits = ["_debian"]
  name     = "debian-fpm-${replace(php, ".", "")}"
  matrix   = { php = PHP_VERSIONS }
  args = {
    PHP_VERSION = php
    PHP_VARIANT = "fpm"
  }
  tags = concat(
    [img("${php}-fpm-bookworm")],
    debian_shorthand_tags(php, "fpm", "bookworm"),
  )
}

target "debian-apache" {
  inherits = ["_debian"]
  name     = "debian-apache-${replace(php, ".", "")}"
  matrix   = { php = PHP_VERSIONS }
  args = {
    PHP_VERSION = php
    PHP_VARIANT = "apache"
  }
  tags = concat(
    [img("${php}-apache-bookworm")],
    debian_shorthand_tags(php, "apache", "bookworm"),
  )
}

target "alpine-cli" {
  inherits = ["_alpine"]
  name     = "alpine-cli-${replace(php, ".", "")}"
  matrix   = { php = PHP_VERSIONS }
  args = {
    PHP_VERSION = php
    PHP_VARIANT = "cli"
  }
  tags = [img("${php}-cli-alpine")]
}

target "alpine-fpm" {
  inherits = ["_alpine"]
  name     = "alpine-fpm-${replace(php, ".", "")}"
  matrix   = { php = PHP_VERSIONS }
  args = {
    PHP_VERSION = php
    PHP_VARIANT = "fpm"
  }
  tags = [img("${php}-fpm-alpine")]
}
