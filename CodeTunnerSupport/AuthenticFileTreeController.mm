//
//  AuthenticFileTreeController.mm
//  CodeTunner
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

#import "AuthenticFileTreeController.h"
#include <sys/stat.h>
#include <dirent.h>
#include <vector>
#include <string>
#include <algorithm>

@implementation AuthenticFileNode
@end

@implementation AuthenticFileTreeController

+ (instancetype)sharedController {
    static AuthenticFileTreeController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AuthenticFileTreeController alloc] init];
    });
    return shared;
}

- (BOOL)isDirectory:(NSString *)path {
    const char *cPath = [path fileSystemRepresentation];
    struct stat sb;
    if (stat(cPath, &sb) == 0) {
        return S_ISDIR(sb.st_mode);
    }
    return NO;
}

- (BOOL)isHidden:(NSString *)path {
    return [[path lastPathComponent] hasPrefix:@"."];
}

- (NSArray<AuthenticFileNode *> *)contentsOfDirectory:(NSString *)path error:(NSError **)error {
    if (!path) return nil;
    
    @try {
        const char *cPath = [path fileSystemRepresentation];
        if (!cPath) return nil;
        
        DIR *dir = opendir(cPath);
        
        if (!dir) {
            if (error) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            }
            return nil;
        }
        
        NSMutableArray<AuthenticFileNode *> *nodes = [NSMutableArray array];
        
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            // Skip . and ..
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
            
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            if (!name) {
                // Try MacOS Roman or lossy conversion if UTF8 fails
                name = [[NSString alloc] initWithCString:entry->d_name encoding:NSMacOSRomanStringEncoding];
                if (!name) continue; 
            }
            
            // Skip hidden files if preferred (configured?)
            if ([name hasPrefix:@"."]) continue;
            
            NSString *fullPath = [path stringByAppendingPathComponent:name];
            
            BOOL isDir = (entry->d_type == DT_DIR);
            if (entry->d_type == DT_UNKNOWN || entry->d_type == DT_LNK) {
                // Fallback to stat
                struct stat sb;
                if (stat([fullPath fileSystemRepresentation], &sb) == 0) {
                    isDir = S_ISDIR(sb.st_mode);
                }
            }
            
            AuthenticFileNode *node = [[AuthenticFileNode alloc] init];
            node.name = name;
            node.path = fullPath;
            node.isDirectory = isDir;
            node.isExpanded = NO;
            node.depth = 0;
            node.children = @[];
            
            [nodes addObject:node];
        }
        closedir(dir);
        
        // Sort: Directories first, then Files. Alphabetical.
        [nodes sortUsingComparator:^NSComparisonResult(AuthenticFileNode *node1, AuthenticFileNode *node2) {
            if (node1.isDirectory != node2.isDirectory) {
                return node1.isDirectory ? NSOrderedAscending : NSOrderedDescending;
            }
            return [node1.name localizedStandardCompare:node2.name];
        }];
        
        return nodes;
    } @catch (NSException *exception) {
        NSLog(@"[AuthenticFileTreeController] CRASH PREVENTED: %@", exception);
        if (error) {
            *error = [NSError errorWithDomain:@"AuthenticError" code:500 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown Exception"}];
        }
        return @[];
    }
}

- (void)loadContentsOfDirectory:(NSString *)path completion:(void (^)(NSArray<AuthenticFileNode *> * _Nullable, NSError * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSArray *nodes = [self contentsOfDirectory:path error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nodes, error);
        });
    });
}

@end
