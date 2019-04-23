//
//  GCDTask.m
//
//  Author: Darvell Long
//  Copyright (c) 2014 Reliablehosting.com. All rights reserved.
//

#import "GCDTask.h"
#define GCDTASK_BUFFER_MAX 4096

@implementation GCDTask

- (id) init
{
    return [super init];
}

- (void) launchWithOutputBlock: (void (^)(NSData* stdOutData)) stdOut
                 andErrorBlock: (void (^)(NSData* stdErrData)) stdErr
                      onLaunch: (void (^)(void)) launched
                        onExit: (void (^)(void)) exit
{
    executingTask = [[NSTask alloc] init];
    
    NSLog(@">>task:[%@],thread:[%@].",executingTask,[NSThread currentThread]);
 
    /* Set launch path. */
    [executingTask setLaunchPath:[_launchPath stringByStandardizingPath]];
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:[executingTask launchPath]])
    {
        @throw [NSException exceptionWithName:@"GCDTASK_INVALID_EXECUTABLE" reason:@"There is no executable at the path set." userInfo:nil];
    }

    /* Clean then set arguments. */
    for (id arg in _arguments)
    {
        if([arg class] != [NSString class])
        {
            NSMutableArray* cleanedArray = [[NSMutableArray alloc] init];
            /* Clean up required! */
            for (id arg in _arguments)
            {
                [cleanedArray addObject:[NSString stringWithFormat:@"%@",arg]];
            }
            [self setArguments:cleanedArray];
            break;
        }
    }

    [executingTask setArguments:_arguments];

    /* Setup pipes */
    stdinPipe = [NSPipe pipe];
    stdoutPipe = [NSPipe pipe];
    stderrPipe = [NSPipe pipe];
    
    [executingTask setStandardInput:stdinPipe];
    [executingTask setStandardOutput:stdoutPipe];
    [executingTask setStandardError:stderrPipe];
    
    /* Set current directory, just pass on our actual CWD. */
    /* TODO: Potentially make this changeable? Surely there's probably a nicer way to get the CWD too. */
    [executingTask setCurrentDirectoryPath:[[[NSFileManager alloc] init] currentDirectoryPath]];

    /* Ensure the pipes are non-blocking so GCD can read them correctly. */
    fcntl([stdoutPipe fileHandleForReading].fileDescriptor, F_SETFL, O_NONBLOCK);
    fcntl([stderrPipe fileHandleForReading].fileDescriptor, F_SETFL, O_NONBLOCK);
    
    /* Setup a dispatch source for both descriptors. */
    _stdoutSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,[stdoutPipe fileHandleForReading].fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    _stderrSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,[stderrPipe fileHandleForReading].fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    /* Set stdout source event handler to read data and send it out. */
    dispatch_source_set_event_handler(_stdoutSource, ^ {
        void* buffer = malloc(GCDTASK_BUFFER_MAX);
        ssize_t bytesRead;
        
        do
        {
            errno = 0;
            bytesRead = read([self->stdoutPipe fileHandleForReading].fileDescriptor, buffer, GCDTASK_BUFFER_MAX);
        } while(bytesRead == -1 && errno == EINTR);
        
        if(bytesRead > 0)
        {
            // Create before dispatch to prevent a race condition.
            NSData* dataToPass = [NSData dataWithBytes:buffer length:bytesRead];
            dispatch_async(dispatch_get_main_queue(), ^{
                if(!self->_hasExecuted)
                {
                    if(launched)
                        launched();
                    self->_hasExecuted = TRUE;
                }
                if(stdOut)
                {
                    stdOut(dataToPass);
                }
            });
        }
        
        if(errno != 0 && bytesRead <= 0)
        {
            dispatch_source_cancel(self->_stdoutSource);
            dispatch_async(dispatch_get_main_queue(), ^{
                if(exit)
                    exit();
            });
        }

        free(buffer);
    });
    
    /* Same thing for stderr. */
    dispatch_source_set_event_handler(_stderrSource, ^ {
        void* buffer = malloc(GCDTASK_BUFFER_MAX);
        ssize_t bytesRead;
        
        do
        {
            errno = 0;
            bytesRead = read([self->stderrPipe fileHandleForReading].fileDescriptor, buffer, GCDTASK_BUFFER_MAX);
        } while(bytesRead == -1 && errno == EINTR);
        
        if(bytesRead > 0)
        {
            NSData* dataToPass = [NSData dataWithBytes:buffer length:bytesRead];
            dispatch_async(dispatch_get_main_queue(), ^{
                if(stdErr)
                {
                    stdErr(dataToPass);
                }
            });
        }
        
        if(errno != 0 && bytesRead <= 0)
        {
            dispatch_source_cancel(self->_stderrSource);
        }
        
        free(buffer);
    });

    dispatch_resume(_stdoutSource);
    dispatch_resume(_stderrSource);

    executingTask.terminationHandler = ^(NSTask* task)
    {
        dispatch_source_cancel(self->_stdoutSource);
        dispatch_source_cancel(self->_stderrSource);
        if(exit)
            exit();
    };

    [executingTask launch];
}

- (BOOL) WriteStringToStandardInput: (NSString*) input
{
    return [self WriteDataToStandardInput:[input dataUsingEncoding:NSUTF8StringEncoding]];
}

/* Currently synchronous. TODO: Async fun! */
- (BOOL) WriteDataToStandardInput: (NSData*) input
{
    if (!stdinPipe || stdinPipe == nil)
    {
        GCDDebug(@"Standard input pipe does not exist.");
        return NO;
    }
    
    [[stdinPipe fileHandleForWriting] writeData:input];
    return YES;
}

/* If you don't like setting your own array. You really should never have a use for this. */
- (void) AddArgument: (NSString*) argument
{
    NSMutableArray* temp = [NSMutableArray arrayWithArray:_arguments];
    [temp addObject:argument];
    [self setArguments:temp];
}

- (void) RequestTermination
{
    /* Ask nicely for SIGINT, then SIGTERM. */
    [executingTask interrupt];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void)
    {
        [self->executingTask terminate];
    });
}


- (NSString *)cmd:(NSString *)cmd
{
    // 初始化并设置shell路径
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/bash"];
    // -c 用来执行string-commands（命令字符串），也就说不管后面的字符串里是什么都会被当做shellcode来执行
    NSArray *arguments = [NSArray arrayWithObjects: @"-c", cmd, nil];
    [task setArguments: arguments];
    
    // 新建输出管道作为Task的输出
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    // 开始task
    NSFileHandle *file = [pipe fileHandleForReading];
    [task launch];
    
    // 获取运行结果
    NSData *data = [file readDataToEndOfFile];
    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}


-(void)testDemo
{
    // 应使用下面这种方式实现
    [self cmd:@"cd Desktop; mkdir helloWorld"];
}
@end
