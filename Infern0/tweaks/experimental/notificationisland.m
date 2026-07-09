//
//  notificationisland.m
//  Cyanide
//

#import "notificationisland.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <string.h>
#import <sys/time.h>

#pragma mark - ActivityKit route state

static const uint64_t kNotificationIslandVisibleUS    = 3600000ULL;
static const uint64_t kNotificationIslandRepeatUS     = 1200000ULL;
static const uint64_t kNotificationIslandPrepareRetryUS = 5000000ULL;

static bool gNIActivityKitPrepared = false;
static bool gNILegacyOverlayCleanupDone = false;
static uint64_t gNILastRequest = 0;
static uint64_t gNIVisibleUntilUS = 0;
static uint64_t gNILastShowUS = 0;
static uint64_t gNILastPrepareAttemptUS = 0;
static char gNILastIdentifier[192] = {0};
static bool gNIMissingBannerLogged = false;
static bool gNIMissingDispatcherLogged = false;

static uint64_t ni_now_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((uint64_t)tv.tv_sec * 1000000ULL) + (uint64_t)tv.tv_usec;
}

static uint64_t ni_try_msg0_main(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj) || !r_responds_main(obj, selName)) return 0;
    return r_msg2_main(obj, selName, 0, 0, 0, 0);
}

static uint64_t ni_springboard_application(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    return r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
}

static uint64_t ni_legacy_overlay_assoc_key(void)
{
    return r_sel("cyanideNotificationIslandWindow");
}

static void ni_cleanup_legacy_overlay_once(void)
{
    if (gNILegacyOverlayCleanupDone) return;
    gNILegacyOverlayCleanupDone = true;

    uint64_t app = ni_springboard_application();
    uint64_t key = ni_legacy_overlay_assoc_key();
    if (!r_is_objc_ptr(app) || !key) return;

    uint64_t win = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                app, key, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(win)) return;

    r_msg2_main(win, "setHidden:", 1, 0, 0, 0);
    if (r_responds_main(win, "removeFromSuperview")) {
        r_msg2_main(win, "removeFromSuperview", 0, 0, 0, 0);
    }
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 app, key, 0, 1, 0, 0, 0, 0);
    printf("[NISLAND] cleaned legacy SpringBoard overlay window=0x%llx\n", win);
}

#pragma mark - Notification Center request extraction

static uint64_t ni_springboard_dispatcher(uint64_t app)
{
    uint64_t dispatcher = ni_try_msg0_main(app, "notificationDispatcher");
    if (!r_is_objc_ptr(dispatcher)) dispatcher = r_ivar_value(app, "_notificationDispatcher");
    if (!r_is_objc_ptr(dispatcher) && !gNIMissingDispatcherLogged) {
        printf("[NISLAND] SpringBoard notificationDispatcher unavailable\n");
        gNIMissingDispatcherLogged = true;
    }
    return dispatcher;
}

static uint64_t ni_banner_destination(uint64_t dispatcher)
{
    uint64_t dest = ni_try_msg0_main(dispatcher, "bannerDestination");
    if (!r_is_objc_ptr(dest)) dest = r_ivar_value(dispatcher, "_bannerDestination");
    if (!r_is_objc_ptr(dest)) dest = r_ivar_value(dispatcher, "_alertDestination");
    if (!r_is_objc_ptr(dest) && !gNIMissingBannerLogged) {
        printf("[NISLAND] bannerDestination unavailable dispatcher=0x%llx\n", dispatcher);
        gNIMissingBannerLogged = true;
    }
    return dest;
}

static uint64_t ni_nc_dispatcher(uint64_t dispatcher)
{
    uint64_t nc = ni_try_msg0_main(dispatcher, "dispatcher");
    if (!r_is_objc_ptr(nc)) nc = r_ivar_value(dispatcher, "_dispatcher");
    return r_is_objc_ptr(nc) ? nc : dispatcher;
}

static uint64_t ni_active_request_from_presenter(uint64_t presenter)
{
    if (!r_is_objc_ptr(presenter)) return 0;
    uint64_t req = ni_try_msg0_main(presenter, "notificationRequest");
    if (!r_is_objc_ptr(req)) req = ni_try_msg0_main(presenter, "request");
    if (!r_is_objc_ptr(req)) req = r_ivar_value(presenter, "_notificationRequest");
    if (!r_is_objc_ptr(req)) req = r_ivar_value(presenter, "_request");
    return req;
}

static uint64_t ni_active_notification_request(uint64_t banner)
{
    if (!r_is_objc_ptr(banner)) return 0;
    uint64_t req = ni_try_msg0_main(banner, "presentedNotificationRequest");
    if (!r_is_objc_ptr(req)) req = ni_try_msg0_main(banner, "_presentedNotificationRequest");
    if (!r_is_objc_ptr(req)) req = r_ivar_value(banner, "_presentedNotificationRequest");
    if (!r_is_objc_ptr(req)) req = r_ivar_value(banner, "_currentNotificationRequest");
    if (!r_is_objc_ptr(req)) req = r_ivar_value(banner, "_notificationRequest");
    if (r_is_objc_ptr(req)) return req;

    uint64_t presenter = ni_try_msg0_main(banner, "presentedNotificationRequestPresenter");
    if (!r_is_objc_ptr(presenter)) {
        presenter = ni_try_msg0_main(banner, "_presentedNotificationRequestPresenter");
    }
    if (!r_is_objc_ptr(presenter)) presenter = r_ivar_value(banner, "_presentedNotificationRequestPresenter");
    req = ni_active_request_from_presenter(presenter);
    if (r_is_objc_ptr(req)) return req;

    uint64_t queue = r_ivar_value(banner, "_alertQueue");
    if (r_is_objc_ptr(queue)) {
        req = r_ivar_value(queue, "_coalescingRequest");
        if (!r_is_objc_ptr(req)) req = r_ivar_value(queue, "_activeRequest");
    }
    return req;
}

static bool ni_read_string_obj(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return false;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return false;
    if (r_read_nsstring(obj, out, outLen) && out[0]) return true;
    uint64_t stringObj = ni_try_msg0_main(obj, "string");
    return r_read_nsstring(stringObj, out, outLen) && out[0];
}

static bool ni_read_field(uint64_t obj, const char *ivarName,
                          const char *selName, char *out, size_t outLen)
{
    if (!out || outLen == 0) return false;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return false;

    uint64_t value = 0;
    if (ivarName) value = r_ivar_value(obj, ivarName);
    if (!r_is_objc_ptr(value) && selName) value = ni_try_msg0_main(obj, selName);
    return ni_read_string_obj(value, out, outLen);
}

static void ni_short_bundle_name(const char *bundle, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!bundle || !bundle[0]) {
        snprintf(out, outLen, "%s", "Notification");
        return;
    }
    const char *last = strrchr(bundle, '.');
    snprintf(out, outLen, "%s", (last && last[1]) ? last + 1 : bundle);
}

static bool ni_request_identifier(uint64_t req, char *identifier, size_t identifierLen)
{
    if (!identifier || identifierLen == 0) return false;
    identifier[0] = '\0';
    if (!r_is_objc_ptr(req)) return false;

    if (ni_read_field(req, "_notificationIdentifier", "notificationIdentifier",
                      identifier, identifierLen)) {
        return true;
    }
    uint64_t uuid = r_ivar_value(req, "_uuid");
    if (!r_is_objc_ptr(uuid)) uuid = ni_try_msg0_main(req, "uuid");
    uint64_t uuidString = ni_try_msg0_main(uuid, "UUIDString");
    if (ni_read_string_obj(uuidString, identifier, identifierLen)) return true;

    snprintf(identifier, identifierLen, "ptr-%llx", req);
    return true;
}

static uint64_t ni_request_content(uint64_t req)
{
    uint64_t content = r_ivar_value(req, "_content");
    if (!r_is_objc_ptr(content)) content = ni_try_msg0_main(req, "content");
    if (!r_is_objc_ptr(content)) {
        uint64_t bulletin = r_ivar_value(req, "_bulletin");
        if (!r_is_objc_ptr(bulletin)) bulletin = ni_try_msg0_main(req, "bulletin");
        content = r_ivar_value(bulletin, "_content");
    }
    return content;
}

static bool ni_request_text(uint64_t req,
                            char *identifier, size_t identifierLen,
                            char *source, size_t sourceLen,
                            char *title, size_t titleLen,
                            char *body, size_t bodyLen)
{
    if (!r_is_objc_ptr(req)) return false;
    char bundle[160] = {0};
    char header[160] = {0};
    char contentTitle[192] = {0};
    char message[320] = {0};
    char subtitle[192] = {0};

    (void)ni_request_identifier(req, identifier, identifierLen);
    (void)ni_read_field(req, "_sectionIdentifier", "sectionIdentifier",
                        bundle, sizeof(bundle));

    uint64_t content = ni_request_content(req);
    (void)ni_read_field(content, "_header", "header", header, sizeof(header));
    if (!header[0]) (void)ni_read_field(content, "_customHeader", "customHeader", header, sizeof(header));
    if (!header[0]) (void)ni_read_field(content, "_defaultHeader", "defaultHeader", header, sizeof(header));
    (void)ni_read_field(content, "_title", "title", contentTitle, sizeof(contentTitle));
    (void)ni_read_field(content, "_subtitle", "subtitle", subtitle, sizeof(subtitle));
    (void)ni_read_field(content, "_message", "message", message, sizeof(message));
    if (!message[0]) (void)ni_read_field(content, "_attributedMessage", "attributedMessage", message, sizeof(message));

    if (!header[0]) {
        uint64_t bulletin = r_ivar_value(req, "_bulletin");
        if (!r_is_objc_ptr(bulletin)) bulletin = ni_try_msg0_main(req, "bulletin");
        (void)ni_read_field(bulletin, "_sectionDisplayName", "sectionDisplayName",
                            header, sizeof(header));
    }
    if (!header[0]) ni_short_bundle_name(bundle, header, sizeof(header));

    if (source && sourceLen) snprintf(source, sourceLen, "%s", header);
    if (title && titleLen) {
        if (contentTitle[0]) {
            snprintf(title, titleLen, "%s", contentTitle);
        } else {
            snprintf(title, titleLen, "%s", header);
        }
    }
    if (body && bodyLen) {
        body[0] = '\0';
        if (message[0] && (!contentTitle[0] || strcmp(contentTitle, message) != 0)) {
            snprintf(body, bodyLen, "%s", message);
        } else if (subtitle[0]) {
            snprintf(body, bodyLen, "%s", subtitle);
        }
    }
    return title && title[0];
}

static bool ni_withdraw_request(uint64_t banner, uint64_t dispatcher, uint64_t req)
{
    bool attempted = false;
    if (r_is_objc_ptr(banner) && r_is_objc_ptr(req)) {
        if (r_responds_main(banner, "withdrawNotificationRequest:")) {
            r_msg2_main_async(banner, "withdrawNotificationRequest:", req, 0, 0, 0);
            attempted = true;
        } else if (r_responds_main(banner, "withdrawNotificationRequest:completion:")) {
            r_msg2_main_async(banner, "withdrawNotificationRequest:completion:", req, 0, 0, 0);
            attempted = true;
        }
    }

    uint64_t nc = ni_nc_dispatcher(dispatcher);
    if (r_is_objc_ptr(nc) && r_is_objc_ptr(req) &&
        r_responds_main(nc, "withdrawNotificationWithRequest:")) {
        r_msg2_main_async(nc, "withdrawNotificationWithRequest:", req, 0, 0, 0);
        attempted = true;
    }
    return attempted;
}

static NSString *ni_local_string_from_c(const char *s)
{
    if (!s) s = "";
    return [NSString stringWithUTF8String:s] ?: @"";
}

static bool ni_activitykit_available(void)
{
    Class cls = NSClassFromString(@"NotificationIslandLiveActivityBridge");
    SEL sel = NSSelectorFromString(@"canPresent");
    if (!cls || ![cls respondsToSelector:sel]) return false;
    return ((BOOL (*)(id, SEL))objc_msgSend)(cls, sel) ? true : false;
}

static bool ni_activitykit_show(const char *title, const char *body,
                                const char *source, const char *identifier)
{
    if (!ni_activitykit_available()) return false;
    Class cls = NSClassFromString(@"NotificationIslandLiveActivityBridge");
    SEL sel = NSSelectorFromString(@"showWithTitle:body:source:requestIdentifier:");
    if (!cls || ![cls respondsToSelector:sel]) return false;

    NSString *titleString = ni_local_string_from_c(title);
    NSString *bodyString = ni_local_string_from_c(body);
    NSString *sourceString = ni_local_string_from_c(source);
    NSString *identifierString = ni_local_string_from_c(identifier);
    return ((BOOL (*)(id, SEL, NSString *, NSString *, NSString *, NSString *))objc_msgSend)(
        cls, sel, titleString, bodyString, sourceString, identifierString) ? true : false;
}

static bool ni_activitykit_prepare(void)
{
    if (!ni_activitykit_available()) return false;
    Class cls = NSClassFromString(@"NotificationIslandLiveActivityBridge");
    SEL sel = NSSelectorFromString(@"prepare");
    if (!cls || ![cls respondsToSelector:sel]) return false;
    return ((BOOL (*)(id, SEL))objc_msgSend)(cls, sel) ? true : false;
}

static bool ni_ensure_activitykit_prepared(uint64_t nowUS, bool force)
{
    if (!force && gNIActivityKitPrepared) return true;
    if (!force &&
        gNILastPrepareAttemptUS != 0 &&
        nowUS - gNILastPrepareAttemptUS < kNotificationIslandPrepareRetryUS) {
        return gNIActivityKitPrepared;
    }

    gNILastPrepareAttemptUS = nowUS;
    bool ready = ni_activitykit_prepare();
    gNIActivityKitPrepared = ready;
    return ready;
}

static bool ni_activitykit_show_sample(void)
{
    if (!ni_activitykit_available()) return false;
    Class cls = NSClassFromString(@"NotificationIslandLiveActivityBridge");
    SEL sel = NSSelectorFromString(@"showSample");
    if (!cls || ![cls respondsToSelector:sel]) return false;
    return ((BOOL (*)(id, SEL))objc_msgSend)(cls, sel) ? true : false;
}

static bool ni_activitykit_end(void)
{
    Class cls = NSClassFromString(@"NotificationIslandLiveActivityBridge");
    SEL sel = NSSelectorFromString(@"end");
    if (!cls || ![cls respondsToSelector:sel]) return false;
    ((void (*)(id, SEL))objc_msgSend)(cls, sel);
    return true;
}

#pragma mark - Public API

bool notificationisland_apply_in_session(void)
{
    uint64_t nowUS = ni_now_us();
    ni_cleanup_legacy_overlay_once();

    if (ni_ensure_activitykit_prepared(nowUS, true)) {
        printf("[NISLAND] apply: ActivityKit route ready/prepared\n");
        return true;
    }

    gNIActivityKitPrepared = false;
    printf("[NISLAND] apply: ActivityKit route unavailable; overlay fallback disabled\n");
    return false;
}

bool notificationisland_tick_in_session(void)
{
    uint64_t nowUS = ni_now_us();
    ni_cleanup_legacy_overlay_once();
    (void)ni_ensure_activitykit_prepared(nowUS, false);

    uint64_t app = ni_springboard_application();
    if (!r_is_objc_ptr(app)) return false;

    uint64_t dispatcher = ni_springboard_dispatcher(app);
    uint64_t banner = ni_banner_destination(dispatcher);
    uint64_t req = ni_active_notification_request(banner);
    if (!r_is_objc_ptr(req)) {
        gNILastRequest = 0;
        if (gNIVisibleUntilUS != 0 && nowUS >= gNIVisibleUntilUS) gNIVisibleUntilUS = 0;
        return true;
    }

    char identifier[sizeof(gNILastIdentifier)] = {0};
    char source[192] = {0};
    char title[192] = {0};
    char body[384] = {0};
    if (!ni_request_text(req, identifier, sizeof(identifier),
                         source, sizeof(source),
                         title, sizeof(title),
                         body, sizeof(body))) {
        if (gNIVisibleUntilUS != 0 && nowUS >= gNIVisibleUntilUS) gNIVisibleUntilUS = 0;
        return true;
    }

    bool sameID = (identifier[0] && strcmp(identifier, gNILastIdentifier) == 0);
    bool samePtr = (gNILastRequest == req);
    if ((sameID || samePtr) &&
        gNIVisibleUntilUS != 0 &&
        nowUS < gNIVisibleUntilUS &&
        nowUS - gNILastShowUS < kNotificationIslandRepeatUS) {
        (void)ni_withdraw_request(banner, dispatcher, req);
        return true;
    }

    bool shown = ni_activitykit_show(title, body, source, identifier);
    if (shown) {
        gNIActivityKitPrepared = true;
        gNIVisibleUntilUS = nowUS + kNotificationIslandVisibleUS;
        gNILastShowUS = nowUS;
    }
    bool withdrew = shown ? ni_withdraw_request(banner, dispatcher, req) : false;
    snprintf(gNILastIdentifier, sizeof(gNILastIdentifier), "%s", identifier);
    gNILastRequest = req;
    printf("[NISLAND] route id=%s req=0x%llx shown=%d withdraw=%d source='%s' title='%s'\n",
           gNILastIdentifier, req, shown, withdrew, source, title);
    return true;
}

bool notificationisland_show_sample_in_session(const char *title, const char *body)
{
    (void)title;
    (void)body;
    if (ni_activitykit_show_sample()) return true;
    printf("[NISLAND] sample unavailable: ActivityKit route failed and overlay fallback is disabled\n");
    return false;
}

bool notificationisland_stop_in_session(void)
{
    ni_cleanup_legacy_overlay_once();
    (void)ni_activitykit_end();
    gNIVisibleUntilUS = 0;
    gNILastRequest = 0;
    gNIActivityKitPrepared = false;
    gNILastPrepareAttemptUS = 0;
    gNILastIdentifier[0] = '\0';
    return true;
}

void notificationisland_forget_remote_state(void)
{
    gNIActivityKitPrepared = false;
    gNILegacyOverlayCleanupDone = false;
    gNILastRequest = 0;
    gNIVisibleUntilUS = 0;
    gNILastShowUS = 0;
    gNILastPrepareAttemptUS = 0;
    gNILastIdentifier[0] = '\0';
    gNIMissingBannerLogged = false;
    gNIMissingDispatcherLogged = false;
}

bool notificationisland_has_remote_state(void)
{
    return gNIActivityKitPrepared;
}
