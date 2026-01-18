#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/serial/IOSerialKeys.h>
#import <IOKit/usb/IOUSBLib.h>
#import "include/bridge.h"

@interface USBDetector : NSObject
@end

@implementation USBDetector

static IONotificationPortRef notificationPort;

static void deviceAdded(void *refCon, io_iterator_t iterator) {
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        // Get VID/PID
        NSNumber *vid = (__bridge_transfer NSNumber *)IORegistryEntryCreateCFProperty(service, CFSTR(kUSBVendorID), kCFAllocatorDefault, 0);
        NSNumber *pid = (__bridge_transfer NSNumber *)IORegistryEntryCreateCFProperty(service, CFSTR(kUSBProductID), kCFAllocatorDefault, 0);
        
        // Try to get serial path (callout device)
        NSString *bsdPath = (__bridge_transfer NSString *)IORegistryEntryCreateCFProperty(service, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0);
        
        // If searching at pure USB device level, we might not have BSD Name directly unless we traverse to interfaces.
        // For this implementation, we assume we might be matching Serial Services or looking up.
        // If VID/PID are present, we log.
        
        if (vid && pid) {
            const char* pathC = bsdPath ? [bsdPath UTF8String] : "unknown";
            // Call Rust
            mc_on_device_connected([vid unsignedShortValue], [pid unsignedShortValue], pathC);
        }
        
        IOObjectRelease(service);
    }
}

+ (void)startDetection {
    // Port should be stored/managed, simplified for immediate assignment
    if (!notificationPort) {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopDefaultMode);
    }

    // Match USB Serial Devices
    CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOSerialBSDServiceValue);
    CFDictionarySetValue(matchingDict, CFSTR(kIOSerialBSDTypeKey), CFSTR(kIOSerialBSDAllTypes));

    io_iterator_t addedIter;
    kern_return_t kr = IOServiceAddMatchingNotification(notificationPort, kIOPublishNotification, matchingDict, deviceAdded, NULL, &addedIter);
    
    if (kr == KERN_SUCCESS) {
        deviceAdded(NULL, addedIter); // Iterate existing
    }
}

@end
