// Headless boot host (M3a): loads the modules, sets up the kernel and runs nn::init::Start, with strict logging of
// every service, SVC and import the game touches. No window, no renderer. Derived from LASRecomp runtime/main.c (MIT). [XCDE]
#include "../diag/diag.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#include "../gamelib.h"
#include "../hle.h"
#include "../kernel.h"
#include "../rt.h"

const char *g_romfs_dir;

#ifdef XCDE_GFX
// [XCDE] T194: laptops with two GPUs (NVIDIA Optimus / AMD switchable graphics) run a program on the integrated one
// unless the exe exports these; the driver reads them at start. (device.c then picks the discrete GPU among those
// Vulkan lists; LARECOMP_GPU=<n> overrides.)
#ifdef _WIN32
__declspec(dllexport) DWORD NvOptimusEnablement = 1;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
#else
__attribute__((visibility("default"))) int NvOptimusEnablement = 1;
__attribute__((visibility("default"))) int AmdPowerXpressRequestHighPerformance = 1;
#endif
#endif

static void run_array(Cpu *c, uint64_t arr, uint64_t size) {
    for (uint64_t i = 0; i < size / 8; i++) {
        uint64_t fn = ((uint64_t *)arr)[i];
        if (fn) guest_call(c, fn);
    }
}
static void module_init(Cpu *c, Module *m) {
    LOG("init %s (DT_INIT %llx, %llu init_array entries)\n", m->name, (unsigned long long)m->init,
        (unsigned long long)(m->init_array_sz / 8));
    if (m->init) guest_call(c, m->init);
    else run_array(c, m->init_array, m->init_array_sz);
}
static void rtld_init_sdk(Cpu *c) { module_init(c, &g_modules[1]); }
static void rtld_init_main(Cpu *c) { module_init(c, &g_modules[0]); }

__attribute__((constructor(101))) static void reserve_guest_space(void) {
    if (!plat_reserve_guest(GUEST_LO, GUEST_HI)) {
        // [XCDE] T135: something the loader placed at random (ASLR) sits in the guest range in ~1 of 5 starts. A new
        // process gets a new layout: start this one again (same command line, same console), up to 8 times.
#ifdef _WIN32
        char n[16] = "0";
        GetEnvironmentVariableA("XCDE_RELAUNCH", n, sizeof n);
        int tries = atoi(n);
        fprintf(stderr, "[boot] guest address range %llx-%llx is not free (try %d)%s\n", (unsigned long long)GUEST_LO,
                (unsigned long long)GUEST_HI, tries + 1, tries < 8 ? ": starting again" : "");
        if (tries < 8) {
            snprintf(n, sizeof n, "%d", tries + 1);
            SetEnvironmentVariableA("XCDE_RELAUNCH", n);
            STARTUPINFOA si = {.cb = sizeof si};
            PROCESS_INFORMATION pi;
            char exe[MAX_PATH];
            GetModuleFileNameA(NULL, exe, sizeof exe);
            // the new process dies with this one (a test's timeout or a closed console must not leave it running)
            HANDLE job = CreateJobObjectA(NULL, NULL);
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION jl = {0};
            jl.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if (job) SetInformationJobObject(job, JobObjectExtendedLimitInformation, &jl, sizeof jl);
            if (CreateProcessA(exe, GetCommandLineA(), NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, NULL, &si, &pi)) {
                if (job) AssignProcessToJobObject(job, pi.hProcess);
                ResumeThread(pi.hThread);
                WaitForSingleObject(pi.hProcess, INFINITE);
                DWORD code = 1;
                GetExitCodeProcess(pi.hProcess, &code);
                ExitProcess(code);
            }
        }
#else
        const char *env = getenv("XCDE_RELAUNCH");
        int tries = env ? atoi(env) : 0;
        fprintf(stderr, "[boot] guest address range %llx-%llx is not free (try %d)%s\n", (unsigned long long)GUEST_LO,
                (unsigned long long)GUEST_HI, tries + 1, tries < 8 ? ": starting again" : "");
        if (tries < 8) {
            char n[16];
            snprintf(n, sizeof n, "%d", tries + 1);
            setenv("XCDE_RELAUNCH", n, 1);
            plat_exec(NULL);
        }
#endif
        fprintf(stderr, "FATAL: guest address range %llx-%llx is not free\n", (unsigned long long)GUEST_LO,
                (unsigned long long)GUEST_HI);
        exit(1);
    }
}

// [XCDE] Watchdog (T027, first version): every few seconds the state of every guest thread; XCDE_WATCHDOG=<seconds>.
#ifdef _WIN32
static DWORD WINAPI watchdog_main(LPVOID p) {
    unsigned secs = (unsigned)(uintptr_t)p;
    for (;;) { Sleep(secs * 1000); LOG("[wd] ---- %u s ----"" %c", secs, 10); kernel_dump_threads(stderr); }
}
#else
static void *watchdog_main(void *p) {
    unsigned secs = (unsigned)(uintptr_t)p;
    for (;;) { usleep(secs * 1000000); LOG("[wd] ---- %u s ----"" %c", secs, 10); kernel_dump_threads(stderr); }
    return NULL;
}
#endif


static bool dir_has_exefs(const char *dir) {
    char p[1024];
    snprintf(p, sizeof p, "%s/exefs", dir);
#ifdef _WIN32
    DWORD a = GetFileAttributesA(p);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
#else
    return access(p, F_OK) == 0;
#endif
}

int main(int argc, char **argv) {
    if (argc >= 6 && !strcmp(argv[1], "--minidump")) return diag_minidump_helper(argc, argv);  // [XCDE] T028: crash helper process
#ifdef XCDE_GFX
    if (argc >= 2 && !strcmp(argv[1], "--precompile")) {  // [XCDE] T187: fill the shader cache from the RomFS, then exit
        extern int vk_precompile_main(const char *root);
        const char *pc_root = argc >= 3 ? argv[2] : (dir_has_exefs("target") ? "target" : "targets");
        return vk_precompile_main(pc_root);
    }
#endif
    plat_init();
    setvbuf(stderr, NULL, _IONBF, 0);
    const char *root = NULL;
    int seconds = 20;
    if (argc >= 2 && argv[1][0] != '-') {
        root = argv[1];
        if (argc > 2) seconds = atoi(argv[2]);
    } else {
        if (dir_has_exefs("target")) root = "target";
        else if (dir_has_exefs("targets")) root = "targets";
        else if (dir_has_exefs("dump")) root = "dump";
        else {
            fprintf(stderr, "usage: xcde [target dir with exefs/ and romfs/] [seconds]\n");
            return 2;
        }
        if (argc >= 2) seconds = atoi(argv[1]);
    }
    char exefs[1024], romfs[1024], npdm_path[1024];
    snprintf(exefs, sizeof exefs, "%s/exefs", root);
    snprintf(romfs, sizeof romfs, "%s/romfs", root);
    snprintf(npdm_path, sizeof npdm_path, "%s/main.npdm", exefs);
    g_romfs_dir = strdup(romfs);

    diag_watchdog_start();
#ifdef _WIN32
    if (getenv("XCDE_WATCHDOG")) CreateThread(NULL, 0, watchdog_main, (LPVOID)(uintptr_t)atoi(getenv("XCDE_WATCHDOG")), 0, NULL);
#else
    if (getenv("XCDE_WATCHDOG")) {
        pthread_t th;
        pthread_create(&th, NULL, watchdog_main, (void *)(uintptr_t)atoi(getenv("XCDE_WATCHDOG")));
        pthread_detach(th);
    }
#endif
    loader_load(exefs);
    kernel_init();
    dispatch_init();

    uint32_t stack_size = 0x100000;
    int prio = 44;
    FILE *f = fopen(npdm_path, "rb");
    if (f) {
        uint8_t meta[0x80];
        if (fread(meta, 1, sizeof meta, f) == sizeof meta && !memcmp(meta, "META", 4)) {
            prio = meta[0xE];
            stack_size = *(uint32_t *)(meta + 0x1C);
        }
        fclose(f);
    }
    LOG("main thread: prio %d, stack 0x%x\n", prio, stack_size);

    uint64_t start = loader_find_symbol("_ZN2nn4init5StartEmmPFvvES2_");
    if (!start) FATAL("nn::init::Start not found\n");
    uint64_t init_fn = hle_register("<rtld_init_sdk>", rtld_init_sdk);
    uint64_t fini_fn = hle_register("<rtld_init_main>", rtld_init_main);
    KThread *t = kernel_create_main_thread(start, stack_size, prio);
    kernel_run_main(t, t->handle, 0, init_fn, fini_fn);
#ifdef XCDE_GFX
    extern int ui_run(void);  // window + Vulkan presenter on the main thread (runtime/nvn/vulkan/device.c)
    LOG("[boot] running with the window\n");
    (void)seconds;
    return ui_run();
#else
    LOG("[boot] running; stopping after %d s\n", seconds);
    plat_sleep_until_ns(plat_now_ns() + (uint64_t)seconds * 1000000000ull);
    LOG("[boot] timeout reached, exiting\n");
    return 0;
#endif
}
