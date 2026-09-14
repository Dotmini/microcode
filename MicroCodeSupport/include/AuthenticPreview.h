//
//  AuthenticPreview.h
//  CodeTunner
//
//  Created by Tirawat Nantamas
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthenticPreviewGenerator : NSObject

/// Creates a native preview view (NSImageView, PDFView, etc.) for the given file URL.
+ (NSView *)createPreviewForURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
