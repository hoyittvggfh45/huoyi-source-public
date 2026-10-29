#!/bin/sh
set -e
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${1:-/tmp/libquickjs.so}
CC=${CC:-cc}
"$CC" -shared -fPIC -O2 -D_GNU_SOURCE -DCONFIG_VERSION='"2024-01-13"' -o "$OUT" "$DIR/quickjs.c" "$DIR/libregexp.c" "$DIR/libunicode.c" "$DIR/cutils.c" "$DIR/libbf.c" -lm -ldl
