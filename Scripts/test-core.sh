#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swiftc -swift-version 6 -D STANDALONE_TESTS -parse-as-library \
  LvLian/Core/*.swift Tests/LvLianCoreTests/*.swift Scripts/StandaloneTests.swift \
  -o .build/core-tests
.build/core-tests
