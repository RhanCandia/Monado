// nn::os fibers over host fibers (T032b, FR-022).  [XCDE]
//
// The SDK switches fibers by saving/restoring registers and `ret`-ing into the other context. Recompiled code runs on
// the host stack, so it cannot do that: each guest fiber gets a host fiber (its own host stack) and its own guest
// register file (Cpu). The guest stack (given to InitializeFiber) stays guest memory.
//
//   InitializeFiber(FiberType*, FiberFunction, void *arg, void *stack, size_t stack_size, int flags)
//   SwitchToFiber(FiberType*)      FinalizeFiber(FiberType*)      GetCurrentFiber() -> FiberType*
//   FiberFunction: FiberType *(*)(void *arg) -- returns the fiber to switch to when it ends (null: back to the thread)
//
// Lessons applied (research R10): a fiber may be resumed on another host thread than the one that suspended it, so
// its guest thread block (tpidr/tpidrro/thread) is handed over from the switching thread on every switch (ssbu #43);
// the per-thread "current fiber" is read through non-inlined accessors, because a compiler may keep a thread-local
// address across a switch that moves the code to another thread.
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <ucontext.h>
#include <sys/mman.h>
#endif

#include "../rt.h"

typedef struct HFiber {
    uint64_t key;                 // guest FiberType*
    uint64_t fn, arg, stack, stack_size;
    void *host;                   // the host fiber (Windows: LPVOID fiber; Linux: ucontext_t *)
    Cpu cpu;                      // this fiber's guest registers
    uint64_t tpidr, tpidrro;      // thread block of the host thread that runs it now (set by whoever switches to it)
    void *thread;
#ifndef _WIN32
    void *host_stack;             // the mmap'd stack backing the ucontext (freed on finalize)
    size_t host_stack_size;
#endif
    struct HFiber *next;          // hash chain
} HFiber;

#define NBUCKETS 4096
static HFiber *g_buckets[NBUCKETS];
#ifdef _WIN32
static CRITICAL_SECTION g_lock;
static INIT_ONCE g_once = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK init_lock(PINIT_ONCE o, PVOID p, PVOID *ctx) { (void)o; (void)p; (void)ctx; InitializeCriticalSection(&g_lock); return TRUE; }
static void lock(void) { InitOnceExecuteOnce(&g_once, init_lock, NULL, NULL); EnterCriticalSection(&g_lock); }
static void unlock(void) { LeaveCriticalSection(&g_lock); }
#else
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static void lock(void) { pthread_mutex_lock(&g_lock); }
static void unlock(void) { pthread_mutex_unlock(&g_lock); }
#endif

static unsigned bucket(uint64_t key) { return (unsigned)((key >> 4) * 0x9E3779B1u) % NBUCKETS; }
static HFiber *find(uint64_t key) {
    lock();
    HFiber *f = g_buckets[bucket(key)];
    while (f && f->key != key) f = f->next;
    unlock();
    return f;
}

// ---- per host thread state, through non-inlined accessors
static __thread uint64_t t_fiber;       // guest FiberType* running on this host thread now (0: the thread itself)
static __thread void *t_root;           // the host fiber of the thread itself
__attribute__((noinline)) static uint64_t cur_get(void) { __asm__ volatile("" ::: "memory"); return t_fiber; }
__attribute__((noinline)) static void cur_set(uint64_t k) { t_fiber = k; __asm__ volatile("" ::: "memory"); }
__attribute__((noinline)) static void *root_get(void) { __asm__ volatile("" ::: "memory"); return t_root; }
__attribute__((noinline)) static void root_set(void *r) { t_root = r; __asm__ volatile("" ::: "memory"); }

#ifdef _WIN32
static void *ensure_root(void) {
    void *r = root_get();
    if (!r) {
        r = IsThreadAFiber() ? GetCurrentFiber() : ConvertThreadToFiber(NULL);
        root_set(r);
    }
    return r;
}
#else
// Linux: the "root" context is a ucontext_t allocated per thread (thread-local).  swapcontext saves the current
// execution state into it when switching to a fiber, and the fiber switches back by swapping into it.
static __thread ucontext_t t_root_ctx;
static void *ensure_root(void) {
    void *r = root_get();
    if (!r) {
        r = &t_root_ctx;
        root_set(r);
    }
    return r;
}
#endif

// hand the caller's thread block to the fiber about to run on this host thread
static void hand_over(HFiber *to, const Cpu *from) {
    to->tpidr = from->tpidr;
    to->tpidrro = from->tpidrro;
    to->thread = from->thread;
}
static void take_over(Cpu *c, const HFiber *f) {
    c->tpidr = f->tpidr;
    c->tpidrro = f->tpidrro;
    c->thread = f->thread;
}

#ifdef _WIN32
static void CALLBACK fiber_main(void *p) {
#else
static void fiber_main_linux(unsigned hi, unsigned lo) {
    void *p = (void *)((uintptr_t)hi << 32 | (uintptr_t)lo);
#endif
    HFiber *f = p;
    for (;;) {
        Cpu *c = &f->cpu;
        take_over(c, f);
        c->x[0] = f->arg;
        c->sp = (f->stack + f->stack_size) & ~15ull;
        c->excl_addr = ~0ull;
        guest_call(c, f->fn);                 // returns the fiber to switch to next, or null
        uint64_t next = c->x[0];
        HFiber *n = next ? find(next) : NULL;
        if (next && !n) FATAL("[fiber] function of fiber %llx returned unknown fiber %llx\n", (unsigned long long)f->key, (unsigned long long)next);
        if (n) hand_over(n, c);
        cur_set(next);
#ifdef _WIN32
        SwitchToFiber(n ? n->host : root_get());
#else
        swapcontext((ucontext_t *)f->host, n ? (ucontext_t *)n->host : (ucontext_t *)root_get());
#endif
        // only reached if a finished fiber is switched to again: it starts over with its function
    }
}

#ifndef _WIN32
static void fiber_free_host(HFiber *f) {
    if (f->host) {
        free((ucontext_t *)f->host);
        f->host = NULL;
    }
    if (f->host_stack) {
        munmap(f->host_stack, f->host_stack_size);
        f->host_stack = NULL;
    }
}
#endif

// ---- the HLE entry points (names fixed: gen.py --hle binds the SDK functions to hle_<mangled>)
void hle__ZN2nn2os15InitializeFiberEPNS0_9FiberTypeEPFS2_PvES3_S3_mi(Cpu *c) {
    uint64_t key = c->x[0];
    lock();
    HFiber *f = g_buckets[bucket(key)];
    while (f && f->key != key) f = f->next;
    if (!f) {
        f = calloc(1, sizeof *f);
        f->key = key;
        f->next = g_buckets[bucket(key)];
        g_buckets[bucket(key)] = f;
    } else if (f->host) {
#ifdef _WIN32
        DeleteFiber(f->host);  // re-initialized without Finalize: start fresh
        f->host = NULL;
#else
        fiber_free_host(f);
#endif
    }
    unlock();
    f->fn = c->x[1], f->arg = c->x[2], f->stack = c->x[3], f->stack_size = c->x[4];
    memset(&f->cpu, 0, sizeof f->cpu);
    f->cpu.excl_addr = ~0ull;
#ifdef _WIN32
    f->host = CreateFiberEx(256 * 1024, (SIZE_T)64 << 20, 0, fiber_main, f);
    if (!f->host) FATAL("[fiber] CreateFiber failed (%lu)\n", GetLastError());
#else
    // Linux: allocate a ucontext with an mmap'd stack (64 MiB committed, guard page at the bottom)
    f->host_stack_size = (size_t)64 << 20;
    f->host_stack = mmap(NULL, f->host_stack_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK, -1, 0);
    if (f->host_stack == MAP_FAILED) FATAL("[fiber] mmap %zu bytes failed\n", f->host_stack_size);
    mprotect(f->host_stack, 4096, PROT_NONE);  // guard page
    ucontext_t *uc = calloc(1, sizeof(ucontext_t));
    getcontext(uc);
    uc->uc_stack.ss_sp = f->host_stack;
    uc->uc_stack.ss_size = f->host_stack_size;
    uc->uc_link = NULL;  // fiber_main loops forever; uc_link is never reached
    // makecontext takes int args; pass the pointer as two unsigned ints
    unsigned hi = (unsigned)((uintptr_t)f >> 32), lo = (unsigned)(uintptr_t)f;
    makecontext(uc, (void (*)(void))fiber_main_linux, 2, hi, lo);
    f->host = uc;
#endif
}

void hle__ZN2nn2os13FinalizeFiberEPNS0_9FiberTypeE(Cpu *c) {
    uint64_t key = c->x[0];
    lock();
    HFiber **pp = &g_buckets[bucket(key)];
    while (*pp && (*pp)->key != key) pp = &(*pp)->next;
    HFiber *f = *pp;
    if (f) *pp = f->next;
    unlock();
    if (f) {
#ifdef _WIN32
        if (f->host) DeleteFiber(f->host);
#else
        fiber_free_host(f);
#endif
        free(f);
    }
}

void hle__ZN2nn2os13SwitchToFiberEPNS0_9FiberTypeE(Cpu *c) {
    uint64_t key = c->x[0];
    void *root = ensure_root();
    HFiber *n = key ? find(key) : NULL;
    if (key && !n) FATAL("[fiber] SwitchToFiber to unknown fiber %llx\n", (unsigned long long)key);
    uint64_t self = cur_get();
    if (n) hand_over(n, c);
    cur_set(key);
#ifdef _WIN32
    SwitchToFiber(n ? n->host : root);
#else
    // Save the current context into either our fiber's context or the root context, then switch
    HFiber *me_fiber = self ? find(self) : NULL;
    ucontext_t *save_to = me_fiber ? (ucontext_t *)me_fiber->host : (ucontext_t *)root;
    swapcontext(save_to, n ? (ucontext_t *)n->host : (ucontext_t *)root);
#endif
    // resumed: possibly on another host thread than the one that suspended us. The one that switched to us wrote
    // its thread block into our record (or, for the thread's own context, nothing changed).
    cur_set(self);
    if (self) {
        HFiber *me = find(self);
        if (me) take_over(c, me);
    }
}

void hle__ZN2nn2os15GetCurrentFiberEv(Cpu *c) { c->x[0] = cur_get(); }
