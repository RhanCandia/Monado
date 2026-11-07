#!/usr/bin/env bash
# Compile recompiled game code (generated/{main,sdk}/*.c) into build/obj/{main,sdk}/*.o on Linux using Clang.
set -e
cd "$(dirname "$0")/.."

CC=${CC:-clang}
JOBS=${JOBS:-$(nproc)}
CF="-O1 -march=x86-64-v2 -ffp-contract=off -fno-strict-aliasing -fvisibility=hidden -Iruntime -w"

mkdir -p build/obj/main build/obj/sdk

# Drop objects whose chunk no longer exists
for o in build/obj/*/*.o; do
  [ -f "$o" ] || continue
  m=$(basename "$(dirname "$o")")
  b=$(basename "$o" .o)
  [ -f "generated/$m/$b.c" ] || rm -f "$o"
done

echo "Compiling game objects with $JOBS parallel jobs..."

cc1() {
  f="$1"
  m=$(basename "$(dirname "$f")")
  b=$(basename "$f" .c)
  o="build/obj/$m/$b.o"
  if [ ! -f "$o" ] || [ "$f" -nt "$o" ]; then
    $CC -c "$f" -o "$o" $CF || { echo "FAIL $f"; exit 1; }
  fi
}
export -f cc1
export CC CF

ls generated/main/*.c generated/sdk/*.c | xargs -P "$JOBS" -I{} bash -c 'cc1 "$@"' _ {}

echo "All game objects compiled in build/obj/"
