#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Isrc tests/tests.m src/AppCatalog.m src/RecentDirectories.m src/SleepController.m src/SleepLog.m src/GestureRecognizer.c -framework Cocoa -framework IOKit -lsqlite3 -o build/tests
build/tests
