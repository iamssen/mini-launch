#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  ""|--install) ;;
  *) echo "사용법: ./build.sh [--install]" >&2; exit 2 ;;
esac
if ! xcrun --find clang >/dev/null 2>&1; then
  echo "Command Line Tools가 필요합니다: xcode-select --install" >&2
  exit 1
fi
# build는 매번 재생성하는 중간 산출물 전용 디렉터리입니다.
rm -rf build
mkdir -p build/composer
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0   src/*.m src/GestureRecognizer.c -framework Cocoa -framework ApplicationServices   -framework QuartzCore -framework CoreImage -o build/MiniLaunch
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Icon Composer 아이콘 빌드에는 Xcode 26 이상의 actool이 필요합니다." >&2
  exit 1
fi
xcrun actool "$PWD/icon.icon" --compile "$PWD/build/composer"   --app-icon icon --platform macosx --target-device mac   --minimum-deployment-target 13.0   --output-partial-info-plist "$PWD/build/composer-info.plist"
# 컴파일 성공 후 번들을 새로 조립해 이전 리소스가 남지 않게 합니다.
rm -rf dist/MiniLaunch.app
mkdir -p dist/MiniLaunch.app/Contents/{MacOS,Resources}
cp build/MiniLaunch dist/MiniLaunch.app/Contents/MacOS/MiniLaunch
cp build/composer/Assets.car build/composer/icon.icns dist/MiniLaunch.app/Contents/Resources/
cp Info.plist dist/MiniLaunch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Merge build/composer-info.plist" dist/MiniLaunch.app/Contents/Info.plist
plutil -lint dist/MiniLaunch.app/Contents/Info.plist
codesign --force --sign - dist/MiniLaunch.app
codesign --verify --strict dist/MiniLaunch.app
echo "생성 완료: $PWD/dist/MiniLaunch.app"
if [[ "${1:-}" == "--install" ]]; then
  destination="$HOME/Applications/MiniLaunch.app"
  if [[ -e "$destination" ]]; then
    echo "기존 앱을 덮어쓰지 않습니다: $destination" >&2
    echo "실행 중인 앱을 종료하고 기존 앱을 다른 위치로 옮긴 뒤 다시 실행해 주세요." >&2
    exit 1
  fi
  mkdir -p "$HOME/Applications"
  ditto dist/MiniLaunch.app "$destination"
  echo "설치 완료: $destination"
fi
