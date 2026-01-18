//
//  AuthenticFileTreeController.h
//  CodeTunner
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lightweight File Node Structure
@interface AuthenticFileNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, strong) NSArray<AuthenticFileNode *> *children;
@property (nonatomic, assign) NSInteger depth;
@end

/// Controller for high-performance File Tree operations using native APIs
@interface AuthenticFileTreeController : NSObject

/// Shared Instance
+ (instancetype)sharedController;

/// Load contents of a directory synchronously (fast) or returns nil on error
- (nullable NSArray<AuthenticFileNode *> *)contentsOfDirectory:(NSString *)path error:(NSError **)error;

/// Load contents asynchronously
- (void)loadContentsOfDirectory:(NSString *)path completion:(void (^)(NSArray<AuthenticFileNode *> * _Nullable nodes, NSError * _Nullable error))completion;

/// Check if a path is a directory (Fast stat)
- (BOOL)isDirectory:(NSString *)path;

/// Check if file is hidden/system (Fast)
- (BOOL)isHidden:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
