#import <Cocoa/Cocoa.h>
@interface MLItem : NSObject
@property NSURL *sourceURL;
@property NSURL *targetURL;
@property NSString *name;
@property NSArray<NSString *> *tags;
@property BOOL folder;
@property NSString *problem;
@end
@interface AppCatalog : NSObject
+ (NSArray<NSArray<MLItem *> *> *)groupsForItems:(NSArray<MLItem *> *)items;
+ (NSArray<MLItem *> *)itemsAtURL:(NSURL *)url error:(NSError **)error;
@end
