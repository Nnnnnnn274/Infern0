//
//  JSTweakDocsViewController.m
//  infern0
//

#import "JSTweakDocsViewController.h"

@implementation JSTweakDocsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    BOOL repoMode = (self.docsMode == JSTweakDocsModeSetupRepo);
    self.title = repoMode ? @"Set Up a Repo" : @"Build a JS Tweak";

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                         target:self action:@selector(dismiss)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
                                                              style:UIBarButtonItemStylePlain target:self action:@selector(copyToClipboard)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                               style:UIBarButtonItemStylePlain target:self action:@selector(shareMarkdown)];
    self.navigationItem.rightBarButtonItems = @[done, share, copy];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20.0;
    stack.alignment = UIStackViewAlignmentFill;
    [scroll addSubview:stack];

    CGFloat m = 20.0;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor      constraintEqualToAnchor:self.view.topAnchor],
        [scroll.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor      constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12.0],
        [stack.leadingAnchor  constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:m],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-m],
        [stack.bottomAnchor   constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28.0],
        [stack.widthAnchor    constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-m * 2],
    ]];

    if (repoMode) {
        [self buildRepoDocsInStack:stack];
    } else {
        [self buildTweakDocsInStack:stack];
    }
}

#pragma mark - Tweak writing docs

- (void)buildTweakDocsInStack:(UIStackView *)stack
{
    [stack addArrangedSubview:[self introCard:@"Build JavaScript Tweaks"
                                        body:@"Write .js scripts that run inside SpringBoard through infern0's RemoteCall bridge. Publish them as a source repo or load them locally with QuickLoader."
                                      credit:@"JavaScript engine contributed by @MinePlayer16"]];

    [stack addArrangedSubview:[self docCard:@"Writing a Tweak"
        body:@"A tweak is a plain .js file that runs inside JavaScriptCore. 64-bit pointers are passed as hex strings (e.g. \"0x105f2a000\"). Wrap your code in an IIFE:\n\n"
              "(() => {\n"
              "  log(\"Hello from my tweak!\");\n"
              "  var app = r_msg2(\n"
              "    r_class(\"UIApplication\"),\n"
              "    \"sharedApplication\");\n"
              "  var win = r_msg2(app, \"keyWindow\");\n"
              "  // …\n"
              "})();\n\n"
              "Use log() to print to infern0's Log tab. Use r_msg2_main() instead of r_msg2() for anything that touches UIKit views."]];

    [stack addArrangedSubview:[self docCard:@"Parameter Declaration"
        body:@"Add @param comments at the top of your script. infern0 parses them and generates native UI controls in Settings.\n\n"
              "Syntax:\n"
              "// @param: type | varName | Label | default | range\n\n"
              "Types:\n\n"
              "switch — Boolean toggle\n"
              "// @param: switch | enabled | Enable Tweak | true\n\n"
              "text — String text field\n"
              "// @param: text | label | Custom Text | Hello\n\n"
              "color — Hex color picker\n"
              "// @param: color | tint | Tint Color | #00FFCC\n\n"
              "slider — Numeric slider with range\n"
              "// @param: slider | radius | Blur | 5.0 | 0.0-10.0\n\n"
              "Default values auto-populate on first install. The slider shows a \"(Def)\" indicator when at the declared default."]];

    [stack addArrangedSubview:[self docCard:@"RemoteCall API"
        body:@"These functions are injected into every JS context:\n\n"
              "log(message)\n"
              "  Print to infern0's log console.\n\n"
              "r_class(name) → pointer\n"
              "  Get an Objective-C class pointer.\n"
              "  r_class(\"UIApplication\")\n\n"
              "r_sel(name) → pointer\n"
              "  Convert a string to a native SEL.\n\n"
              "r_nsstr(string) → pointer\n"
              "  Allocate an NSString in SpringBoard.\n"
              "  Call r_msg2(ptr, \"release\") when done.\n\n"
              "r_msg2(target, selector, a1, a2, a3, a4)\n"
              "  Send an ObjC message. Up to 4 args.\n\n"
              "r_msg2_main(target, selector, a1, a2, a3, a4)\n"
              "  Same but forced onto the main thread.\n"
              "  Required for all UIKit/view changes.\n\n"
              "r_responds(target, selector) → bool\n"
              "  Check if an object responds to a selector."]];

    [stack addArrangedSubview:[self docCard:@"Reading Parameters (QuickLoader)"
        body:@"QuickLoader scripts can read their @param values at runtime:\n\n"
              "r_pref_num(\"blurRadius\")   → float\n"
              "r_pref_bool(\"enableBlur\")  → boolean\n"
              "r_pref_str(\"tintColor\")    → string\n\n"
              "RepoTweaks scripts receive their parameters as pre-injected global variables instead."]];

    [stack addArrangedSubview:[self docCard:@"Timers"
        body:@"Standard timer functions are mapped to GCD background queues so they never block the UI:\n\n"
              "setInterval(fn, ms) → id\n"
              "clearInterval(id)\n"
              "setTimeout(fn, ms) → id\n"
              "clearTimeout(id)\n\n"
              "All active timers are automatically cancelled when the tweak is disabled or infern0 cleans up."]];

    [stack addArrangedSubview:[self docCard:@"Color Allocation Example"
        body:@"64-bit IPC can't pass CGFloat arrays directly. Allocate colors through CIColor:\n\n"
              "var hex = \"#00FFCC\".replace('#','');\n"
              "var r = parseInt(hex.substring(0,2),16)/255;\n"
              "var g = parseInt(hex.substring(2,4),16)/255;\n"
              "var b = parseInt(hex.substring(4,6),16)/255;\n"
              "var str = r_nsstr(r+\" \"+g+\" \"+b+\" 1.0\");\n"
              "var ci = r_msg2(\n"
              "  r_class(\"CIColor\"),\n"
              "  \"colorWithString:\", str);\n"
              "var ui = r_msg2(\n"
              "  r_class(\"UIColor\"),\n"
              "  \"colorWithCIColor:\", ci);\n"
              "r_msg2_main(view, \"setBackgroundColor:\", ui);\n"
              "r_msg2(str, \"release\");"]];

    [stack addArrangedSubview:[self docCard:@"Tips"
        body:@"• Always use r_msg2_main for view manipulation — r_msg2 on a background thread can crash SpringBoard.\n"
              "• Release r_nsstr allocations to avoid leaking memory in the SpringBoard process.\n"
              "• Use r_responds to check selectors before calling them — iOS versions differ.\n"
              "• Test locally with QuickLoader before publishing to a repo.\n"
              "• Only run and publish scripts you trust. JS tweaks have full RemoteCall access."]];
}

#pragma mark - Repo setup docs

- (void)buildRepoDocsInStack:(UIStackView *)stack
{
    [stack addArrangedSubview:[self introCard:@"Set Up a Tweak Repository"
                                        body:@"Host your JavaScript tweaks as an HTTPS JSON feed that infern0 users can add in the Sources tab. No server-side code needed — a GitHub Pages repo or any static file host works."
                                      credit:nil]];

    [stack addArrangedSubview:[self docCard:@"Repository JSON Format"
        body:@"Create a JSON file with this structure:\n\n"
              "{\n"
              "  \"repoName\": \"My Repo\",\n"
              "  \"author\": \"yourname\",\n"
              "  \"tweaks\": [\n"
              "    {\n"
              "      \"id\": \"my.tweak.id\",\n"
              "      \"name\": \"My Tweak\",\n"
              "      \"description\": \"What it does\",\n"
              "      \"version\": \"1.0.0\",\n"
              "      \"symbol\": \"sparkle\",\n"
              "      \"author\": \"tweakauthor\",\n"
              "      \"scriptURL\": \"https://…/tweak.js\"\n"
              "    }\n"
              "  ]\n"
              "}\n\n"
              "Host it at any HTTPS URL. Users paste this URL into infern0's Sources tab."]];

    [stack addArrangedSubview:[self docCard:@"Required Fields"
        body:@"repoName\n"
              "  Display name shown in the Sources list.\n\n"
              "author\n"
              "  Your name or handle.\n\n"
              "tweaks[].id\n"
              "  Unique identifier (e.g. \"myname.tweakname\").\n"
              "  Must be unique across your repo.\n\n"
              "tweaks[].name\n"
              "  Display name in the package list.\n\n"
              "tweaks[].description\n"
              "  Short description shown under the name.\n\n"
              "tweaks[].version\n"
              "  Semver string. infern0 compares this to\n"
              "  detect updates for installed tweaks.\n\n"
              "tweaks[].scriptURL\n"
              "  HTTPS URL to the .js file. infern0\n"
              "  downloads and caches it on refresh."]];

    [stack addArrangedSubview:[self docCard:@"Optional Fields"
        body:@"tweaks[].symbol\n"
              "  SF Symbol name for the tweak icon\n"
              "  (e.g. \"paintpalette.fill\", \"wind\").\n"
              "  Shown in Packages and Sources lists.\n"
              "  Defaults to a generic package icon.\n\n"
              "tweaks[].author\n"
              "  Per-tweak author. Overrides the repo-level\n"
              "  author for this tweak. Useful when your\n"
              "  repo hosts tweaks by different people.\n\n"
              "Custom icon images are not yet supported\n"
              "but are planned for a future update."]];

    [stack addArrangedSubview:[self docCard:@"Hosting with GitHub Pages"
        body:@"1. Create a public GitHub repo\n"
              "2. Add your .js tweak files\n"
              "3. Add a JSON file (e.g. tweaks.json)\n"
              "   pointing scriptURLs to the raw files:\n\n"
              "   \"scriptURL\":\n"
              "   \"https://yourname.github.io/repo/tweak.js\"\n\n"
              "4. Enable GitHub Pages in repo Settings\n"
              "   (Source: main branch, root folder)\n"
              "5. Share the JSON URL with users:\n"
              "   https://yourname.github.io/repo/tweaks.json"]];

    [stack addArrangedSubview:[self docCard:@"Updating Tweaks"
        body:@"To push an update:\n\n"
              "1. Update the .js file at the same URL\n"
              "2. Bump the version string in the JSON\n"
              "3. Commit and push\n\n"
              "infern0 checks for updates every few hours. When the repo version is newer than the installed version, the Sources tab shows an update badge. Users tap the tweak to reinstall the latest version."]];

    [stack addArrangedSubview:[self docCard:@"Multiple Tweaks"
        body:@"Add more entries to the tweaks array:\n\n"
              "\"tweaks\": [\n"
              "  { \"id\": \"me.hidedock\", … },\n"
              "  { \"id\": \"me.colordock\", … },\n"
              "  { \"id\": \"me.searchpill\", … }\n"
              "]\n\n"
              "Each tweak needs its own unique id and scriptURL. They all share the repo's author and repoName."]];

    [stack addArrangedSubview:[self docCard:@"Tips"
        body:@"• Use descriptive ids like \"yourname.tweakname\" to avoid collisions with other repos.\n"
              "• Keep descriptions short — they show as one or two lines in the package list.\n"
              "• Bump the version on every change so users get the update badge.\n"
              "• Test scripts locally with QuickLoader before adding them to your repo.\n"
              "• HTTPS is required — infern0 rejects HTTP URLs."]];
}

#pragma mark - Actions

- (void)dismiss
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyToClipboard
{
    [UIPasteboard generalPasteboard].string = [self markdownString];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:@"Copied to clipboard"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)shareMarkdown
{
    NSString *md = [self markdownString];
    NSString *name = (self.docsMode == JSTweakDocsModeSetupRepo) ? @"infern0-Repo-Setup.md" : @"infern0-JS-Tweak-Docs.md";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [md writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems[1];
    [self presentViewController:activity animated:YES completion:nil];
}

#pragma mark - Markdown

- (NSString *)markdownString
{
    if (self.docsMode == JSTweakDocsModeSetupRepo) return [self repoMarkdown];
    return [self tweakMarkdown];
}

- (NSString *)tweakMarkdown
{
    return
    @"# infern0 JavaScript Tweak Documentation\n\n"
    "JavaScript engine contributed by @MinePlayer16.\n\n"
    "---\n\n"
    "## Writing a Tweak\n\n"
    "A tweak is a plain .js file that runs inside JavaScriptCore. 64-bit pointers are hex strings. Wrap code in an IIFE:\n\n"
    "```javascript\n"
    "(() => {\n"
    "  log(\"Hello from my tweak!\");\n"
    "  var app = r_msg2(r_class(\"UIApplication\"), \"sharedApplication\");\n"
    "  var win = r_msg2(app, \"keyWindow\");\n"
    "})();\n"
    "```\n\n"
    "## Parameter Declaration\n\n"
    "```\n// @param: type | varName | Label | default | range\n```\n\n"
    "| Type | Example |\n|------|--------|\n"
    "| `switch` | `// @param: switch \\| enabled \\| Enable \\| true` |\n"
    "| `text` | `// @param: text \\| label \\| Text \\| Hello` |\n"
    "| `color` | `// @param: color \\| tint \\| Color \\| #00FFCC` |\n"
    "| `slider` | `// @param: slider \\| radius \\| Blur \\| 5.0 \\| 0.0-10.0` |\n\n"
    "## RemoteCall API\n\n"
    "| Function | Description |\n|----------|-------------|\n"
    "| `log(msg)` | Print to log |\n"
    "| `r_class(name)` | ObjC class pointer |\n"
    "| `r_sel(name)` | String → SEL |\n"
    "| `r_nsstr(str)` | Allocate NSString (release when done) |\n"
    "| `r_msg2(t,s,a1..a4)` | Send ObjC message |\n"
    "| `r_msg2_main(t,s,a1..a4)` | Send on main thread |\n"
    "| `r_responds(t,s)` | respondsToSelector check |\n\n"
    "## QuickLoader Prefs\n\n"
    "```javascript\nr_pref_num(\"key\")  // float\nr_pref_bool(\"key\") // bool\nr_pref_str(\"key\")  // string\n```\n\n"
    "## Timers\n\n"
    "```javascript\nsetInterval(fn, ms) / clearInterval(id)\nsetTimeout(fn, ms) / clearTimeout(id)\n```\n";
}

- (NSString *)repoMarkdown
{
    return
    @"# infern0 Repo Setup Guide\n\n"
    "## JSON Format\n\n"
    "```json\n"
    "{\n"
    "  \"repoName\": \"My Repo\",\n"
    "  \"author\": \"yourname\",\n"
    "  \"tweaks\": [\n"
    "    {\n"
    "      \"id\": \"my.tweak.id\",\n"
    "      \"name\": \"My Tweak\",\n"
    "      \"description\": \"What it does\",\n"
    "      \"version\": \"1.0.0\",\n"
    "      \"symbol\": \"sparkle\",\n"
    "      \"author\": \"tweakauthor\",\n"
    "      \"scriptURL\": \"https://…/tweak.js\"\n"
    "    }\n"
    "  ]\n"
    "}\n```\n\n"
    "## Required Fields\n\n"
    "- `repoName` — display name\n"
    "- `author` — your name\n"
    "- `tweaks[].id` — unique identifier\n"
    "- `tweaks[].name` — display name\n"
    "- `tweaks[].description` — short description\n"
    "- `tweaks[].version` — semver for update detection\n"
    "- `tweaks[].scriptURL` — HTTPS URL to .js file\n\n"
    "## Optional Fields\n\n"
    "- `tweaks[].symbol` — SF Symbol name for the tweak icon (e.g. `paintpalette.fill`, `wind`). Defaults to a generic package icon.\n"
    "- `tweaks[].author` — per-tweak author, overrides the repo-level author.\n\n"
    "Custom icon images are not yet supported but are planned for a future update.\n\n"
    "## GitHub Pages Hosting\n\n"
    "1. Create a public repo\n"
    "2. Add .js files and a JSON index\n"
    "3. Enable GitHub Pages (Settings → Pages → main branch)\n"
    "4. Share: `https://yourname.github.io/repo/tweaks.json`\n\n"
    "## Updating\n\n"
    "1. Update the .js file\n"
    "2. Bump the version in JSON\n"
    "3. Push — infern0 detects updates automatically\n";
}

#pragma mark - Card builders

- (UIView *)introCard:(NSString *)title body:(NSString *)body credit:(NSString *)credit
{
    UIView *card = [self makeCard];
    UIStackView *s = [self stackInCard:card];

    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    t.textColor = UIColor.labelColor;
    [s addArrangedSubview:t];

    UILabel *b = [[UILabel alloc] init];
    b.text = body;
    b.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    b.textColor = UIColor.secondaryLabelColor;
    b.numberOfLines = 0;
    [s addArrangedSubview:b];

    if (credit.length) {
        UILabel *c = [[UILabel alloc] init];
        c.text = credit;
        c.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        c.textColor = UIColor.tertiaryLabelColor;
        [s addArrangedSubview:c];
    }
    return card;
}

- (UIView *)docCard:(NSString *)title body:(NSString *)body
{
    UIView *card = [self makeCard];
    UIStackView *s = [self stackInCard:card];

    UILabel *h = [[UILabel alloc] init];
    h.text = title;
    h.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    h.textColor = UIColor.labelColor;
    [s addArrangedSubview:h];

    UILabel *b = [[UILabel alloc] init];
    b.numberOfLines = 0;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 2.5;
    b.attributedText = [[NSAttributedString alloc]
        initWithString:body attributes:@{
            NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:12.5] ?: [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
            NSParagraphStyleAttributeName: ps,
        }];
    [s addArrangedSubview:b];
    return card;
}

- (UIView *)makeCard
{
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    v.layer.cornerRadius = 14.0;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.04f;
    v.layer.shadowRadius = 8.0;
    v.layer.shadowOffset = CGSizeMake(0, 2);
    return v;
}

- (UIStackView *)stackInCard:(UIView *)card
{
    UIStackView *s = [[UIStackView alloc] init];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10.0;
    s.alignment = UIStackViewAlignmentFill;
    [card addSubview:s];
    CGFloat p = 16.0;
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:p],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:p],
        [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-p],
        [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-p],
    ]];
    return s;
}

@end
