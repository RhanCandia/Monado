# Building Monado on Linux

This guide describes how to build, package, and run Monado (Xenoblade Chronicles: Definitive Edition Recompiler) natively on Linux.

---

## Table of Contents
1. [Quick Start (Docker)](#quick-start-docker)
2. [Native Build Prerequisites](#native-build-prerequisites)
   - [Arch Linux](#arch-linux--manjaro)
   - [Ubuntu / Debian](#ubuntu--debian)
   - [Fedora](#fedora)
   - [Vulkan Memory Allocator (VMA)](#vulkan-memory-allocator-vma)
   - [Python Dependencies](#python-dependencies)
3. [Game Files Setup](#game-files-setup)
4. [Building Monado](#building-monado)
   - [Automated Build](#automated-build)
   - [Individual Build Steps](#individual-build-steps)
5. [Packaging AppImage](#packaging-appimage)
6. [Running the Game & Launcher](#running-the-game--launcher)
7. [Troubleshooting & FAQs](#troubleshooting--faqs)

---

## Quick Start (Docker)

If you have Docker installed, you can build Monado and package the AppImage in a clean Arch Linux container without manually configuring local packages:

```bash
# 1. Build the container image
docker build -t monado-build .

# 2. Build Monado (runtime, Vulkan backend, recompiled game code, and launcher)
docker run --rm -v "$PWD:/monado" -w /monado -u $(id -u):$(id -g) monado-build bash -c "scripts/build_linux.sh"

# Steam Deck build:
# docker run --rm -v "$PWD:/monado" -w /monado -u $(id -u):$(id -g) monado-build bash -c "scripts/build_linux.sh --steamdeck"

# 3. (Optional) Generate the standalone AppImage
docker run --rm -v "$PWD:/monado" -w /monado -u $(id -u):$(id -g) monado-build bash -c "scripts/make_appimage.sh"
# Or pass --steamdeck (or --appimage to scripts/build_linux.sh):
# docker run --rm -v "$PWD:/monado" -w /monado -u $(id -u):$(id -g) monado-build bash -c "scripts/make_appimage.sh --steamdeck"
```

The resulting binaries will be placed in `build/` (`xcde`, `xcde_launcher`), and the AppImage in the repository root (`Monado-x86_64.AppImage` or `Monado-x86_64-steamdeck.AppImage` when targeting Steam Deck).

---

## Native Build Prerequisites

To build directly on your host Linux system, install the required toolchains and libraries:

* **Compiler:** Clang 16+ & Clang++ (supporting C++17)
* **Python:** Python 3.10+ (with `capstone`, `unicorn`, `lz4`)
* **Libraries:**
  * SDL3 (`libsdl3`)
  * Vulkan loader & headers (`vulkan-icd-loader`, `vulkan-headers`)
  * Shaderc (`libshaderc`)
  * FFmpeg (development libraries: `avcodec`, `avformat`, `avutil`, `swscale`, `swresample`)
  * Opus (`libopus`)
  * zlib
  * pkg-config

### Arch Linux / Manjaro

```bash
sudo pacman -S --needed base-devel clang llvm cmake ninja git pkgconf \
    python python-pip sdl3 vulkan-headers vulkan-icd-loader shaderc \
    ffmpeg opus zlib wget file
```

### Ubuntu / Debian

On Ubuntu 24.04 or Debian testing/unstable:

```bash
sudo apt update
sudo apt install -y build-essential clang llvm cmake ninja-build git pkg-config \
    python3 python3-pip libvulkan-dev vulkan-tools libshaderc-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
    libopus-dev zlib1g-dev wget file
```

> [!NOTE]
> If your distribution does not yet package SDL3, build and install SDL3 from source:
> ```bash
> git clone https://github.com/libsdl-org/SDL.git -b main --depth 1
> cmake -S SDL -B SDL/build -DCMAKE_BUILD_TYPE=Release
> cmake --build SDL/build -j$(nproc)
> sudo cmake --install SDL/build
> ```

### Fedora

```bash
sudo dnf install -y clang llvm cmake ninja-build git pkgconf-pkg-config \
    python3 python3-pip vulkan-headers vulkan-loader-devel libshaderc-devel \
    ffmpeg-free-devel opus-devel zlib-devel wget file
```

### Vulkan Memory Allocator (VMA)

The NVN Vulkan renderer uses the header-only VulkanMemoryAllocator. If not present in your system include path, install it to `/usr/include`:

```bash
sudo wget -q -O /usr/include/vk_mem_alloc.h \
  https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/master/include/vk_mem_alloc.h
```

### Python Dependencies

The recompiler lifter and code generator (`tools/gen_all.py`) require the following Python libraries:

```bash
pip install --break-system-packages capstone unicorn lz4
# or inside a virtualenv:
# python3 -m venv .venv && source .venv/bin/activate && pip install capstone unicorn lz4
```

---

## Game Files Setup

Monado runs directly from your legally dumped game files (version 2.0.0). Place or symlink your dump into the repository root:

```
Monado/
├── target/ (or targets/)
│   ├── exefs/
│   │   ├── main
│   │   ├── subsdk0
│   │   └── ...
│   └── romfs/
│       ├── bdat/
│       ├── chr/
│       └── ...
```

Verify your game dump integrity with:
```bash
python3 tools/extract/check_dump.py target
```

---

## Building Monado

### Automated Build

The easiest way to build everything is to execute `scripts/build_linux.sh`:

```bash
./scripts/build_linux.sh
```

For **Steam Deck** builds (disables AMD DCC lean format restrictions to prevent pink/magenta texture artifacts):
```bash
./scripts/build_linux.sh --steamdeck
```

You can also pass `--appimage` to build and package in a single step:
```bash
./scripts/build_linux.sh --steamdeck --appimage
```

This automated script will:
1. Detect `target/exefs` or `targets/exefs`.
2. Generate recompiled C source code in `generated/` (if not already generated).
3. Compile all recompiled game chunks in parallel (`build/obj/`).
4. Compile the Monado runtime, NVN Vulkan renderer, and Dear ImGui Vulkan backend (`build/rt/`, `build/nvn/`).
5. Link the main game executable `build/xcde`.
6. Compile and link the GUI launcher `build/xcde_launcher`.

### Individual Build Steps

If modifying specific components, you can invoke the individual build stages:

```bash
# 1. Compile game objects (generated/{main,sdk}/*.c)
./scripts/build_game_linux.sh

# 2. Compile runtime and Vulkan renderer
./scripts/build_rt_linux.sh

# 3. Link the game executable (build/xcde)
./scripts/link_gfx_linux.sh

# 4. Build the graphical settings launcher (build/xcde_launcher)
./tools/launcher/build_linux.sh
```

---

## Packaging AppImage

To bundle Monado and all its runtime dependencies (FFmpeg, SDL3, Opus, shaderc, bundled fonts, desktop entry, and icons) into a single portable binary:

```bash
# Generic Linux build:
./scripts/make_appimage.sh

# Steam Deck build:
./scripts/make_appimage.sh --steamdeck
```

> [!TIP]
> If you previously built using `./scripts/build_linux.sh --steamdeck`, running `./scripts/make_appimage.sh` automatically detects the Steam Deck target tag and creates `Monado-x86_64-steamdeck.AppImage`.

The resulting AppImage is created directly in the repository root:
* Generic Linux: `Monado-x86_64.AppImage`
* Steam Deck: `Monado-x86_64-steamdeck.AppImage`

---

## Running the Game & Launcher

### Using the AppImage

```bash
# Run the game directly (automatically detects target/ or targets/ in current directory):
./Monado-x86_64.AppImage

# Start the game pointing to an external game directory:
./Monado-x86_64.AppImage /path/to/game_dump

# Open the graphical settings launcher:
./Monado-x86_64.AppImage --launcher

# View help and command-line options:
./Monado-x86_64.AppImage --help
```

### Running Native Binaries Directly

```bash
# Start via the launcher:
./build/xcde_launcher

# Or run the game directly:
./build/xcde target
```

### In-Game Overlay Menu

* Press **F1** or controller **Minus + Plus** (Back + Start) anytime during gameplay to open the in-game settings overlay.
* Press **Esc** or **F1** again to close the menu and return to the game.
* Changes can be applied live and saved directly to `xcde.ini`.

---

## Troubleshooting & FAQs

### Font Rendering / "Could not load font file!" Assertion
Both the in-game **F1** menu and the settings launcher use Dear ImGui. Fonts are resolved in the following priority:
1. Bundled AppImage font (`usr/share/fonts/Roboto-Medium.ttf`).
2. Repository fonts (`third_party/imgui/misc/fonts/Roboto-Medium.ttf`).
3. Standard Linux system fonts (DejaVu Sans, Noto Sans, Liberation Sans, Adwaita Sans, FreeSans, Ubuntu).
4. Dear ImGui's built-in bitmap default font (`AddFontDefault`).

The launcher and menu verify font file availability before loading, avoiding any assertion aborts on headless or custom environments.

### Running AppImage Without FUSE (e.g. Docker, LXC, Containers)
If your environment lacks `/dev/fuse` or `fusermount`, run the AppImage with:
```bash
./Monado-x86_64.AppImage --appimage-extract-and-run [options]
```

### Precompiling Shaders
On the first game launch, shader precompilation is strongly recommended to eliminate runtime stutter:
* In the launcher, click **Precompilar shaders** (or let **JUGAR** perform it automatically).
* Or from the terminal:
  ```bash
  ./build/xcde --precompile target
  # or via AppImage:
  ./Monado-x86_64.AppImage --game --precompile target
  ```
Precompiled SPIR-V shaders are cached in `cache/spirv/`.
