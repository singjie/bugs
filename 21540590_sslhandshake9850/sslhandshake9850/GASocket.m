//
//  GASocket.m
//  GA
//
//  Created by Lee Sing Jie on 13/1/15.
//  Copyright (c) 2015 Lee Sing Jie. All rights reserved.
//

#import "GASocket.h"

#import <netinet/tcp.h>
#import <netinet/in.h>
#import <arpa/inet.h>


/* https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/Streams/Articles/WritingOutputStreams.html
 The best approach is to use some reasonable buffer size, such as 512 bytes,
 one kilobyte (as in the example above), or a page size (four kilobytes) */


#define GASOCKET_STRINGIFY(v) #v
#define GASOCKET_CASE(x) case x : return @GASOCKET_STRINGIFY(x);

static NSInteger const kBufferSize = 512;

static NSString *streamStatusFromCode(NSInteger code)
{
    switch (code) {
            GASOCKET_CASE(NSStreamStatusNotOpen);
            GASOCKET_CASE(NSStreamStatusOpening);
            GASOCKET_CASE(NSStreamStatusOpen);
            GASOCKET_CASE(NSStreamStatusReading);
            GASOCKET_CASE(NSStreamStatusWriting);
            GASOCKET_CASE(NSStreamStatusAtEnd);
            GASOCKET_CASE(NSStreamStatusClosed);
            GASOCKET_CASE(NSStreamStatusError);
    }

    return nil;
}

static NSString *eventStringFromCode(NSInteger code)
{
    switch (code) {
            GASOCKET_CASE(NSStreamEventNone);
            GASOCKET_CASE(NSStreamEventOpenCompleted);
            GASOCKET_CASE(NSStreamEventHasBytesAvailable);
            GASOCKET_CASE(NSStreamEventHasSpaceAvailable);
            GASOCKET_CASE(NSStreamEventErrorOccurred);
            GASOCKET_CASE(NSStreamEventEndEncountered);
    }

    return nil;
}

typedef NS_OPTIONS(NSUInteger, GASocketFlag)
{
    GASocketFlagInputOpen = 1 << 0,
    GASocketFlagOutputOpen = 1 << 1,
    GASocketFlagHasSpaceAvailable = 1 << 2,
};

@interface GASocket () <NSStreamDelegate>

@property (nonatomic, weak) id <GASocketDelegate> delegate;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;

@property (nonatomic, assign) NSUInteger flags;

@property (nonatomic, strong) NSMutableData *outputPacket;

@end

@implementation GASocket

- (id)initWithDelegate:(id<GASocketDelegate>)delegate
{
    self = [super init];

    if (self) {
        self.delegate = delegate;
    }

    return self;
}

- (void)connectToHost:(NSString *)host
{
    NSParameterAssert([NSThread isMainThread]);
    [self logData:@"%@ - %@", NSStringFromSelector(_cmd), host];

    if (self.inputStream || self.outputStream) {
        return;
    }

    NSArray *components = [host componentsSeparatedByString:@":"];

    if (components.count != 2) {
        return;
    }

    NSString *hostname = components[0];
    NSString *port = components[1];

    uint32_t portValue = (uint32_t)[port integerValue];

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)hostname,
                                       portValue,
                                       &readStream,
                                       &writeStream);

    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket,
                            kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket,
                             kCFBooleanTrue);

    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;

    self.inputStream.delegate = self;
    self.outputStream.delegate = self;

    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

    [self.inputStream open];
    [self.outputStream open];

    self.outputPacket = [NSMutableData data];

    if ([self.sslSettings count]) {
        [self.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                               forKey:NSStreamSocketSecurityLevelKey];
        [self.outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                                forKey:NSStreamSocketSecurityLevelKey];

        BOOL r1 = CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(self.sslSettings));
        BOOL r2 = CFWriteStreamSetProperty(writeStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(self.sslSettings));

        if (!r1 || !r2) {
            [self onDisconnected];
            return;
        }
    }

    [self logData:@"Connecting to %@", host];
}

- (void)send:(NSData *)data
{
    [self logData:@"%@", NSStringFromSelector(_cmd)];

    [self.outputPacket appendData:data];

    [self processQueue];
}

- (void)stop
{
    [self logData:@"%@", NSStringFromSelector(_cmd)];

    self.inputStream.delegate = nil;
    self.outputStream.delegate = nil;

    [self.inputStream close];
    [self.outputStream close];

    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSRunLoopCommonModes];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                 forMode:NSRunLoopCommonModes];

    self.outputPacket.length = 0;

    self.inputStream = nil;
    self.outputStream = nil;
    self.flags = 0;
}

- (void)processQueue
{
    [self logData:@"%@", NSStringFromSelector(_cmd)];

    if ((self.flags & GASocketFlagHasSpaceAvailable) == 0) {
        return;
    }

    if (self.outputPacket.length <= 0) {
        return;
    }

    self.flags &= ~GASocketFlagHasSpaceAvailable;

    NSInteger written = [self.outputStream write:self.outputPacket.bytes
                                       maxLength:MIN(kBufferSize, self.outputPacket.length)];

    if (written <= 0) {
        [self onDisconnected];
        return;
    }

    [self logData:@"Written:%zd bytes", written];

    [self.outputPacket replaceBytesInRange:NSMakeRange(0, written)
                                 withBytes:NULL
                                    length:0];
}

#pragma mark - Delegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    NSParameterAssert([NSThread isMainThread]);
    [self logData:@"================="];
    [self logData:@"%@", NSStringFromSelector(_cmd)];
    [self logData:@"code:%@", eventStringFromCode(eventCode)];
    [self logData:@"status:%@", streamStatusFromCode(aStream.streamStatus)];
    [self logData:@"================="];

    if (aStream != self.inputStream && aStream != self.outputStream) {
        NSParameterAssert(NO);
        return;
    }
    {
        NSArray *certs = [self.inputStream propertyForKey: (__bridge NSString *)kCFStreamPropertySSLPeerCertificates];
        SecTrustRef trust = (__bridge SecTrustRef)[self.inputStream propertyForKey: (__bridge NSString *)kCFStreamPropertySSLPeerTrust];

        [self logData:@"Certs:%@ Trust:%@", certs, trust];
    }

    switch (eventCode) {
        case NSStreamEventHasSpaceAvailable:
            self.flags |= GASocketFlagHasSpaceAvailable;
            [self processQueue];
            break;
        case NSStreamEventHasBytesAvailable:
        {
            NSMutableData *allData = [NSMutableData data];
            while ([self.inputStream hasBytesAvailable]) {
                NSMutableData *incomingData = [NSMutableData dataWithLength:kBufferSize];

                NSInteger readBytes = [self.inputStream read:(uint8_t *)incomingData.bytes
                                                   maxLength:kBufferSize];

                [self logData:@"Read Bytes:%zd", readBytes];

                if (readBytes <= 0) {
                    [self onDisconnected];
                    return;
                }

                incomingData.length = readBytes;

                [allData appendData:incomingData];
            }

            if (allData.length) {
                [self onReceiveData:allData];
            }
        }
            break;
        case NSStreamEventEndEncountered:
        case NSStreamEventErrorOccurred:
            [self onDisconnected];
            break;
        case NSStreamEventNone:
            break;
        case NSStreamEventOpenCompleted:
            if (aStream == self.inputStream) {
                self.flags |= GASocketFlagInputOpen;
            }

            if (aStream == self.outputStream) {
                self.flags |= GASocketFlagOutputOpen;
            }

            GASocketFlag isOpen = GASocketFlagInputOpen|GASocketFlagOutputOpen;

            if ((self.flags & isOpen) == isOpen) {
                [self onConnected];
            }
            break;
        default:
            break;
    }
}

- (void)onReceiveData:(NSData *)data
{
    [self logData:@"%@", NSStringFromSelector(_cmd)];

    [self logData:@"Received :%zd bytes", data.length];

    [self.delegate socket:self didReceiveData:data];
}

- (void)onConnected
{
    [self logData:@"%@", NSStringFromSelector(_cmd)];

    [self.delegate socketDidConnect:self];
}

- (void)onDisconnected
{
    self.flags = 0;

    [self logData:@"%@", NSStringFromSelector(_cmd)];

    [self.delegate socketDidDisconnect:self];
}

- (void)dealloc
{
    [self logData:@"%@", NSStringFromSelector(_cmd)];
}

- (void)logData:(NSString *)formatString, ...
{
    va_list vaArguments;
    va_start(vaArguments, formatString);
    NSString *logString = [[NSString alloc] initWithFormat:formatString arguments:vaArguments];
    va_end(vaArguments);

    NSLog(@"[%@]: %@", self, logString);
}

@end
