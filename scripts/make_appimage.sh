#!/usr/bin/env bash
# Package Monado as an AppImage.
set -e
cd "$(dirname "$0")/.."

APPDIR="build/AppDir"
CUSTOM_OUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output)
      CUSTOM_OUT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "$CUSTOM_OUT" ]; then
  OUT="$CUSTOM_OUT"
elif [ -n "$APPIMAGE_OUT" ]; then
  OUT="$APPIMAGE_OUT"
else
  OUT="Monado-x86_64.AppImage"
fi

echo "=== Packaging AppImage: $OUT ==="

echo "=== Preparing AppDir ==="
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/fonts" "$APPDIR/usr/share/icons/hicolor/scalable/apps"

# Copy binaries
[ -f "build/xcde" ] || { echo "Error: build/xcde not found. Run scripts/build_linux.sh first."; exit 1; }
[ -f "build/xcde_launcher" ] || { echo "Error: build/xcde_launcher not found. Run scripts/build_linux.sh first."; exit 1; }

cp "build/xcde" "$APPDIR/usr/bin/"
cp "build/xcde_launcher" "$APPDIR/usr/bin/"

# Copy font
if [ -f "third_party/imgui/misc/fonts/Roboto-Medium.ttf" ]; then
  cp "third_party/imgui/misc/fonts/Roboto-Medium.ttf" "$APPDIR/usr/share/fonts/"
fi

# Copy desktop file and icons
cp "tools/launcher/monado.desktop" "$APPDIR/"
cp "tools/launcher/monado.svg" "$APPDIR/"
if [ -f "tools/launcher/monado.png" ]; then
  cp "tools/launcher/monado.png" "$APPDIR/.DirIcon"
  cp "tools/launcher/monado.png" "$APPDIR/"
fi
cp "tools/launcher/monado.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
[ -f "tools/launcher/monado.png" ] && cp "tools/launcher/monado.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/"

# Copy AppRun
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export APPDIR="${HERE}"
export OWD="${OWD:-$(pwd)}"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS}"

find_target() {
  if [ -d "targets/exefs" ]; then
    echo "targets"
  elif [ -d "target/exefs" ]; then
    echo "target"
  elif [ -d "dump/exefs" ]; then
    echo "dump"
  else
    echo "targets"
  fi
}

case "$1" in
  --help|-h)
    echo "Monado - Xenoblade Chronicles Definitive Edition Recompiler"
    echo "Usage:"
    echo "  $0                  Start the game"
    echo "  $0 <path_to_game>   Start the game with custom game path"
    echo "  $0 --launcher       Launch graphical settings launcher"
    echo "  $0 --game [path]    Start the game directly"
    exit 0
    ;;
  --launcher)
    shift
    exec "${HERE}/usr/bin/xcde_launcher" "$@"
    ;;
  --game)
    shift
    if [ "$#" -gt 0 ]; then
      exec "${HERE}/usr/bin/xcde" "$@"
    else
      T="$(find_target)"
      exec "${HERE}/usr/bin/xcde" "$T"
    fi
    ;;
  *)
    if [ "$#" -gt 0 ]; then
      exec "${HERE}/usr/bin/xcde" "$@"
    else
      T="$(find_target)"
      exec "${HERE}/usr/bin/xcde" "$T"
    fi
    ;;
esac
EOF
chmod +x "$APPDIR/AppRun"

echo "=== Bundling required shared libraries ==="
# Helper to copy dependent libraries (excluding basic system libc/libm/libdl/libpthread)
copy_lib() {
  local bin=$1
  ldd "$bin" | grep "=>" | awk '{print $3}' | while read -r lib; do
    [ -f "$lib" ] || continue
    base=$(basename "$lib")
    case "$base" in
      libc.so*|libm.so*|libpthread.so*|libdl.so*|libresolv.so*|librt.so*|ld-linux*)
        # Keep glibc libraries from host system
        ;;
      libGL*|libEGL*|libvulkan.so*|libdrm*|libX*|libxcb*|libwayland*)
        # Keep graphics driver / display server libraries from host system
        ;;
      *)
        if [ ! -f "$APPDIR/usr/lib/$base" ]; then
          cp -L "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
        fi
        ;;
    esac
  done
}

copy_lib "build/xcde"
copy_lib "build/xcde_launcher"

echo "Bundled libraries:"
ls -lh "$APPDIR/usr/lib"

# Get appimagetool if not present
if [ ! -f "build/appimagetool" ]; then
  echo "Downloading appimagetool..."
  wget -q -O "build/appimagetool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" || true
  chmod +x "build/appimagetool" 2>/dev/null || true
fi

if [ -f "build/appimagetool" ]; then
  echo "Generating AppImage..."
  ARCH=x86_64 build/appimagetool --appimage-extract-and-run "$APPDIR" "$OUT"
  echo "AppImage created: $OUT"
else
  echo "Notice: appimagetool could not be downloaded in this environment."
  echo "AppDir structure is ready in $APPDIR"
fi
