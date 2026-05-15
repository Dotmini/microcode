#import "AuthenticLineNumberRuler.h"

@implementation AuthenticLineNumberRuler

- (instancetype)initWithScrollView:(nullable NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation {
    self = [super initWithScrollView:scrollView orientation:orientation];
    if (self) {
        self.ruleThickness = 40.0;
        // Default colors if not set
        self.backgroundColor = [NSColor textBackgroundColor];
        self.textColor = [NSColor secondaryLabelColor];
        self.separatorColor = [[NSColor textColor] colorWithAlphaComponent:0.1];
        self.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    }
    return self;
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    // 1. Draw Background
    if (self.backgroundColor) {
        [self.backgroundColor setFill];
        NSRectFill(rect);
    }
    
    // 2. Draw Separator
    if (self.separatorColor) {
        [self.separatorColor setStroke];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMaxX(self.bounds) - 1, NSMinY(self.bounds))];
        [path lineToPoint:NSMakePoint(NSMaxX(self.bounds) - 1, NSMaxY(self.bounds))];
        [path setLineWidth:1.0];
        [path stroke];
    }
    
    // Ensure we have a client view
    NSTextView *textView = (NSTextView *)self.clientView;
    if (![textView isKindOfClass:[NSTextView class]]) {
        return;
    }
    
    NSLayoutManager *layoutManager = textView.layoutManager;
    NSTextContainer *textContainer = textView.textContainer;
    if (!layoutManager || !textContainer) {
        return;
    }
    
    // 3. Calculate Visible Range
    NSRect visibleRect = self.scrollView.contentView.bounds;
    NSRange glyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:textContainer];
    
    NSString *string = textView.string;
    NSUInteger length = string.length;
    
    // 4. Calculate starting line number
    // Count newlines before the visible range start
    NSUInteger startCharIndex = [layoutManager characterIndexForGlyphAtIndex:glyphRange.location];
    
    __block NSInteger lineNumber = 1;
    if (startCharIndex > 0) {
        // Linear scan for newlines (simple but effective for now)
        // In minimal optimized C++ we could do this faster with direct buffer access if needed
        NSString *precedingText = [string substringToIndex:startCharIndex];
        
        NSUInteger count = 0, length = [precedingText length];
        NSRange range = NSMakeRange(0, length);
        while(range.location != NSNotFound)
        {
            range = [precedingText rangeOfString:@"\n" options:0 range:range];
            if(range.location != NSNotFound)
            {
                range = NSMakeRange(range.location + range.length, length - (range.location + range.length));
                count++; 
            }
        }
        lineNumber += count;
    }
    
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: self.textColor
    };
    
    // 5. Enumerate Lines
    [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange usingBlock:^(NSRect rect, NSRect usedRect, NSTextContainer * _Nonnull textContainer, NSRange glyphRange, BOOL * _Nonnull stop) {
        
        NSRange charRange = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
        BOOL isNewLine = YES;
        
        if (charRange.location > 0) {
            if (charRange.location - 1 < length) {
                unichar prevChar = [string characterAtIndex:charRange.location - 1];
                if (prevChar != 10) { // '\n'
                    isNewLine = NO;
                }
            }
        }
        
        if (isNewLine) {
            NSString *numStr = [NSString stringWithFormat:@"%ld", (long)lineNumber];
            NSSize size = [numStr sizeWithAttributes:attributes];
            
            // Calculate Y
            // rect.origin.y is in container coordinates
            CGFloat yPos = rect.origin.y + textView.textContainerInset.height;
            
            // Map to ruler view coordinates
            NSPoint pt = [self convertPoint:NSMakePoint(0, yPos) fromView:textView];
            
            // Center vertically
            CGFloat centeredY = pt.y + (rect.size.height - size.height) / 2.0;
            
            NSPoint drawPoint = NSMakePoint(self.ruleThickness - size.width - 8, centeredY);
            
            [numStr drawAtPoint:drawPoint withAttributes:attributes];
            
            lineNumber++;
        }
    }];
}

@end
