# MiniLaunch 작업 지침
- 사용자에게 보내는 한국어 응답은 존댓말로 작성합니다.
- 사람이 읽는 문서, 주석, 테스트 설명은 한국어로 작성합니다.
- Objective-C/AppKit과 Command Line Tools로 빌드합니다. Xcode 프로젝트, 외부 패키지, Developer ID는 필요하지 않아야 합니다.
- 앱 구성의 원본은 ~/Apps의 Finder alias와 실제 하위 폴더입니다.
- 공개 AppKit/Accessibility API와 비공개 MultitouchSupport 코드를 분리합니다.
- 비공개 API의 감지와 시스템 제스처 차단을 혼동하지 않습니다. 실기 검증 여부를 기록합니다.
- 사용자 앱 폴더, Dock 설정, 시스템 제스처 설정을 자동 변경하지 않습니다.
- ./build.sh와 ./test.sh로 변경을 검증합니다.
