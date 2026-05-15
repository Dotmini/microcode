//
//  AuthenticPreview.mm
//  CodeTunner
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

#import "AuthenticPreview.h"
#import <Quartz/Quartz.h> // For PDFKit (part of Quartz in some contexts or PDFKit framework)
#import <PDFKit/PDFKit.h> // Explicit import

#include <string>
#include <algorithm>
#include <vector>

@implementation AuthenticPreviewGenerator

+ (NSView *)createPreviewForURL:(NSURL *)url {
    if (!url) return [self createErrorView:@"Invalid URL"];
    
    // C++ Logic: Parse Extension
    std::string path = [url.path UTF8String];
    size_t lastDot = path.find_last_of(".");
    std::string extension = "";
    
    if (lastDot != std::string::npos) {
        extension = path.substr(lastDot + 1);
        std::transform(extension.begin(), extension.end(), extension.begin(), ::tolower);
    }
    
    // Check type using C++ vector search
    const std::vector<std::string> images = {"png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"};
    const std::vector<std::string> pdfs = {"pdf"};
    
    bool isImage = std::find(images.begin(), images.end(), extension) != images.end();
    bool isPDF = std::find(pdfs.begin(), pdfs.end(), extension) != pdfs.end();
    
    // ObjC View Creation
    if (isImage) {
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
        if (!image) return [self createErrorView:@"Failed to load image"];
        
        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.image = image;
        imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        imageView.animates = YES;
        return imageView;
    } 
    else if (isPDF) {
        PDFDocument *document = [[PDFDocument alloc] initWithURL:url];
        if (!document) return [self createErrorView:@"Failed to load PDF"];
        
        PDFView *pdfView = [[PDFView alloc] initWithFrame:NSZeroRect];
        pdfView.document = document;
        pdfView.autoScales = YES;
        pdfView.displayMode = kPDFDisplaySinglePageContinuous;
        
        // Optional: Background color
        // pdfView.backgroundColor = [NSColor controlBackgroundColor];
        return pdfView;
    }
    
    return [self createErrorView:@"Preview not available for this file type"];
}

+ (NSView *)createErrorView:(NSString *)message {
    NSTextField *label = [NSTextField labelWithString:message];
    label.alignment = NSTextAlignmentCenter;
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

@end
