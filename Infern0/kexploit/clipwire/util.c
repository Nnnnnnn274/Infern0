#include "clipwire.h"

U64 g_kern_slide = 0;
U64 g_kern_base = KERNEL_TEXT_BASE_STATIC;

static bool g_initialized = false;



void clipwire_init(void)
{
    if (g_initialized) return;
    setbuf(stdout, NULL);
    g_kern_slide = get_kernel_slide();
    g_kern_base = KERNEL_TEXT_BASE_STATIC + g_kern_slide;
    g_initialized = true;
}

void nsleep(U64 ns)
{
    struct timespec ts;
    ts.tv_sec = ns / 1000000000ULL;
    ts.tv_nsec = ns % 1000000000ULL;
    nanosleep(&ts, NULL);
}

bool check_target(void)
{
    struct utsname u;
    if (uname(&u) != 0) {
        LOGBAD("uname failed (%d)", errno);
        return false;
    }
    LOG("running on %s %s", u.machine, u.version);

    /* By default refuse to run on a non-A13 device or a non-23B85 build:
     * every static address in this project is specific to that target and a
     * wrong-target run only panics the device. CLIPWIRE_ALLOW_NONMATCH=1
     * forces it for research/validation runs. */
    const char *env = getenv("CLIPWIRE_ALLOW_NONMATCH");
    bool hard = (env == NULL || env[0] == '\0' || env[0] == '0');

    if (strncmp(u.machine, "iPhone12,", 9) != 0) {
        if (hard) {
            LOGBAD("device is %s - offsets/validation written for A13 (iPhone12,*); "
                   "set CLIPWIRE_ALLOW_NONMATCH=1 to force", u.machine);
            return false;
        }
        LOGWARN("device is %s, continuing anyway (CLIPWIRE_ALLOW_NONMATCH=1)", u.machine);
    }

    char osver[256] = {0};
    size_t len = sizeof(osver);
    if (sysctlbyname("kern.osversion", osver, &len, NULL, 0) == 0) {
        LOG("kern.osversion: %s", osver);
        if (strcmp(osver, "23B85") != 0) {
            if (hard) {
                LOGBAD("expected 23B85 (iOS 26.1), got %s - static addresses are "
                       "build-specific; set CLIPWIRE_ALLOW_NONMATCH=1 to force", osver);
                return false;
            }
            LOGWARN("expected 23B85 (iOS 26.1), got %s", osver);
        }
    }
    return true;
}
