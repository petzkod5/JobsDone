#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Monitor.swift Sources/UIState.swift Tests/main.swift -o .build/monitor-tests
.build/monitor-tests
