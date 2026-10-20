#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "==> LocalSend 项目: $PWD"

echo "==> 安装/同步 Flutter 依赖"
(
  cd app
  fvm flutter pub get
)

echo "==> 初始化完成"
echo "启动项目：cd app && fvm flutter run"