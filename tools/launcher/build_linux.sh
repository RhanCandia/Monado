#!/usr/bin/env bash
# Build the launcher on Linux: build/xcde_launcher (SDL3 + Dear ImGui, SDL renderer).
set -e
cd "$(dirname "$0")/../.."
CXX=${CXX:-g++}
I=third_party/imgui
SDL_CFLAGS=$(pkg-config --cflags sdl3 2>/dev/null || echo "-I/usr/include/SDL3")
SDL_LIBS=$(pkg-config --libs sdl3 2>/dev/null || echo "-lSDL3")

mkdir -p build/launcher
for f in $I/imgui.cpp $I/imgui_draw.cpp $I/imgui_tables.cpp $I/imgui_widgets.cpp \
         $I/backends/imgui_impl_sdl3.cpp $I/backends/imgui_impl_sdlrenderer3.cpp \
         tools/launcher/launcher.cpp; do
  o=build/launcher/$(basename ${f%.cpp}).o
  if [ "$f" -nt "$o" ] || [ ! -f "$o" ]; then
    echo "  CXX $f"
    $CXX -c "$f" -o "$o" -O2 -march=x86-64-v2 -std=c++17 -I$I -I$I/backends $SDL_CFLAGS -w
  fi
done

echo "  LINK build/xcde_launcher"
$CXX -o build/xcde_launcher build/launcher/*.o $SDL_LIBS -march=x86-64-v2 -lpthread
echo "Done: build/xcde_launcher"
