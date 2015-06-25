//
//  GASocket.h
//  GA
//
//  Created by Lee Sing Jie on 13/1/15.
//  Copyright (c) 2015 Lee Sing Jie. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GASocket;

@protocol GASocketDelegate <NSObject>

- (void)socketDidConnect:(GASocket *)socket;
- (void)socketDidDisconnect:(GASocket *)socket;

- (void)socket:(GASocket *)socket didReceiveData:(NSData *)data;

@end

@interface GASocket : NSObject

@property (nonatomic, strong) NSDictionary *sslSettings;

- (id)initWithDelegate:(id<GASocketDelegate>)delegate;

- (void)connectToHost:(NSString *)host;

- (void)send:(NSData *)data;

- (void)stop;

@end
