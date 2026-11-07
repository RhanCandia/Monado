# Monado

> [!IMPORTANT]
> **This project was made almost entirely with AI.** Nearly all of the code, tooling, reverse engineering and
> documentation was written by an AI (Anthropic's Claude, through Claude Code), directed, tested and reviewed by a
> human. It is shared as is, in the hope that someone takes it further. You run it at your own discretion.

**Monado** is a static recompilation of *Xenoblade Chronicles: Definitive Edition* (Nintendo Switch, 2020) into a
native Windows x86-64 application with a Vulkan renderer. It is **not an emulator**: the game's ARM64 code is
translated ahead of time into C and compiled for your PC, and the console's operating system and graphics API (NVN)
are reimplemented on top of Windows and Vulkan.

It is built on [LASRecomp](https://github.com/peiikai/LASRecomp) (MIT), the static recompilation of *Link's
Awakening*, whose generator and runtime it adapts. Internally the project still uses its working name **XCDE**
(`build/xcde.exe`, `XCDE_*` environment variables, `[XCDE]` marks in the code).

> [!NOTE]
> **No game files are included.** You need your own legally obtained copy of the game, **version 2.0.0** (the base
> game with the 2.0.0 update applied), extracted to an `exefs` folder and a `romfs` folder. Instructions on how to
> obtain or extract these files will **not** be provided. Everything derived from the game (the recompiled code,
> translated shaders, caches) is generated on your own machine and never belongs in this repository.

## Status

The whole game is playable on Windows with an NVIDIA RTX GPU: the story, battles, side quests, Heart-to-Hearts,
*Future Connected*, menus, cutscenes and videos with audio. The original developer considers it finished for their own
PC and is looking for someone to continue it, above all on **AMD, Intel and lower-end hardware**, which are largely
untested. See [Known issues](#known-issues) and [Where the knowledge is](#where-the-knowledge-is).

## Features

**Graphics**
- Internal resolution: match the window (default), 1x–3x the Switch's image (up to 4K), 75 % / 50 % of the window, or
  dynamic resolution that follows performance. Ultrawide windows keep their shape.
- Upscaling and anti-aliasing:
  - spatial: AMD FSR 1.0;
  - temporal: AMD FSR 3.1 or NVIDIA DLSS (with native-AA / DLAA modes);
  - extra: SMAA.
- FSR 3 frame generation, everywhere or only in cutscenes (an even 60 on screen for scenes the game animates at 30).
- Toggles for the game's own depth of field, temporal AA and motion blur (tuned for the Switch's 720p).

**Frame rate**
- 30 / 60 / 120 / 144 / 165 / unlimited without changing the speed of the world, the clock or cutscenes.
- Optional steady-30 cutscenes and V-Sync.

**Controls**
- Keyboard and mouse in an MMO-style layout: mouse camera, keys 1–8 + T fire the arts in the palette.
- Every key, mouse button and controller button can be remapped.
- Button prompts drawn from your own key bindings. Xbox / PlayStation icon packs (third-party, from GameBanana, not
  included) are picked by the connected controller.
- Configurable stick dead zone for controllers with drift.
- Xenoblade 3-style party switching (hold L2, press L1 / R1) in the field and in battle.

**Robustness**
- **Shader precompilation:** a seed of ~30,000 pipeline variants built ahead of time, so the first visit to an area
  doesn't stop to compile. The SPIR-V cache is a single file (`cache/spirv.pack`).
- **Safe saves:** the game's save commits are honoured with a journal, so a crash in the middle of a save rolls back
  to the last good one. Every session keeps an automatic backup (`save/backup/`, the newest 5).
- **Diagnostics:** crash reports with minidumps, a hang watchdog, and a launcher button that zips the logs for a bug
  report.
- **Low-end aware:** RAM size, integrated GPUs and core count are detected, and caches, budgets and thread counts are
  scaled to them. The target is a Ryzen 3 3200G (Vega 8) with 8 GB at 720p.

**Launcher and mods**
- A launcher (English / Spanish) for every setting, the shader precompilation and the bug report.
- Mods: romfs mods in `mods/<name>/romfs/` (the same layout as Ryujinx / yuzu). Code mods (exefs, IPS / pchtxt) don't
  apply to a recompilation.

## Requirements

- **OS:** Windows 10 / 11, x86-64 (x86-64-v2: SSE4.2, no AVX needed).
- **GPU:** Vulkan 1.3.
  - **Tested:** NVIDIA RTX.
  - **Not verified on real hardware:** AMD and Intel (including iGPUs). Fixes are in place, but reports are welcome.
- **RAM:** 8 GB minimum (tight), 16 GB recommended. The game's own heap is 3.2 GB; see Known issues.
- **Disk:** ~15 GB for the game files, ~5 GB for the build, plus caches.
- **Your game files:** see the next section.

## Game files: what and where

You need the game's own files, from your own copy of Xenoblade Chronicles: Definitive Edition. Instructions on how
to obtain them are **not** provided.

**Format:** plain extracted folders, not packages. An `.nsp`, `.xci` or `.nca` is refused: those are game
packages, not game files.

**Version:** exactly 2.0.0 (title ID `0100ff500e34a000`). This means the base game with the 2.0.0 update applied:
- `exefs` is the update's: its `main` is the 2.0.0 one;
- `romfs` is the base romfs with the update's files laid over it.

The base game alone (1.0.0) does not work: the recompiled code is the 2.0.0 `main`.

**Layout:** one folder holding both:
```
<any folder>/
├── exefs/
│   ├── main          (the game; build-id 7e1df8e08d60544b)
│   ├── main.npdm
│   ├── rtld
│   ├── sdk           (build-id ad3fdfbd62a5f4b0)
│   └── subsdk0
└── romfs/            (18,529 files, 13.6 GB)
    ├── bdat/
    ├── chr/
    ├── ...
```

**Where:** anywhere on your disk.
- With `Build Monado.bat`, you pick that folder and it links `targets\exefs` and `targets\romfs` to it. Nothing is
  copied, and the folder you pick may also be a few levels above `exefs`/`romfs`.
- By hand, put (or link) them at `targets/exefs/` and `targets/romfs/` in this repository.

`tools/extract/check_dump.py targets` verifies them:
- the exefs, by build-id;
- the romfs, against a per-folder manifest of names and sizes.

If it fails, it says which files are missing or different. It reports a wrong version (a 1.0.0 `main`, for
example) separately.

## Building

The build runs the recompiler on your machine, from your own game files. It takes 10–20 minutes the first time and
~5 GB of disk.

> [!NOTE]
> Building on Linux? See [BUILD_LINUX.md](BUILD_LINUX.md) for full Linux build, Docker container, and AppImage instructions.

You need [Git for Windows](https://git-scm.com/download/win) for Windows builds (the build scripts run in Git Bash).

### The easy way: `Build Monado.bat`

Run `Build Monado.bat` from the repository root. It does three things, asking before anything is installed:
1. **Tools:** if they aren't set up, it runs `tools\setup_windows.ps1`, which installs MSYS2 with SDL3, FFmpeg,
   Vulkan, shaderc, VMA and Opus, plus Python 3.12 (via winget), and creates `.venv` with the recompiler's packages.
2. **Your game files:** choose the folder that has the game's `exefs` and `romfs` folders in it (or a folder above
   them: they are found up to 4 levels down).
   - `.xci` / `.nsp` / `.nca` packages are refused without being read: the game's own extracted files are needed.
   - The version (2.0.0) and the romfs contents are checked.
   - `targets\` is then linked to those folders, so nothing is copied.

   This is `tools\setup_game_files.ps1`.
3. **Build:** `scripts/build_all.sh` checks the files, recompiles the game code, compiles it with the runtime and
   builds the launcher. The log goes to `build\build_all.log`.

When it finishes it offers to start the launcher: press **Precompile shaders** once, then **PLAY**.

### By hand

1. **Install the tools** (or run `powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1`).
   - [MSYS2](https://www.msys2.org/) at `C:\msys64`. In its UCRT64 shell, install the libraries the runtime links
     against:
     ```
     pacman -S mingw-w64-ucrt-x86_64-sdl3 mingw-w64-ucrt-x86_64-vulkan-devel mingw-w64-ucrt-x86_64-shaderc \
               mingw-w64-ucrt-x86_64-vulkan-memory-allocator mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-opus
     ```
   - Python 3.12+ and Git for Windows (the scripts run in Git Bash).
   - A virtual environment in the repository root, with the generator's packages and the Zig toolchain (used as the
     C compiler):
     ```
     python -m venv .venv
     .venv/Scripts/pip install capstone unicorn lz4 ziglang
     ```
2. **Place your game files** in `targets/exefs/` and `targets/romfs/` (or run `tools\setup_game_files.ps1`), then
   check them:
   ```
   python tools/extract/check_dump.py targets
   ```
3. **Recompile the game code** into C (`generated/`, ~240 MB, never commit it):
   ```
   cd tools && ../.venv/Scripts/python -X utf8 gen_all.py --out ../generated && cd ..
   ```
4. **Compile the game objects and the runtime** (in Git Bash; `scripts/build_all.sh` runs steps 2–4 in one go). The boot script also links a window-less dev exe from an old milestone that no longer links; `XCDE_SKIP_BOOT_LINK=1` skips it:
   ```
   XCDE_SKIP_BOOT_LINK=1 scripts/build_boot.sh   # the recompiled game -> build/obj/
   scripts/build_rt_gfx.sh                       # the runtime + Vulkan renderer -> build/xcde.exe
   tools/launcher/build.sh                       # the launcher -> build/xcde_launcher.exe
   ```
5. **Optional: temporal upscalers.** FSR 3.1 and DLSS need vendor DLLs that aren't redistributed here: the AMD
   FidelityFX SDK 1.1.4 (signed prebuilt DLL) and NVIDIA Streamline 2.14.16. Download them yourself and run
   `SDK_DIR=<folder> scripts/copy_upscaler_dlls.sh`, which copies them next to `build/xcde.exe`. Without them, those
   options fall back to FSR 1.0.
6. **Play:** run `Play Monado.bat`. The first time, press **Precompile shaders** (a few minutes) and then **PLAY**.

`scripts/ci.sh` runs the unit tests (no game data needed); `scripts/native_tests.sh` the C tests.

## Settings

Everything is set in the launcher and saved to `xcde.ini` in the repository root. Useful keys:

| Key | Values |
|---|---|
| `resolution` | `match`, `1`–`3`, `75%`, `50%`, `dynamic` |
| `upscaler` / `upscale_quality` | `bilinear` `fsr` `fsr3` `dlss` / `native` `quality` `balanced` `performance` `ultra` |
| `frame_gen`, `antialias` | `0/1`, `smaa` / `off` |
| `fps`, `vsync`, `cutscenes` | `30` `60` `120` `144` `165` `unlimited`, `0/1`, `same` / `30` / `30fg` |
| `depth_of_field`, `game_blur` | `0/1` |
| `language` | `auto`, `en-US`, `es`, `fr`, `de`, `it`, `ja` (the game's text; only what your copy includes) |
| `stick_deadzone` | `0`–`30` (% of the stick's travel; 0 = raw) |
| `bind_key_*`, `bind_pad_*`, `mouse_look`, `mouse_sens` | controls |
| `mod_<folder>` | `0/1` |
| `launcher_lang` | `en` / `es` |

In game, **F1** opens the overlay menu.

Advanced switches are environment variables (`XCDE_*`, `LARECOMP_*`). The most useful are listed in
`docs/dev/HANDOFF.md`, and `grep -rn 'getenv("XCDE_' runtime` lists them all. A few:
- `XCDE_PIPE_BUDGET` / `XCDE_LIB_BUDGET`: pipeline / library memory caps.
- `XCDE_LOWSPEC_CPUS=4`: simulate a 4-core CPU.
- `LARECOMP_VK_VALIDATION=1`: the Vulkan validation layer.
- `XCDE_DETERMINISTIC=1`: deterministic replay.

## Known issues

- **Only really tested on NVIDIA.**
  - AMD and Intel GPUs have fixes from other recomps' bug reports: trailing empty colour attachments on Intel, D32S8
    depth, D16 shadow-compare rounding. None is confirmed on the hardware.
  - Integrated GPUs with 8 GB of RAM are the big unknown: the game's 3.2 GB heap is imported into the GPU in one block,
    which failed on an AMD iGPU in another recomp. The fix (a windowed import) is designed but untested: task T244.
- **Memory in very long sessions.** Our caches are capped by RAM size (pipelines and pipeline libraries are evicted).
  The graphics driver's own memory still grows as new shaders compile: ~0.6 GB/h in a worst-case test hopping between
  every map on NVIDIA (T246). Normal sessions are fine. On 8 GB machines, hours of map hopping can end in stutter;
  restarting the game resets it.
- **First run:** shader precompilation takes a few minutes. After a GPU driver update the driver's own cache is cold
  and the first visit to an area can hitch a little.
- **Build dependencies:** the build depends on MSYS2 runtime DLLs. A self-contained package (`scripts/make_dist.sh`
  copies the DLLs next to the exe) exists for local use, but there's no release builder.
- **Paths:** non-Latin characters in paths (a Cyrillic or CJK user name) aren't supported; accents and spaces are fine.
- **Minor and open:**
  - One vertex shader uses `SHFL` (a warp shuffle), approximated as lane-local.
  - Deterministic replays drift by a few pixels after ~2,000 frames (T124).
- **Linux / macOS:** code paths inherited from LASRecomp exist (`runtime/platform/linux.c`), but this project was only
  built and tested on Windows.

## Where the knowledge is

This repository is meant to let someone else continue the work. Start here:

| Document | What it holds |
|---|---|
| [`docs/dev/HANDOFF.md`](docs/dev/HANDOFF.md) | The running development record, **newest first**: what each session did, the current state, open problems, pitfalls, measured results. The first sections are the most up to date. |
| [`docs/dev/tasks.md`](docs/dev/tasks.md) | Every task (T001–T246) with its status, evidence and the reasoning behind it, including what was tried and dropped. |
| [`docs/RECOMP_KNOWLEDGE.md`](docs/RECOMP_KNOWLEDGE.md) | Lessons from reviewing ~20 other Switch recomps / PC ports (commits and issues), by topic, useful for **any** recomp, with this project's status per item. |
| [`docs/LESSONS_FOR_XC2.md`](docs/LESSONS_FOR_XC2.md) | What carries over to *Xenoblade 2*, *3* and *X* (same engine family), and what won't. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The project rules (no game data, attribution, tests first) and the working method, including how to prove a change doesn't regress anything. |
| [`docs/dev/spec.md`](docs/dev/spec.md), [`plan.md`](docs/dev/plan.md), [`research.md`](docs/dev/research.md) | The original requirements, architecture and game facts (modules, SDK, services, memory, audio, video). |
| `docs/adr/`, `docs/contracts/` | Design decisions and interfaces. |
| `docs/spec_lowend_gpu.md`, `docs/handoff_shader_pipeline.md`, `docs/graphics_options_research.md`, `docs/lessons_*.md` | Deep dives: low-end / non-NVIDIA work, the shader and pipeline system, graphics options, reviews of other projects. |
| `docs/hle_audit.md` | Every SVC, service and HLE function with its fidelity class (generated). |

### Main things learnt
- **The GPU side was most of the work.** NVN is reimplemented on Vulkan and Maxwell shaders are translated to GLSL /
  SPIR-V. Most bugs were in barriers, texture aliasing, formats, transform feedback, occlusion queries and races with
  the asynchronous render worker. The fixes are recorded task by task.
- **Stutter:** pipeline variants are recorded while playing, merged into a seed (`data/variants_seed.bin`) and built
  ahead of time with graphics pipeline libraries, then prewarmed per area at the loading screen.
- **Deterministic mode** (one guest thread at a time, virtual time) plus per-frame hashes made every rendering change
  provable. Use it before trusting any performance or refactoring change.
- **Kernel details matter:**
  - Horizon's condvar sets its key before releasing the mutex.
  - Address arbiters must use compare-and-swap.
  - Thread stacks must be reserved, not committed (they were 10 GB of commit).
- **Memory:** the growth in long sessions came from pipeline libraries that were never freed (now evicted with
  reference counting, because NVIDIA crashes if a linked pipeline's library goes away) and from the driver itself.
  Pipelines themselves cost ~0.025 MB each.
- **Audio:** feeder threads need high priority on 4-core CPUs (7 vs 63 underruns in 5 minutes on 2 cores).

### Tried and dropped (measured)
- `VK_EXT_extended_dynamic_state3` to cut pipeline variants: only −1 % on this game.
- Native host `memcpy`: no guest function exceeds 1 % of the CPU.
- A per-thread pipeline cache; spin-before-sleep on locks.
- Hold-the-frame at loading screens: the game dropped cutscenes.
- See `docs/dev/tasks.md` and the HANDOFF for each one's numbers.

## Repository layout

```
runtime/        the recompiled game's host: loader, kernel (SVC, threads, sync), IPC services, HLE, NVN -> Vulkan,
                Maxwell shader translator, audio, video, input, diagnostics
tools/          recompiler (lifter/), dump check (extract/), launcher/, test and analysis tools
games/xcde/     the game profile: build-ids, modules, patches, HLE symbol and class lists
scripts/        build, test-drive and soak scripts (Git Bash)
tests/          unit tests (no game data), native C tests, input routes, test tours
data/           variants_seed.bin: pipeline variants to precompile (state keys, no game content)
docs/           everything above
third_party/    Dear ImGui, SMAA, AMD FidelityFX API headers, NVIDIA Streamline headers, bcdec
```

## Credits and license

- [LASRecomp](https://github.com/peiikai/LASRecomp) by Peiikai (MIT): the recompiler and runtime this project is
  derived from. Every change to its files is marked `[XCDE]` and listed in `docs/UPSTREAM.md`.
- Ideas (never code) from many other recomp and port projects, listed in `docs/RECOMP_KNOWLEDGE.md` and `NOTICE.md`.
- Third-party components and their licences: `NOTICE.md`.

Monado is released under the MIT License (`LICENSE`). It is an independent project, not affiliated with or endorsed by
Nintendo or Monolith Soft. *Xenoblade Chronicles* is a trademark of Nintendo.
