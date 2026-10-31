#import "FolderIcon.h"
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>

void MLLoadFolderIcon(NSURL *url, CGFloat size, CGFloat scale, void (^completion)(NSImage *)) {
    NSNumber *directory = nil, *package = nil;
    [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
    [url getResourceValue:&package forKey:NSURLIsPackageKey error:nil];
    if (!directory.boolValue || package.boolValue) return;

    // iconForFile:과 달리 폴더의 색상과 내용물·사용자 지정 장식을 시스템이 함께 그립니다.
    QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc]
        initWithFileAtURL:url size:CGSizeMake(size, size) scale:MAX(1, scale)
        representationTypes:QLThumbnailGenerationRequestRepresentationTypeAll];
    request.iconMode = YES;
    [QLThumbnailGenerator.sharedGenerator generateBestRepresentationForRequest:request
        completionHandler:^(QLThumbnailRepresentation *representation, NSError *error) {
            // 생성에 실패하면 호출자가 먼저 표시한 NSWorkspace 아이콘을 유지합니다.
            if (error || !representation) return;
            NSImage *image = representation.NSImage;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
        }];
}
