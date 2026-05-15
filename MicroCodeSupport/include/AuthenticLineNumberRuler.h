#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthenticLineNumberRuler : NSRulerView

// Properties to be set from Swift (Theming)
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, strong) NSColor *separatorColor;
@property (nonatomic, strong) NSFont *font;

// Init
- (instancetype)initWithScrollView:(nullable NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation;

@end

NS_ASSUME_NONNULL_END
