#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
./build-yaml.sh
xcrun clang -Ivendor/libyaml/include -fobjc-arc -Wall -Wextra -Werror -Isrc tests/tests.m src/AppCatalog.m src/RecentDirectories.m src/ConfigStore.m src/LauncherShortcut.m src/AppIconUpdater.m src/SleepController.m src/EventLog.m src/GestureRecognizer.c -framework Cocoa -framework IOKit -lsqlite3 build/yaml/libyaml.a -o build/tests
build/tests
