#!/usr/bin/env bash
# Build Monado runtime and NVN Vulkan renderer on Linux using Clang.
set -e
cd "$(dirname "$0")/.."

CC=${CC:-clang}
CXX=${CXX:-clang++}
PYTHON=${PYTHON:-python3}

STEAMDECK=0
for arg in "$@"; do
  case "$arg" in
    --steamdeck|--deck)
      STEAMDECK=1
      ;;
  esac
done

TARGET_TAG="linux_generic"
if [ "$STEAMDECK" = "1" ]; then
  TARGET_TAG="steamdeck"
  echo "Target configuration: Steam Deck (XCDE_TARGET_STEAMDECK)"
fi

mkdir -p build/rt build/nvn build/inc

# Invalidate textures object if the target mode changed
TARGET_TAG_FILE="build/.target_tag"
if [ -f "$TARGET_TAG_FILE" ]; then
  PREV_TAG=$(cat "$TARGET_TAG_FILE" 2>/dev/null || true)
  if [ "$PREV_TAG" != "$TARGET_TAG" ]; then
    echo "  Target mode changed ($PREV_TAG -> $TARGET_TAG): rebuilding textures.o..."
    rm -f build/nvn/nvn_vulkan_textures.o
  fi
fi
echo "$TARGET_TAG" > "$TARGET_TAG_FILE"

EXTRA_TARGET_FLAGS=""
if [ "$STEAMDECK" = "1" ]; then
  EXTRA_TARGET_FLAGS="-DXCDE_TARGET_STEAMDECK"
fi

CF="-O1 -march=x86-64-v2 -fno-strict-aliasing -fvisibility=hidden -fdeclspec -Iruntime -Iruntime/nvn -Ithird_party -w $EXTRA_TARGET_FLAGS"
CXXF="-std=c++17 -O1 -march=x86-64-v2 -fvisibility=hidden -fdeclspec -Iruntime -Iruntime/nvn -Iruntime/nvn/vulkan -Ithird_party/imgui -Ithird_party/imgui/backends -w $EXTRA_TARGET_FLAGS"

RT="loader dispatch kernel ipc fnprof platform/linux services/fs services/romfs_virtual services/am services/acc services/time \
    services/hid_set services/kbicons services/misc services/audio services/hwopus hle/heaps hle/pl hle/vi hle/nvn_boot hle/fibers hle/input hle/party \
    hle/bindings hle/movie hle/framepace host/stubs host/settings_ini host/stubs_gfx host/gamelib_static host/main_boot diag/diag diag/sampler diag/watchdog \
    diag/crashdump"

NVN="astc cmdbuf formats maxwell/translate objects output_scale smaa_data tegra texpatch vulkan/device vulkan/exec vulkan/precompile vulkan/shaders vulkan/textures vulkan/temporal"

mkdir -p build/rt build/nvn build/inc

echo "=== Building Runtime objects ==="
for f in $RT; do
  o=build/rt/$(echo $f | tr / _).o
  extra=""
  if [ "$f" = "host/main_boot" ]; then
    o=build/rt/host_main_boot_gfx.o
    extra="-DXCDE_GFX"
  fi
  src="runtime/$f.c"
  if [ "$src" -nt "$o" ] || [ ! -f "$o" ]; then
    echo "  CC $src -> $o"
    $CC -c "$src" -o "$o" $CF -DGAMELIB_ID='"dev"' $extra
  fi
done

echo "=== Building NVN objects ==="
for f in $NVN; do
  o=build/nvn/nvn_$(echo $f | tr / _).o
  extra=""
  if [ "$f" = "smaa_data" ]; then
    if [ ! -f build/inc/smaa_hlsl.inc ]; then
      $PYTHON tools/gen_smaa_inc.py third_party/smaa/SMAA.hlsl build/inc/smaa_hlsl.inc
    fi
    extra="-Ibuild/inc -Ithird_party/smaa/Textures"
  fi
  src="runtime/nvn/$f.c"
  if [ "$src" -nt "$o" ] || [ ! -f "$o" ]; then
    echo "  CC $src -> $o"
    $CC -c "$src" -o "$o" $CF -DGAMELIB_ID='"dev"' $extra
  fi
done

echo "=== Building ImGui UI & Vulkan Glue ==="
I=third_party/imgui
for f in $I/imgui.cpp $I/imgui_draw.cpp $I/imgui_tables.cpp $I/imgui_widgets.cpp \
         $I/backends/imgui_impl_vulkan.cpp runtime/nvn/vulkan/imgui_glue.cpp runtime/ui/menu_vk.cpp; do
  o=build/nvn/ui_$(basename ${f%.cpp}).o
  if [ "$f" -nt "$o" ] || [ ! -f "$o" ]; then
    echo "  CXX $f -> $o"
    $CXX -c "$f" -o "$o" $CXXF
  fi
done

echo "=== Building Vulkan Memory Allocator & Paths ==="
if [ "runtime/nvn/vulkan/vma.cpp" -nt "build/nvn/vma.o" ] || [ ! -f "build/nvn/vma.o" ]; then
  echo "  CXX runtime/nvn/vulkan/vma.cpp"
  $CXX -c runtime/nvn/vulkan/vma.cpp -o build/nvn/vma.o -std=c++17 -O1 -march=x86-64-v2 -fvisibility=hidden -w
fi

if [ "runtime/nvn/vulkan/dlss.cpp" -nt "build/nvn/nvn_vulkan_dlss.o" ] || [ ! -f "build/nvn/nvn_vulkan_dlss.o" ]; then
  echo "  CXX runtime/nvn/vulkan/dlss.cpp"
  $CXX -c runtime/nvn/vulkan/dlss.cpp -o build/nvn/nvn_vulkan_dlss.o -std=c++17 -O1 -march=x86-64-v2 -fvisibility=hidden -Iruntime -Iruntime/nvn -w
fi

if [ "runtime/paths.c" -nt "build/nvn/paths.o" ] || [ ! -f "build/nvn/paths.o" ]; then
  echo "  CC runtime/paths.c"
  $CC -c runtime/paths.c -o build/nvn/paths.o $CF -DGAMELIB_ID='"dev"'
fi

echo "Runtime build complete."
