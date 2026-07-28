//
//  appstoretools.h
//  One-shot App Store downgrade and update-blocking backends.
//


#ifndef appstoretools_h
#define appstoretools_h

#import <Foundation/Foundation.h>
#import "../TaskRop/RemoteCall.h"

bool appdowngrade_request_in_remote_session(RemoteCallSession *session,
                                            uint64_t itemID,
                                            uint64_t versionID,
                                            uint64_t accountID);

bool appupdateblocking_set_in_remote_session(RemoteCallSession *session,
                                             NSString *markerPath,
                                             bool blocked,
                                             int *remoteErrnoOut);

#endif /* appstoretools_h */
