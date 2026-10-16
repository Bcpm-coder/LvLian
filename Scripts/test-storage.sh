#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/storage-tests .build/storage-module-cache
fixture_dir=$(mktemp -d "$PWD/.build/storage-tests/migration.XXXXXX")
xcrun swiftc -swift-version 5 -module-name LvLian -target arm64-apple-macosx14.0 -parse-as-library \
  -module-cache-path .build/storage-module-cache \
  LvLian/Core/*.swift Tests/Fixtures/TrainingRecordV1.swift Tests/Fixtures/CreateLegacyStore.swift \
  -o .build/storage-tests/legacy
.build/storage-tests/legacy "$fixture_dir/default.store"
xcrun swiftc -swift-version 5 -module-name LvLian -target arm64-apple-macosx14.0 -parse-as-library \
  -module-cache-path .build/storage-module-cache \
  LvLian/Core/*.swift LvLian/App/TrainingRecord.swift LvLian/App/SquatRecord.swift \
  LvLian/Services/TrainingLibrary.swift Scripts/StorageSmoke.swift \
  -o .build/storage-tests/smoke
.build/storage-tests/smoke "$fixture_dir/default.store"
