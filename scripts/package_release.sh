#!/usr/bin/env bash
# [XCDE] Package Monado release archive: AppImage, data/, portable cache (SPIR-V pack + variants), and targets/
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo "dev")}"
OUT_DIR="build/release"
STAGING_DIR="build/release_staging/Monado"

echo "=== Packaging Monado Release: $VERSION ==="
mkdir -p "$OUT_DIR"
rm -rf "build/release_staging"
mkdir -p "$STAGING_DIR"

# 1. AppImage
if [ ! -f "Monado-x86_64.AppImage" ]; then
  if [ -f "build/xcde" ] && [ -f "build/xcde_launcher" ]; then
    echo "Creating AppImage..."
    scripts/make_appimage.sh
  else
    echo "Error: Monado-x86_64.AppImage not found and binaries missing in build/"
    exit 1
  fi
fi
cp -p "Monado-x86_64.AppImage" "$STAGING_DIR/"
chmod +x "$STAGING_DIR/Monado-x86_64.AppImage"

# 2. data/
mkdir -p "$STAGING_DIR/data"
if [ -f "data/variants_seed.bin" ]; then
  cp -p "data/variants_seed.bin" "$STAGING_DIR/data/"
fi

# 3. cache/ (only sharable portable files: spirv.pack, spirv.idx, variants.bin)
mkdir -p "$STAGING_DIR/cache"
[ -f "cache/spirv.pack" ] && cp -p "cache/spirv.pack" "$STAGING_DIR/cache/"
[ -f "cache/spirv.idx" ] && cp -p "cache/spirv.idx" "$STAGING_DIR/cache/"
[ -f "cache/variants.bin" ] && cp -p "cache/variants.bin" "$STAGING_DIR/cache/"

# 4. targets/ placeholder with instructions
mkdir -p "$STAGING_DIR/targets"
cat > "$STAGING_DIR/targets/PUT_GAME_FILES_HERE.txt" << 'EOF'
Place your legally dumped game files (Xenoblade Chronicles: Definitive Edition v2.0.0) in this folder:

targets/
├── exefs/
│   ├── main
│   ├── subsdk0
│   └── ...
└── romfs/
    ├── bdat/
    ├── chr/
    └── ...

Once placed, run ./Monado-x86_64.AppImage or open the launcher with ./Monado-x86_64.AppImage --launcher.
EOF

# 5. Default configuration
[ -f "xcde.ini" ] && cp -p "xcde.ini" "$STAGING_DIR/"

# 6. Compress to .tar.xz
ARCHIVE_NAME="Monado-${VERSION}-linux-x86_64.tar.xz"
echo "Compressing into $OUT_DIR/$ARCHIVE_NAME (xz -T0)..."
tar -cf - -C "build/release_staging" "Monado" | xz -T0 -6 > "$OUT_DIR/$ARCHIVE_NAME"

# 7. Checksums and standalone AppImage copy
cd "$OUT_DIR"
sha256sum "$ARCHIVE_NAME" > "SHA256SUMS.txt"
cp -p "../../Monado-x86_64.AppImage" "./"
sha256sum "Monado-x86_64.AppImage" >> "SHA256SUMS.txt"
cd - > /dev/null

echo "Release package created:"
ls -lh "$OUT_DIR"
echo "Archive contents preview:"
tar -tvf "$OUT_DIR/$ARCHIVE_NAME"
