//
//  AppDelegate.m
//  Unrar
//
//  Created by BP on 22/04/2019.
//  Copyright © 2019 BP. All rights reserved.
//

#import "AppDelegate.h"
#import "GCDTask.h"
@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
}
- (IBAction)unrar:(id)sender {
    //获取unrar的路径
    NSString * path = [[NSBundle mainBundle] pathForResource:@"unrar" ofType:@""];
    //获取解压路径，解压路径与待解压文件路径相同
    NSString * unrarPath = [_filePath.stringValue stringByReplacingOccurrencesOfString:@".rar" withString:@""];
    //拼接解压命令
    NSString * shellCommand = [NSString stringWithFormat:@"%@ x \"%@\" \"%@\"",path,_filePath.stringValue,unrarPath];
    NSLog(@"%@",shellCommand);
    //若解压路径不存在就新建一个
    if (![[NSFileManager defaultManager] fileExistsAtPath:unrarPath])
    {
        BOOL makeDir = [[NSFileManager defaultManager] createDirectoryAtPath:unrarPath withIntermediateDirectories:YES attributes:nil error:nil];
        if (!makeDir) {
            NSLog(@"Create path error");
        }
    }
    //若没有待解压路径则直接返回。
    if ([_filePath.stringValue isEqualToString:@""]) {
        return;
    }
    [self runTaskCmd:shellCommand];
}

-(void)runTaskCmd:(NSString *)shell
{
    GCDTask * task = [[GCDTask alloc] init];
    [task setArguments:@[@"-c",shell]];
    [task setLaunchPath:@"/bin/sh"];
    
    [task launchWithOutputBlock:^(NSData *stdOutData) {
        NSString* output = [[NSString alloc] initWithData:stdOutData encoding:NSUTF8StringEncoding];
        //[self logInfo:output];
        NSLog(@"%@",output);
    } andErrorBlock:^(NSData *stdErrData) {
        NSString* output = [[NSString alloc] initWithData:stdErrData encoding:NSUTF8StringEncoding];
        NSLog(@"%@",output);
    } onLaunch:^{
        NSLog(@"Task has started running.");
    } onExit:^{
        NSLog(@"Task has now quit.");
    }];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}
@end
