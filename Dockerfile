ARG ARCH="arm64/v8"

ARG DP_CFLAGS_OPTIMIZE="-O2"
ARG DP_CFLAGS="-fstack-protector-strong -fpic -fpie ${DP_CFLAGS_OPTIMIZE}"
ARG DP_CPPFLAGS_OPTIMIZE="-O2"
ARG DP_CPPFLAGS="-fstack-protector-strong -fpic -fpie ${DP_CPPFLAGS_OPTIMIZE}"
ARG DP_LDFLAGS_OPTIMIZE="-O1"
ARG DP_LDFLAGS="-Wl,${DP_LDFLAGS_OPTIMIZE} -pie"
ARG DP_PHP_INI_DIR="/usr/local/etc/php"
ARG DP_PHP_DEB_PACKAGES="libgmp-dev libzip-dev libyaml-dev libzstd-dev libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev libsodium-dev libsqlite3-dev libssl-dev zlib1g-dev"
ARG DP_PHP_CONFIGURE_OPTIONS="--enable-bcmath --enable-exif --enable-intl --enable-pcntl --enable-sockets --enable-sysvmsg --enable-sysvsem --enable-sysvshm --with-gmp --with-pdo-mysql --with-zip --with-pic --enable-mysqlnd --with-password-argon2 --with-sodium --with-pdo-sqlite=/usr --with-sqlite3=/usr --with-curl --with-iconv --with-openssl --with-readline --with-zlib --disable-phpdbg --disable-cgi --enable-fpm --with-fpm-user=nonroot --with-fpm-group=nonroot"
ARG DP_PHP_SAPIS="/usr/local/bin/php"

FROM --platform="linux/${ARCH}" debian:12 AS base

ARG DP_CFLAGS_OPTIMIZE
ARG DP_CFLAGS
ARG DP_CPPFLAGS_OPTIMIZE
ARG DP_CPPFLAGS
ARG DP_LDFLAGS_OPTIMIZE
ARG DP_LDFLAGS
ARG DP_PHP_INI_DIR
ARG DP_PHP_DEB_PACKAGES
ARG DP_PHP_CONFIGURE_OPTIONS
ARG DP_PHP_SAPIS

# base
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      "build-essential" "ca-certificates" "pkg-config" "autoconf" "automake" "bison" "re2c" "curl"

# ICU
COPY "third_party/unicode-org/icu" "/build/icu"
COPY "third_party/alpinelinux/aports/main/icu/data-filter-en.yml" "/build/icu/data-filter-en.yml"
RUN apt-get update \
 && apt-get install -y "python3" "python3-yaml" \
 && cd "/build/icu/icu4c/source" \
 &&   python3 -c 'import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout)' < "/build/icu/data-filter-en.yml" > "/build/icu/data-filter-en.json" \
 &&   ICU_DATA_FILTER_FILE="/build/icu/data-filter-en.json" DP_CFLAGS="${DP_CFLAGS_OPTIMIZE}" DP_CPPFLAGS="${DP_CPPFLAGS_OPTIMIZE}" DP_LDFLAGS="${DP_LDFLAGS_OPTIMIZE}" ./configure --prefix="/usr" --with-data-packaging=static --disable-samples --enable-shared --disable-static \
 &&   make -j"$(nproc)" \
 &&   make install \
 && cd -

# libxml2
COPY "third_party/GNOME/libxml2" "/build/libxml2"
RUN apt-get update \
 && apt-get install -y "meson" "ninja-build" "zlib1g-dev" "python3-dev" "git" \
 && cd "/build/libxml2" \
 &&   CFLAGS="${DP_CFLAGS_OPTIMIZE}" CPPFLAGS="${DP_CPPFLAGS_OPTIMIZE}" LDFLAGS="${DP_LDFLAGS_OPTIMIZE}" meson setup --prefix="/usr" "build" \
 &&   ninja -C "build" \
 &&   ninja -C "build" install \
 && cd -

# PHP
COPY "third_party/php/php-src" "/build/php-src"
RUN apt-get update \
 && apt-get install -y ${DP_PHP_DEB_PACKAGES} \
 && cd "/build/php-src" \
 &&   ./buildconf --force \
 &&   CFLAGS="-I/usr/include/libxml2 ${DP_CFLAGS}" CPPFLAGS="-I/usr/include/libxml2 ${DP_CPPFLAGS}" LDFLAGS="${DP_LDFLAGS}" ./configure \
        --with-config-file-path="${DP_PHP_INI_DIR}" \
        --with-config-file-scan-dir="${DP_PHP_INI_DIR}/conf.d" \
        --enable-option-checking=fatal \
        ${DP_PHP_CONFIGURE_OPTIONS} \
 &&   make -j"$(nproc)" \
 &&   make install \
 && cd -

# Generate rootfs
COPY --chmod=755 "dependency_resolve/dependency_resolve" "/usr/local/bin/dependency_resolve"
RUN dependency_resolve \
      "/usr/bin/ldd" \
        ${DP_PHP_SAPIS} \
        $(find "$(php-config --extension-dir)" -type f) \
    | xargs -I {} sh -c 'mkdir -p /rootfs/$(dirname "{}") && cp -apP "{}" /rootfs/{}' \
 && find "/rootfs" -type f -print0 | xargs -0 -n 1 sh -c 'strip --strip-all "$0" || true'

FROM --platform="linux/${ARCH}" busybox:latest AS busybox

FROM --platform="linux/${ARCH}" gcr.io/distroless/base-nossl-debian12

COPY --from=busybox "/bin/busybox" "/bin/busybox"
RUN ["/bin/busybox", "--install", "-s"]

COPY --from=base "/rootfs" "/"

USER nonroot

ENTRYPOINT ["/bin/sh"]
