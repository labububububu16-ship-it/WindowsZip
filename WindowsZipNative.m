#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>

@interface WindowsZipAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSTask *compressionTask;
@property(nonatomic, assign) BOOL didStart;
@property(nonatomic, strong) NSOpenPanel *sourcePanel;
@end

@implementation WindowsZipAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    if ([self startFromCommandLineIfPresent]) {
        return;
    }
    [self presentSourcePicker];
}

- (BOOL)startFromCommandLineIfPresent {
    NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
    if (arguments.count < 2) {
        return NO;
    }
    [self startCompressionWithURLs:@[[NSURL fileURLWithPath:arguments[1]]]];
    return YES;
}

- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames {
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:filenames.count];
    for (NSString *filename in filenames) {
        [urls addObject:[NSURL fileURLWithPath:filename]];
    }
    [self startCompressionWithURLs:urls];
    [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    [self startCompressionWithURLs:urls];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // The app is one-shot: closing it must also stop its own compressor.
    if (self.compressionTask.isRunning) {
        pid_t pid = self.compressionTask.processIdentifier;
        [self.compressionTask terminate];
        if (pid > 0) {
            kill(pid, SIGKILL);
        }
    }
    return NSTerminateNow;
}

- (void)presentSourcePicker {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.title = @"选择要压缩的文件或文件夹";
    panel.prompt = @"开始压缩";
    self.sourcePanel = panel;

    __weak typeof(self) weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        __strong typeof(weakSelf) self = weakSelf;
        self.sourcePanel = nil;
        if (response == NSModalResponseOK && panel.URL != nil) {
            [self startCompressionWithURLs:@[panel.URL]];
        } else {
            [NSApp terminate:nil];
        }
    }];
}

- (void)startCompressionWithURLs:(NSArray<NSURL *> *)urls {
    if (self.didStart) {
        return;
    }
    self.didStart = YES;

    if (urls.count == 0) {
        [self showError:@"没有收到要压缩的文件或文件夹。"];
        return;
    }
    if (urls.count > 1) {
        [self showError:@"一次只能压缩一个文件或文件夹。源文件不会被删除，请重新拖入一个项目。"];
        return;
    }

    NSURL *source = urls.firstObject;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:source.path isDirectory:&isDirectory]) {
        [self showError:[NSString stringWithFormat:@"找不到源文件或文件夹：\n%@", source.path]];
        return;
    }

    NSURL *output = [self nextOutputURLForSource:source isDirectory:isDirectory];
    NSString *logDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MacWindowsZip"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDirectory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
    NSString *logPath = [logDirectory stringByAppendingPathComponent:@"compression.log"];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/zip";
    task.currentDirectoryPath = source.URLByDeletingLastPathComponent.path;
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
        @"-r",
        @"-X",
        @"-q",
        output.path,
        source.lastPathComponent,
        @"-x"
    ]];
    [arguments addObjectsFromArray:@[
        @"*/.DS_Store",
        @"*/._*",
        @"*/__MACOSX",
        @"*/__MACOSX/*",
        @"*/.AppleDouble",
        @"*/.AppleDouble/*",
        @"*/.AppleDesktop",
        @"*/.AppleDesktop/*",
        @"*/.LSOverride",
        @"*/.Spotlight-V100",
        @"*/.Spotlight-V100/*",
        @"*/.Trashes",
        @"*/.Trashes/*",
        @"*/.fseventsd",
        @"*/.fseventsd/*",
        @"*/.TemporaryItems",
        @"*/.TemporaryItems/*",
        @"*/.DocumentRevisions-V100",
        @"*/.DocumentRevisions-V100/*",
        @"*/.VolumeIcon.icns",
        @"*/.metadata_never_index",
        @"*/.com.apple.timemachine.donotpresent",
        @"*/Icon\r",
        @"*/.localized"
    ]];
    task.arguments = arguments;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    self.compressionTask = task;
    [NSApp requestUserAttention:NSInformationalRequest];

    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        [text writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            self.compressionTask = nil;

            BOOL outputExists = [[NSFileManager defaultManager] fileExistsAtPath:output.path];
            if (finishedTask.terminationStatus == 0 && outputExists) {
                [self revealInFinder:output];
                [self showSuccess:output];
            } else {
                NSString *details = [text stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *message = details.length > 0
                    ? [NSString stringWithFormat:@"压缩失败，未生成 ZIP。\n\n%@", details]
                    : @"压缩失败，未生成 ZIP。请确认源文件仍可访问。";
                [self showError:message];
            }
        });
    };

    @try {
        [task launch];
    } @catch (NSException *exception) {
        self.compressionTask = nil;
        [self showError:[NSString stringWithFormat:@"无法启动压缩引擎：\n%@", exception.reason ?: @"未知错误"]];
    }
}

- (void)revealInFinder:(NSURL *)output {
    // `open -R` is Finder's explicit "Show in Finder" operation and reliably
    // opens the containing folder while selecting the generated ZIP.
    NSTask *finderTask = [[NSTask alloc] init];
    finderTask.launchPath = @"/usr/bin/open";
    finderTask.arguments = @[@"-R", output.path];
    @try {
        [finderTask launch];
    } @catch (NSException *exception) {
        [[NSWorkspace sharedWorkspace] selectFile:output.path
                          inFileViewerRootedAtPath:output.URLByDeletingLastPathComponent.path];
    }
}

- (NSURL *)nextOutputURLForSource:(NSURL *)source isDirectory:(BOOL)isDirectory {
    NSString *sourceName = source.lastPathComponent;
    NSString *baseName = isDirectory ? sourceName : source.URLByDeletingPathExtension.lastPathComponent;
    if (baseName.length == 0) {
        baseName = sourceName;
    }

    NSURL *directory = source.URLByDeletingLastPathComponent;
    NSString *firstName = [NSString stringWithFormat:@"%@-Windows.zip", baseName];
    NSURL *candidate = [directory URLByAppendingPathComponent:firstName];
    NSUInteger index = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        NSString *name = [NSString stringWithFormat:@"%@-Windows %lu.zip", baseName, (unsigned long)index++];
        candidate = [directory URLByAppendingPathComponent:name];
    }
    return candidate;
}

- (void)showSuccess:(NSURL *)output {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"压缩完成";
    alert.informativeText = [NSString stringWithFormat:@"已生成并打开所在文件夹：\n%@", output.path];
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
    [NSApp terminate:nil];
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Windows 压缩包";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        WindowsZipAppDelegate *delegate = [[WindowsZipAppDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
