#import <Cocoa/Cocoa.h>

// Quick Look이 생성한 폴더 아이콘을 메인 스레드로 전달합니다. 원본 파일은 변경하지 않습니다.
void MLLoadFolderIcon(NSURL *url, CGFloat size, CGFloat scale, void (^completion)(NSImage *));
