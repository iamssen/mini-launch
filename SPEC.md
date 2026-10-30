# MiniLaunch 사양

사용 방법은 [README.md](README.md), 변경·검증 기록은 [HISTORY.md](HISTORY.md)에 정리합니다.
이 문서는 현재 구현의 동작 기준과 기술적 경계를 다룹니다.

## 구성과 빌드

- Objective-C/AppKit 기반의 macOS 13 이상용 상주 런처입니다. Xcode 프로젝트와 외부 패키지는 사용하지 않습니다.
- Icon Composer를 지원하는 Xcode 26 이상의 CLI 도구로 `./build.sh`를 실행합니다. Xcode GUI와 Apple Developer 계정은 필요하지 않습니다.
- 현재 Mac의 아키텍처로 빌드하고 `dist/MiniLaunch.app`을 생성합니다. 로컬 ad-hoc 서명만 수행하며 Developer ID와 공증은 포함하지 않습니다.
- 아이콘 원본은 `icon.icon` 하나이며 `actool`로 `Assets.car`와 호환 ICNS를 생성합니다. Command Line Tools만으로는 아이콘을 컴파일할 수 없습니다.
- `build/`는 매번 재생성하고 컴파일 성공 후 `dist/MiniLaunch.app`을 새로 조립합니다.
- `--install`은 `~/Applications/MiniLaunch.app`에 복사하며 기존 설치를 덮어쓰지 않습니다.

## 앱 목록과 실행

- 기본 원본은 `~/Apps`의 Finder alias, 심볼릭 링크, 앱 번들, 실제 하위 폴더입니다. `-AppsDirectory`로 변경할 수 있습니다.
- 원본 폴더를 생성하거나 앱·alias·Dock 설정을 자동 변경하지 않습니다.
- alias 해석 시 사용자 대화상자와 볼륨 마운트를 유발하지 않습니다.
- 숨김 항목과 일반 파일은 제외하고 깨진 alias는 오류 상태로 남기며 실행하지 않습니다.
- 원본 앱이 아닌 alias 자체의 Finder Tag를 사용합니다. Tag 이름순으로 그룹화하고 Tag 없는 항목은 마지막에 배치합니다.
- 여러 Tag가 있으면 각 그룹에 표시합니다. 그룹 안에서는 Finder 표시 이름으로 자연 정렬합니다.
- 그룹 제목 없이 새 행과 구분선으로 나눕니다.
- 앱 번들은 실행하고 일반 폴더는 같은 Grid에서 탐색합니다. 열기·폴더 이동·⌘R 시 앱 목록을 다시 읽습니다.

## 화면과 입력

- 비활성화 `NSPanel`을 사용합니다. macOS 26 이상은 `NSGlassEffectView`의 Clear 스타일과 검정 50% 틴트, 이전 버전은 `NSVisualEffectView`를 사용합니다.
- 첫 실행과 모으기 제스처는 포인터가 있는 화면 중앙에 표시합니다.
- Dock 재열기는 공개 Accessibility API로 자기 아이콘 위치를 조회합니다. 권한 없이 하단 Dock 영역을 클릭한 경우 클릭 위치를 보조 기준으로 사용하고, 위치를 확인하지 못하면 화면 중앙에 표시합니다.
- 하단 Dock의 아이콘 위, 좌우 Dock의 안쪽에 배치하며 화면의 `visibleFrame` 안으로 제한합니다.
- 하단 Dock에는 말풍선 꼬리를 표시합니다. 좌우 꼬리는 지원하지 않습니다. 외곽 마스크는 유리 효과에 적용합니다.
- 메뉴 막대 아이콘 클릭은 아이콘 아래에서 상단을 기준으로 Grid를 열고, 다시 클릭하면 닫습니다.
- 모든 Space와 다른 앱의 전체 화면에 참여하도록 설정합니다. 표시 시 앱 활성화를 강제하지 않으며 패널이 키보드 입력을 받습니다.
- `LSUIElement`와 Accessory 활성화 정책을 사용합니다. 사용자가 고정한 Dock 아이콘으로 재열기하고, 실행 중 Dock 아이콘 자동 추가와 ⌘Tab 등록은 하지 않습니다.
- 앱 Grid는 최대 6열, 128pt 셀 간격, 96pt 아이콘 이미지 영역, 13pt 이름을 사용합니다. 실제 앱 아이콘은 기본 여백을 포함해 약 80pt로 보입니다.
- 첫 화면에는 제목을 표시하지 않습니다. 하위 폴더에서는 폴더 이름과 뒤로가기 버튼을 표시합니다.
- 창은 항목 수에 맞춰 크기를 조절하며 화면보다 긴 앱 Grid는 스크롤합니다. 검색창과 상시 도움말은 표시하지 않습니다.
- 첫 표시에는 선택 강조를 하지 않고 방향키 입력 시 표시합니다. 방향키 선택, Return 실행, ⌘↑ 상위 폴더, ⌘R 갱신, Esc·바깥 클릭 닫기, ⌘Q 종료를 지원합니다.
- Grid를 닫아도 프로세스는 유지됩니다.
- 등장은 140ms 확대·페이드, 퇴장은 90ms 축소·페이드입니다. Dock·메뉴 막대 위치가 있으면 해당 방향을 기준으로 전환합니다.
- 전환 중 콘텐츠에만 Gaussian blur를 적용합니다. 등장은 5→0, 퇴장은 현재값→6이며 평상시에는 필터를 제거합니다.
- macOS의 동작 줄이기에서는 확대·블러 없이 짧은 페이드만 사용합니다.

## 항목 메뉴와 외부 앱 연동

- 오른클릭과 Control-클릭으로 항목 메뉴를 엽니다. 메뉴는 항목 인덱스 대신 대상 URL을 보관합니다.
- `Reveal in Finder`는 alias가 가리키는 실제 대상을 Finder에서 선택합니다.
- 일반 앱의 `Uninstall with AppCleaner…`는 실제 앱 경로를 AppCleaner에 전달합니다. 분석 화면 이후의 삭제는 사용자가 결정합니다.
- 시스템 보호 앱에는 제거 메뉴를 표시하지 않으며, 실행 액션에서도 다시 확인합니다.
- 판별 시 심볼릭 링크를 해석하고 `/System/Applications`, `/System/Library`, `/System/Cryptexes`, `/System/Volumes/Preboot` 내부 경로와 `SF_RESTRICTED` 표시를 확인합니다.
- `com.apple` 번들 식별자만으로 제외하지 않습니다. 별도로 설치한 Xcode 등의 Apple 앱도 일반 앱으로 취급할 수 있습니다.
- Grid의 하위 폴더와 최근 폴더에는 `Reveal in Finder`, `Open in Finder`, `Open in iTerm`을 제공합니다. Finder 열기는 폴더 내부를 엽니다.
- AppCleaner·iTerm 설치 여부는 메뉴를 열 때 LaunchServices로 확인하고, 설치되지 않은 앱의 메뉴를 비활성화합니다.
- 외부 앱 열기는 `NSWorkspace`로 대상 앱을 명시합니다. Cursor는 `com.todesktop.230313mzl4w4u92`, iTerm은 `com.googlecode.iterm2`, AppCleaner는 `net.freemacsoft.AppCleaner`를 사용합니다.

## Cursor 최근 폴더

- 원본은 `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`의 `ItemTable`에서 `history.recentlyOpenedPathsList` 키로 저장된 JSON입니다.
- 시스템 SQLite를 읽기 전용으로 사용합니다. DB를 생성·수정하지 않으며 경합 시 대기 시간은 50ms로 제한합니다.
- `entries`의 `folderUri` 중 현재 존재하는 로컬 디렉터리만 최근 순서로 유지합니다. 파일·원격 경로·없는 폴더·중복·잘못된 항목은 제외합니다.
- Cursor 내부 저장 형식이 바뀌거나 DB 조회가 실패하면 기존 캐시를 유지합니다. 정상 조회한 빈 목록은 캐시도 비웁니다.
- 앱 시작 시 백그라운드에서 사전 조회하고, Grid를 열 때 메모리 캐시로 먼저 표시한 뒤 새 조회를 요청합니다. 디스크 캐시는 저장하지 않습니다.
- SQLite 조회·JSON 해석·폴더 존재 확인은 전용 직렬 큐에서 실행합니다. 중복 갱신 요청은 진행 중인 조회로 합칩니다.
- 결과 반영은 메인 스레드에서 수행하며 동일한 목록은 화면 갱신을 요청하지 않습니다.
- 닫힌 상태에서는 캐시만 갱신합니다. 등장 애니메이션·메뉴 사용 중에는 화면 반영을 미루고, 키보드 선택 중에는 다음 열기나 ⌘R에서 최신 캐시를 사용합니다.
- 첫 화면 하단의 별도 영역에 실제 Finder 아이콘과 13pt 이름을 표시합니다. 폴더 버튼은 높이 28pt, 행 간격 32pt이며 폭을 넘으면 줄바꿈하고 각 줄을 가운데 정렬합니다.
- 하단 목록에는 별도 스크롤과 개수 제한을 두지 않습니다. 사용자 지정 아이콘을 반영하고 전체 경로를 툴팁으로 표시합니다.
- 클릭·Return은 Cursor로 폴더를 엽니다. 키보드 탐색은 앱 Grid에서 최근 폴더로 이어집니다.

## 제스처 구현 경계

- `GestureMonitor.m`만 비공개 MultitouchSupport ABI를 사용합니다. 공개 AppKit/Accessibility 코드와 분리합니다.
- `dlopen`/`dlsym`으로 연결하며 라이브러리·심볼·장치가 없어도 제스처 외의 실행 경로는 유지합니다. `-DisableGestures YES`로 감지를 끌 수 있습니다.
- 장치별 네 개 또는 다섯 개 접촉점의 중심에서 평균 거리를 구합니다. 기준 대비 28% 이상 모으기, 32% 이상 펼치기와 시간 조건을 사용합니다.
- 같은 방향은 중복 실행하지 않습니다. 실행 이후 최소·최대 거리에서 반대 방향 임계점을 넘으면 손을 떼지 않고 반대 동작을 실행합니다.
- 120ms 이내의 접촉 누락은 진행량을 보존합니다. 접촉 수 변경과 누락 복귀 시 거리 기준을 보정하고 80ms 동안 판정을 유예합니다.
- 모으기는 닫힌 Grid를 열고 펼치기는 열린 Grid를 닫습니다.
- **Show Desktop 시스템 제스처의 조건부 차단은 미구현입니다.** 관찰 콜백은 시스템 입력을 소비하지 않으며 Grid를 닫아도 Show Desktop이 함께 작동할 수 있습니다. 시스템 제스처 설정을 자동 변경하거나 입력을 합성하지 않습니다.
- 시스템·화면 잠자기 복귀와 세션 복귀 시 1초 뒤 장치를 다시 연결합니다. 장치가 없으면 2초 간격으로 최대 두 번 더 시도합니다.
- 겹치는 복귀 알림은 마지막 알림을 기준으로 처리합니다. 재연결 전 대기 중인 프레임을 버리고 인식 상태를 초기화합니다.
- 상태 화면과 시스템 로그에서 장치 연결과 첫 입력 수신을 구분합니다. 등록 성공은 프레임 수신이나 실제 인식 성공을 뜻하지 않습니다.
- 공개 이벤트 API: [AppKit 터치 이벤트](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html), [Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement.h).
- 비공개 ABI 참고: [Remotastic의 MultitouchSupport 선언](https://github.com/lauschue/Remotastic/blob/main/MultitouchSupport.h). OS 버전별 호환성과 실제 입력은 별도 실기 확인 대상입니다.

## 관리 메뉴

- 메뉴 막대 아이콘 오른클릭·Control-클릭으로 관리 메뉴를 엽니다. 별도 Grid 열기 명령은 두지 않습니다.
- 메인 메뉴는 `Open <경로>`, Caffein 모드 세 개, `Advanced`, `Quit MiniLaunch`로 구성합니다. Caffein 모드는 구분선으로 묶고 하위 메뉴를 사용하지 않습니다.
- 앱 폴더가 홈 디렉터리 안에 있으면 경로를 `~`로 줄입니다. Dock의 폴더 열기 메뉴에도 같은 이름을 사용합니다.
- `Advanced`에는 `Allow Dock Position Access…`, `Gesture Status…`, `Reconnect Gesture Devices`, `Open Caffein Logs`를 배치합니다.
- 편집 메뉴를 포함한 모든 메뉴 이름은 영문입니다.

## 잠자기 방지

- 공개 IOKit API로 자체 전원 요청을 관리합니다. 기존 Caffein 프로젝트의 전원 요청 방식을 Objective-C로 옮겼습니다.
- 모드는 `0 = Off`, `1 = Prevent Sleep`, `2 = Prevent Sleep and Display Sleep`이며 체크 표시와 툴팁으로 현재 모드를 나타냅니다.
- 시스템 유휴 잠자기는 `PreventUserIdleSystemSleep`, 화면 꺼짐은 추가로 `PreventUserIdleDisplaySleep` 요청으로 방지합니다.
- 필요한 요청을 먼저 생성하고 생성 실패 시 기존 모드를 유지합니다. 오류 시 실제 보유 요청을 메뉴·아이콘에 반영하고 알립니다.
- 시작 시 Off이며 모드를 저장하지 않습니다. 앱 종료 시 자체 요청을 해제하고 사용자 전원 설정은 수정하지 않습니다. 수동 잠자기와 덮개 닫기는 차단하지 않습니다.
- 활성 상태에서는 3×3 격자 오른쪽에 가운데 점과 커피잔을 추가하고 비활성 상태에서는 기존 크기로 복귀합니다.
- 커피잔은 15pt regular 심볼의 원래 비율을 사용합니다. 확인 당시 크기는 24×17pt입니다. 격자 15×15pt와 점 2×2pt의 크기·가로 간격을 유지하고 세 요소의 수직 중심을 맞춥니다.

## Caffein 진단 기록

- `~/Library/Logs/MiniLaunch/caffein-YYYY-MM-DD.jsonl`에 UTC 시각·PID를 포함한 JSONL을 기록합니다. `Advanced → Open Caffein Logs`로 폴더를 엽니다.
- 기록 시 UTC 기준 오늘과 이전 6일의 자체 로그만 보관합니다. 다른 파일·폴더는 삭제하지 않으며 앱이 종료된 동안에는 정리하지 않습니다.

| 이벤트 | 내용 |
| --- | --- |
| `app_start`, `startup_state` | 버전·빌드·OS·프로세스 번호와 시작 상태 |
| `mode_requested`, `mode_applied`, `mode_failed` | 이전·선택 모드와 적용 결과 |
| `assertion_create`, `assertion_release`, `assertion_rollback` | 요청 종류·ID·IOKit 반환 코드 |
| `periodic_check` | 약 5분 간격의 자체 요청과 실제 OS 상태 비교 |
| `power_event` | 시스템·화면 잠자기와 복귀 알림, 처리 시점의 요청 상태 |
| `app_exit` | 종료 시 요청 해제를 시도한 뒤의 상태 |

- `matches: true`는 조회 성공과 요청 종류·개수·ID별 활성 상태의 일치를 뜻합니다.
- 불일치는 `query_result`, `owned_assertions`, `owned_checks`, `actual_assertions`를 함께 확인합니다. 조회 실패를 요청 없음이나 정상 동작으로 해석하지 않습니다.
- `timestamp`는 기록 시각, `observed_at`은 전원 알림 수신 시각입니다. 모두 UTC입니다.
- 주기 검사에는 최대 30초의 허용 오차가 있으며 잠자기 중에는 실행되지 않습니다.
- 로그는 조회만 수행하고 자동 복구나 화면 깨우기를 하지 않습니다. 로그 오류는 시스템 로그에 남기며 잠자기 방지 자체는 유지합니다.
- 강제 종료·충돌·전원 차단 시 `app_exit`가 없을 수 있습니다. 알림과 요청의 존재만으로 장시간 동작 성공을 단정하지 않습니다.

## 책임 분리

| 파일 | 책임 |
| --- | --- |
| AppCatalog | 앱 폴더 읽기, alias 해석, 정렬, 시스템 보호 앱 판별, 오류 |
| RecentDirectories | Cursor SQLite 읽기 전용 조회와 비동기 메모리 캐시 |
| LauncherController | Grid·최근 폴더 배치, 탐색, 항목 메뉴, 창 수명 |
| LauncherAppearance | 외곽 마스크와 앱·폴더 버튼 그리기 |
| DockLocator | 공개 AX API와 화면 좌표 변환 |
| GestureRecognizer | 하드웨어와 분리한 제스처 상태 머신 |
| GestureMonitor | 비공개 프레임워크 로딩과 프레임 전달 |
| SleepController | 공개 IOKit 요청 생성·해제·실제 상태 조회 |
| SleepLog | 날짜별 JSONL 기록과 7일 보관 정리 |
| main | 앱 수명, 관리 메뉴, 기능 연결 |
| icon.icon | Icon Composer 원본 |

## 검증 방법

```sh
./build.sh
./test.sh
```

- 빌드: 경고를 오류로 처리한 컴파일, 번들 생성, plist 검사, ad-hoc 서명 검사.
- 자동 테스트: alias·심볼릭 링크·깨진 alias·폴더·Tag·읽기 실패, 시스템 앱 판별, 제스처 방향·시간·접촉 수·중복 방지·잘못된 좌표, Cursor WAL 조회·항목 필터링·캐시 갱신·오류 유지, 실제 IOKit 요청 전환·정리, JSONL 순서·불일치 감지·보관 경계.
- 자동 테스트는 실제 트랙패드 입력, Space 전환, Dock 위치, 장시간 전원 동작이나 시스템 제스처 차단을 증명하지 않습니다.
- 각 전원 모드를 설정된 유휴 시간보다 길게 유지한 뒤 수 시간 또는 하룻밤 시험합니다. 화면 꺼짐 허용·시스템 유지, 화면 유지, Off·종료 후 요청 해제를 확인합니다. 다른 앱의 요청도 함께 확인합니다.

```sh
# 현재 전원 요청을 확인합니다.
pmset -g assertions

# 실기 검증 후 시스템 잠자기·복귀 기록을 저장합니다.
pmset -g log > ~/Desktop/minilaunch-power.log
```

검증 일시·환경·결과와 미확인 항목은 [HISTORY.md](HISTORY.md)에 기록합니다.
