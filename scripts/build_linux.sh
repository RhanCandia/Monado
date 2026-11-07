#!/usr/bin/env bash
# Build Monado (XCDE) on Linux: runtime, Vulkan renderer, launcher, and recompiled game code if present.
set -e
cd "$(dirname "$0")/.."

BUILD_APPIMAGE=0
for arg in "$@"; do
  case "$arg" in
    --appimage)
      BUILD_APPIMAGE=1
      ;;
  esac
done

# Check if game files are present
if [ -d "target/exefs" ]; then
  [ -e targets ] || ln -s target targets
elif [ -d "targets/exefs" ]; then
  [ -e target ] || ln -s targets target
elif [ -d "dump/exefs" ]; then
  [ -e target ] || ln -s dump target
  [ -e targets ] || ln -s target targets
fi

TARGET_DIR="target"
[ -d "$TARGET_DIR/exefs" ] || TARGET_DIR="targets"

if [ -d "$TARGET_DIR/exefs" ]; then
  if [ ! -d "generated/main" ]; then
    echo "=== Generating recompiled game C code from $TARGET_DIR/exefs ==="
    python3 -X utf8 tools/gen_all.py --profile games/xcde/profile.json --exefs "$TARGET_DIR/exefs" --out generated
  fi
  echo "=== Compiling recompiled game objects ==="
  scripts/build_game_linux.sh
fi

echo "=== Building Monado Runtime & NVN Vulkan Backend ==="
scripts/build_rt_linux.sh

echo
echo "=== Linking Monado (build/xcde) ==="
scripts/link_gfx_linux.sh

echo
echo "=== Building Monado Launcher (build/xcde_launcher) ==="
tools/launcher/build_linux.sh

echo
echo "Build complete: build/xcde and build/xcde_launcher ready."

if [ "$BUILD_APPIMAGE" = "1" ]; then
  echo
  scripts/make_appimage.sh
fi
