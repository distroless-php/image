ARG ARCH="arm64/v8"
ARG BASE_IMAGE
ARG DEBIAN_VERSION

FROM --platform="linux/${ARCH}" busybox:latest AS busybox

FROM --platform="linux/${ARCH}" ${BASE_IMAGE} AS base
RUN distroless_php_add_binary "/usr/local/sbin/php-fpm" $(find "$(php-config --extension-dir)" -type f)

FROM --platform="linux/${ARCH}" gcr.io/distroless/base-nossl-debian${DEBIAN_VERSION}:latest

COPY --from=busybox "/bin/busybox" "/bin/busybox"
RUN ["/bin/busybox", "rm", "-rf", "/usr/lib"]
RUN ["/bin/busybox", "--install", "-s"]

COPY --from=base "/rootfs" "/"

USER nonroot

ENTRYPOINT ["/usr/local/sbin/php-fpm"]
