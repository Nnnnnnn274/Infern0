//
//  appstoretools.m
//  StoreKitUI downgrade request and installd-owned update marker operations.
//

#import "appstoretools.h"
#import "remote_objc.h"
#import "../LogTextView.h"

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>

static uint64_t appstoretools_dlopen(RemoteCallSession *session, const char *path)
{
    uint64_t remotePath = r_session_alloc_str(session, path);
    if (!remotePath) return 0;
    uint64_t handle = [session doRemoteCallStableWithTimeout:5
                                               functionName:"dlopen"
                                                         x0:remotePath
                                                         x1:RTLD_LAZY | RTLD_GLOBAL
                                                         x2:0 x3:0 x4:0 x5:0 x6:0 x7:0];
    r_session_free(session, remotePath);
    return handle;
}

static void appstoretools_release(RemoteCallSession *session, uint64_t object)
{
    if (object) (void)r_session_msg2(session, object, "release", 0, 0, 0, 0);
}

static bool appstoretools_has_selector(RemoteCallSession *session,
                                       uint64_t object,
                                       const char *selectorName)
{
    uint64_t selector = r_session_sel(session, selectorName);
    if (!selector) return false;
    uint64_t implementation = r_session_msg2(session, object,
        "methodForSelector:", selector, 0, 0, 0);
    return implementation != 0;
}

bool appdowngrade_request_in_remote_session(RemoteCallSession *session,
                                            uint64_t itemID,
                                            uint64_t versionID,
                                            uint64_t accountID)
{
    if (!session || itemID == 0 || versionID == 0) return false;

    if (!appstoretools_dlopen(session,
            "/System/Library/PrivateFrameworks/StoreKitUI.framework/StoreKitUI")) {
        log_user("[DOWNGRADE] StoreKitUI could not be loaded in SpringBoard.\n");
        return false;
    }

    uint64_t offerClass = r_session_class(session, "SKUIItemOffer");
    uint64_t itemClass = r_session_class(session, "SKUIItem");
    uint64_t contextClass = r_session_class(session, "SKUIClientContext");
    uint64_t centerClass = r_session_class(session, "SKUIItemStateCenter");
    uint64_t stringClass = r_session_class(session, "NSString");
    uint64_t numberClass = r_session_class(session, "NSNumber");
    uint64_t dictionaryClass = r_session_class(session, "NSDictionary");
    uint64_t arrayClass = r_session_class(session, "NSArray");
    if (!offerClass || !itemClass || !contextClass || !centerClass ||
        !stringClass || !numberClass || !dictionaryClass || !arrayClass) {
        log_user("[DOWNGRADE] Required StoreKitUI/Foundation classes are unavailable.\n");
        return false;
    }

    NSString *adamID = [NSString stringWithFormat:@"%llu", itemID];
    NSString *buyParameters = [NSString stringWithFormat:
        @"productType=C&price=0&salableAdamId=%llu&pricingParameters=pricingParameter&appExtVrsId=%llu&clientBuyId=1&installed=0&trolled=1",
        itemID, versionID];

    uint64_t adamIDString = r_session_nsstr_retained(session, adamID.UTF8String);
    uint64_t buyParametersString = r_session_nsstr_retained(session, buyParameters.UTF8String);
    uint64_t softwareKindString = r_session_nsstr_retained(session, "iosSoftware");
    uint64_t buyParametersKey = r_session_nsstr_retained(session, "buyParams");
    uint64_t itemOfferKey = r_session_nsstr_retained(session, "_itemOffer");
    uint64_t itemKindKey = r_session_nsstr_retained(session, "_itemKindString");
    uint64_t versionKey = r_session_nsstr_retained(session, "_versionIdentifier");

    bool ok = false;
    uint64_t offerObject = 0;
    uint64_t itemObject = 0;
    @try {
        if (!adamIDString || !buyParametersString || !softwareKindString ||
            !buyParametersKey || !itemOfferKey || !itemKindKey || !versionKey) {
            log_user("[DOWNGRADE] Failed to allocate StoreKit strings.\n");
            return false;
        }

        uint64_t offerDictionary = r_session_msg2(session, dictionaryClass,
            "dictionaryWithObject:forKey:", buyParametersString, buyParametersKey, 0, 0);
        uint64_t itemDictionary = r_session_msg2(session, dictionaryClass,
            "dictionaryWithObject:forKey:", adamIDString, itemOfferKey, 0, 0);
        uint64_t versionNumber = r_session_msg2(session, numberClass,
            "numberWithUnsignedLongLong:", versionID, 0, 0, 0);
        if (!offerDictionary || !itemDictionary || !versionNumber) {
            log_user("[DOWNGRADE] Failed to construct StoreKit lookup dictionaries.\n");
            return false;
        }

        uint64_t offerAllocation = r_session_msg2(session, offerClass, "alloc", 0, 0, 0, 0);
        offerObject = r_session_msg2(session, offerAllocation,
            "initWithLookupDictionary:", offerDictionary, 0, 0, 0);
        uint64_t itemAllocation = r_session_msg2(session, itemClass, "alloc", 0, 0, 0, 0);
        itemObject = r_session_msg2(session, itemAllocation,
            "initWithLookupDictionary:", itemDictionary, 0, 0, 0);
        if (!offerObject || !itemObject) {
            log_user("[DOWNGRADE] SKUIItemOffer/SKUIItem initialization failed.\n");
            return false;
        }

        (void)r_session_msg2(session, itemObject, "setValue:forKey:",
                             offerObject, itemOfferKey, 0, 0);
        (void)r_session_msg2(session, itemObject, "setValue:forKey:",
                             softwareKindString, itemKindKey, 0, 0);
        (void)r_session_msg2(session, itemObject, "setValue:forKey:",
                             versionNumber, versionKey, 0, 0);

        uint64_t context = r_session_msg2(session, contextClass, "defaultContext", 0, 0, 0, 0);
        uint64_t center = r_session_msg2(session, centerClass, "defaultCenter", 0, 0, 0, 0);
        uint64_t items = r_session_msg2(session, arrayClass, "arrayWithObject:", itemObject, 0, 0, 0);
        bool hasNewPurchases = center && appstoretools_has_selector(
            session, center, "_newPurchasesWithItems:");
        bool hasPerformPurchases = center && appstoretools_has_selector(
            session, center,
            "_performPurchases:hasBundlePurchase:withClientContext:completionBlock:");
        log_user("[DOWNGRADE] StoreKitUI objects context=0x%llx center=0x%llx items=0x%llx.\n",
                 context, center, items);
        log_user("[DOWNGRADE] SKUIItemStateCenter selectors newPurchases=%d performPurchases=%d.\n",
                 hasNewPurchases ? 1 : 0,
                 hasPerformPurchases ? 1 : 0);
        if (!center || !items) {
            log_user("[DOWNGRADE] Required StoreKitUI center/items objects are unavailable.\n");
            return false;
        }
        if (!hasNewPurchases || !hasPerformPurchases) {
            log_user("[DOWNGRADE] Required SKUIItemStateCenter purchase selectors are unavailable.\n");
            return false;
        }
        if (!context) {
            log_user("[DOWNGRADE] SKUIClientContext.defaultContext returned nil; continuing with a nil client context.\n");
        }

        uint64_t purchases = r_session_msg2(session, center,
            "_newPurchasesWithItems:", items, 0, 0, 0);
        uint64_t purchaseCount = purchases
            ? r_session_msg2(session, purchases, "count", 0, 0, 0, 0)
            : 0;
        if (!purchases || purchaseCount == 0) {
            log_user("[DOWNGRADE] StoreKitUI did not create a purchase object.\n");
            return false;
        }

        if (accountID != 0) {
            uint64_t accountNumber = r_session_msg2(session, numberClass,
                "numberWithUnsignedLongLong:", accountID, 0, 0, 0);
            uint64_t bound = 0;
            for (uint64_t i = 0; i < purchaseCount; i++) {
                uint64_t purchase = r_session_msg2(session, purchases,
                    "objectAtIndex:", i, 0, 0, 0);
                if (purchase && accountNumber && appstoretools_has_selector(
                    session, purchase, "setAccountIdentifier:")) {
                    (void)r_session_msg2(session, purchase, "setAccountIdentifier:",
                                         accountNumber, 0, 0, 0);
                    bound++;
                }
            }
            log_user("[DOWNGRADE] Bound %llu/%llu purchase object(s) to the installed app account.\n",
                     bound, purchaseCount);
        } else {
            log_user("[DOWNGRADE] Installed app account ID is unavailable; StoreKitUI will choose an account.\n");
        }

        log_user("[DOWNGRADE] Dispatching App Store request item=%llu version=%llu.\n",
                 itemID, versionID);
        (void)r_session_msg2(session, center,
            "_performPurchases:hasBundlePurchase:withClientContext:completionBlock:",
            purchases, 0, context, 0);
        ok = true;
    } @finally {
        appstoretools_release(session, itemObject);
        appstoretools_release(session, offerObject);
        appstoretools_release(session, adamIDString);
        appstoretools_release(session, buyParametersString);
        appstoretools_release(session, softwareKindString);
        appstoretools_release(session, buyParametersKey);
        appstoretools_release(session, itemOfferKey);
        appstoretools_release(session, itemKindKey);
        appstoretools_release(session, versionKey);
    }
    return ok;
}

static int appstoretools_remote_errno(RemoteCallSession *session)
{
    uint64_t errnoAddress = [session doRemoteCallStableWithTimeout:2
                                                     functionName:"__error"
                                                               x0:0 x1:0 x2:0 x3:0
                                                               x4:0 x5:0 x6:0 x7:0];
    int value = 0;
    if (errnoAddress) [session remoteRead:errnoAddress to:&value size:sizeof(value)];
    return value;
}

bool appupdateblocking_set_in_remote_session(RemoteCallSession *session,
                                             NSString *markerPath,
                                             bool blocked,
                                             int *remoteErrnoOut)
{
    if (remoteErrnoOut) *remoteErrnoOut = 0;
    if (!session || markerPath.length == 0) return false;

    uint64_t path = r_session_alloc_str(session, markerPath.fileSystemRepresentation);
    if (!path) return false;

    bool ok = false;
    int remoteErrno = 0;
    if (blocked) {
        uint64_t mkdirResult = [session doRemoteCallStableWithTimeout:3
                                                        functionName:"mkdir"
                                                                  x0:path x1:0755
                                                                  x2:0 x3:0 x4:0 x5:0 x6:0 x7:0];
        if (mkdirResult == UINT64_MAX) remoteErrno = appstoretools_remote_errno(session);
        bool exists = mkdirResult == 0 || remoteErrno == EEXIST;
        if (exists) {
            uint64_t chmodResult = [session doRemoteCallStableWithTimeout:3
                                                             functionName:"chmod"
                                                                       x0:path x1:0000
                                                                       x2:0 x3:0 x4:0 x5:0 x6:0 x7:0];
            ok = (chmodResult == 0);
            if (!ok) remoteErrno = appstoretools_remote_errno(session);
        }
    } else {
        (void)[session doRemoteCallStableWithTimeout:3
                                       functionName:"chmod"
                                                 x0:path x1:0755
                                                 x2:0 x3:0 x4:0 x5:0 x6:0 x7:0];
        uint64_t removeResult = [session doRemoteCallStableWithTimeout:3
                                                          functionName:"rmdir"
                                                                    x0:path
                                                                    x1:0 x2:0 x3:0 x4:0 x5:0 x6:0 x7:0];
        if (removeResult == 0) {
            ok = true;
        } else {
            remoteErrno = appstoretools_remote_errno(session);
            ok = (remoteErrno == ENOENT);
        }
    }

    r_session_free(session, path);
    if (remoteErrnoOut) *remoteErrnoOut = remoteErrno;
    log_user("[UPDATE-BLOCK] %s marker %s result=%d errno=%d.\n",
             blocked ? "create" : "remove",
             markerPath.UTF8String,
             ok ? 1 : 0,
             remoteErrno);
    return ok;
}
