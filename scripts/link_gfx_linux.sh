#!/usr/bin/env bash
# Link Monado (XCDE) on Linux.
set -e
cd "$(dirname "$0")/.."

CC=${CC:-clang}
CXX=${CXX:-clang++}
OUT="${XCDE_EXE:-build/xcde}"

RT="build/rt/loader.o build/rt/dispatch.o build/rt/kernel.o build/rt/ipc.o build/rt/fnprof.o build/rt/platform_linux.o \
 build/rt/services_fs.o build/rt/services_romfs_virtual.o build/rt/services_am.o build/rt/services_acc.o build/rt/services_time.o \
 build/rt/services_hid_set.o build/rt/services_kbicons.o build/rt/services_misc.o build/rt/hle_heaps.o build/rt/hle_pl.o build/rt/hle_vi.o build/rt/hle_nvn_boot.o build/rt/hle_fibers.o \
 build/rt/host_stubs.o build/rt/host_settings_ini.o build/rt/host_stubs_gfx.o build/rt/services_audio.o build/rt/services_hwopus.o build/rt/hle_input.o build/rt/hle_party.o build/rt/hle_bindings.o build/rt/hle_movie.o build/rt/hle_framepace.o build/rt/host_main_boot_gfx.o build/rt/diag_diag.o build/rt/diag_sampler.o build/rt/diag_watchdog.o build/rt/diag_crashdump.o"

# If game objects exist in build/obj/, link statically with host_gamelib_static.o;
# otherwise link with gamelib.o (which dlopen()s lasgame.so at runtime).
if ls build/obj/main/*.o 1> /dev/null 2>&1; then
  GAME_OBJS="build/rt/host_gamelib_static.o build/obj/main/*.o build/obj/sdk/*.o"
else
  $CC -c runtime/gamelib.c -o build/rt/gamelib.o -O1 -march=x86-64-v2 -fno-strict-aliasing -fvisibility=hidden -Iruntime -w -DGAMELIB_ID='"dev"'
  GAME_OBJS="build/rt/gamelib.o"
fi

NVN="$(ls build/nvn/*.o | tr '\n' ' ')"

LIBS="-lSDL3 -lshaderc_shared -lvulkan -lopus -lavcodec -lavformat -lavutil -lswscale -lswresample -lz -lpthread -ldl -lm"

echo "  LINK $OUT"
$CXX -o "$OUT" $RT $NVN $GAME_OBJS -march=x86-64-v2 $LIBS -rdynamic
echo "Linked: $OUT"
