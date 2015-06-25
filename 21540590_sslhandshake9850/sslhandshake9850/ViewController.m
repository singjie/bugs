//
//  ViewController.m
//  sslhandshake9850
//
//  Created by Lee Sing Jie on 25/6/15.
//  Copyright (c) 2015 Lee Sing Jie. All rights reserved.
//

#import "ViewController.h"

#import "GASocket.h"

#import <CFNetwork/CFNetwork.h>

@interface ViewController () <GASocketDelegate>

@property (nonatomic, strong) GASocket *socket;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.socket = [[GASocket alloc] initWithDelegate:self];
    self.socket.sslSettings = @{(id)kCFStreamSSLValidatesCertificateChain : @NO};
    [self.socket connectToHost:<#>];
}

#pragma mark - GASocketDelegate

- (void)socket:(GASocket *)socket didReceiveData:(NSData *)data
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void)socketDidConnect:(GASocket *)socket
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void)socketDidDisconnect:(GASocket *)socket
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

@end
