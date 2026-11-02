#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/yaml
for source in vendor/libyaml/src/*.c; do
  xcrun clang -O2 -mmacosx-version-min=13.0 -Ivendor/libyaml/include \
    -DYAML_VERSION_MAJOR=0 -DYAML_VERSION_MINOR=2 -DYAML_VERSION_PATCH=5 \
    '-DYAML_VERSION_STRING="0.2.5"' -c "$source" -o "build/yaml/$(basename "${source%.c}").o"
done
ar rcs build/yaml/libyaml.a build/yaml/*.o
