![screenshot](screenshot.webp)

# MiniLaunch

`~/Apps`에 정리한 앱을 반투명 Grid로 여는 macOS 런처입니다.
Finder alias와 하위 폴더로 앱을 구성하며, Cursor 최근 폴더 열기와 잠자기 방지 기능을 제공합니다.

## 빌드와 설치

macOS 13 이상에서 실행합니다. 빌드에는 Icon Composer를 지원하는 Xcode 26 이상의 CLI 도구가 필요합니다.
Command Line Tools만으로는 아이콘을 빌드할 수 없습니다. Xcode GUI 실행이나 개발자 계정 로그인은 필요하지 않습니다.

```sh
# Xcode 초기 구성 요소가 설치되지 않았다면 한 번 실행합니다.
sudo xcodebuild -runFirstLaunch

./build.sh
open dist/MiniLaunch.app
```

사용자 Applications 폴더에 설치하려면 다음 명령을 사용합니다.

```sh
./build.sh --install
open ~/Applications/MiniLaunch.app
```

기존 설치는 덮어쓰지 않습니다. 업데이트하려면 앱을 종료하고 기존 앱을 옮긴 뒤 다시 설치해 주세요.
Dock에 고정하려면 실행한 앱의 Dock 메뉴에서 직접 설정해 주세요.

## 앱 구성

Finder에서 `~/Apps` 폴더를 만들고 사용할 앱의 가상본(alias)을 넣어 주세요.
앱 번들과 심볼릭 링크도 지원하며, 실제 하위 폴더를 만들면 Grid 안에서 탐색할 수 있습니다.

```text
~/Apps/
├── Safari
├── Notes
└── 개발/
    ├── Terminal
    └── Visual Studio Code
```

이름순으로 표시하며 깨진 alias는 흐리게 표시합니다. 앱 폴더의 내용은 자동 수정하지 않습니다.
alias 자체에 Finder Tag를 지정하면 Tag 이름순으로 그룹화합니다. 여러 Tag가 있으면 각 그룹에 표시하고,
Tag 없는 항목은 마지막에 모읍니다. 다시 열거나 ⌘R을 누르면 변경 사항을 읽습니다.

다른 앱 폴더를 사용하려면 앱을 종료하고 경로를 지정해 실행합니다.

```sh
open dist/MiniLaunch.app --args -AppsDirectory "/절대/경로/Apps"
```

## 조작

| 입력 | 동작 |
| --- | --- |
| 메뉴 막대 아이콘 클릭 | Grid 열기·닫기 |
| 메뉴 막대 아이콘 오른클릭 / Control-클릭 | 관리 메뉴 |
| Dock의 MiniLaunch 클릭 | Grid 열기 |
| 앱 클릭 / Return | 선택한 앱 실행 |
| Grid의 폴더 클릭 / Return | 하위 폴더로 이동 |
| 방향키 | 앱·최근 폴더 선택 |
| ⌘↑ / ‹ 버튼 | 상위 폴더로 이동 |
| ⌘R | 목록 다시 읽기 |
| Esc / 바깥 클릭 | Grid 닫기 |
| ⌘Q / 관리 메뉴의 Quit MiniLaunch | 앱 종료 |
| 네 손가락 또는 다섯 손가락 모으기 | Grid 열기 |
| 네 손가락 또는 다섯 손가락 펼치기 | Grid 닫기 |

창을 닫아도 앱은 계속 실행되며 ⌘Tab 목록에는 나타나지 않습니다.
관리 메뉴의 `Open <경로>`로 앱 폴더를 Finder에서 열 수 있습니다.

앱을 오른클릭하면 `Reveal in Finder`로 실제 앱을 선택하거나,
`Uninstall with AppCleaner…`로 AppCleaner의 분석 화면을 열 수 있습니다.
실제 삭제는 AppCleaner에서 결정하며, 시스템 앱에는 제거 메뉴가 표시되지 않습니다.
AppCleaner가 설치되지 않았다면 해당 메뉴가 비활성화됩니다.

## Cursor 최근 폴더

첫 화면 하단에 Cursor에서 최근에 연 로컬 폴더를 표시합니다.
각 폴더의 Finder 아이콘과 이름을 줄마다 가운데 정렬하며, 별도 스크롤이나 개수 제한은 없습니다.
폴더 아이콘은 Quick Look의 아이콘 모드로 비동기 생성하여 시스템이 그린 색상과 내용물·장식을 표시합니다. 생성 중이거나 실패한 경우에는 NSWorkspace의 아이콘을 표시합니다.
클릭하거나 방향키로 선택한 뒤 Return을 누르면 Cursor에서 열립니다. 전체 경로는 툴팁으로 확인할 수 있습니다.

폴더 오른클릭 메뉴의 `Reveal in Finder`는 상위 폴더에서 대상을 선택하고,
`Open in Finder`는 폴더 내부를 엽니다. `Open in iTerm`은 iTerm으로 폴더를 엽니다.
iTerm이 설치되지 않았다면 해당 메뉴가 비활성화됩니다. Grid의 하위 폴더에도 같은 메뉴를 제공합니다.

## 잠자기 방지 (Caffein)

메뉴 막대 아이콘을 오른클릭하고 다음 모드 중 하나를 선택합니다.

| 모드 | 동작 |
| --- | --- |
| Off | 잠자기 방지 끄기 |
| Prevent Sleep | 유휴 상태의 시스템 잠자기 방지, 화면 꺼짐 허용 |
| Prevent Sleep and Display Sleep | 유휴 상태의 시스템 잠자기와 화면 꺼짐 방지 |

활성화 중에는 메뉴 막대에 커피잔을 표시하며, 화면 꺼짐까지 방지하는 모드에서는 주의를 나타내도록 커피잔만 빨간색으로 표시합니다. 앱을 시작하면 항상 Off이며 종료 시 해제됩니다.
수동 잠자기나 덮개 닫기로 인한 잠자기를 차단하지는 않습니다.

## 권한과 문제 해결

- Dock 위치를 정확히 맞추려면 관리 메뉴의 `Advanced → Allow Dock Position Access…`에서 접근성 권한을 허용해 주세요. 권한 없이도 사용할 수 있으며, 위치를 확인하지 못하면 화면 중앙에 표시합니다.
- 제스처가 작동하지 않으면 `Advanced → Gesture Status…`로 상태를 확인하고 `Reconnect Gesture Devices`로 다시 연결해 주세요.
- 제스처는 비공개 macOS 기능을 사용하므로 OS 업데이트에 따라 동작이 달라질 수 있습니다. 펼치기로 Grid를 닫을 때 macOS의 Show Desktop이 함께 작동할 수 있습니다.
- 잠자기 방지 로그는 `Advanced → Open Caffein Logs`에서 확인할 수 있습니다.

제스처 없이 실행하려면 앱을 종료한 뒤 다음 명령을 사용합니다.

```sh
open dist/MiniLaunch.app --args -DisableGestures YES
```

구현 사양과 테스트 방법은 [SPEC.md](SPEC.md), 변경·검증 기록과 남은 실기 확인 항목은 [HISTORY.md](HISTORY.md)에 있습니다.
