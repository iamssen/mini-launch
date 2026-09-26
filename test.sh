#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Isrc tests/tests.m src/AppCatalog.m src/GestureRecognizer.c -framework Cocoa -o build/tests
build/tests
