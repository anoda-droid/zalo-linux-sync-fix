#!/usr/bin/env bash
# install-online.sh — cài Zalo for Linux (bản vá đồng bộ) bằng ĐÚNG 1 LỆNH,
# không cần git, không cần clone tay.
#
# Bản thường (nhắn tin, đồng bộ, ảnh/file):
#   curl -fsSL https://raw.githubusercontent.com/anoda-droid/zalo-linux-sync-fix/main/install-online.sh | bash
#
# Bản FULL có luôn GỌI ĐIỆN (wine đóng gói sẵn trong AppImage):
#   curl -fsSL https://raw.githubusercontent.com/anoda-droid/zalo-linux-sync-fix/main/install-online.sh | bash -s -- --full
#
# Cài thêm cờ khác cho install.sh (ví dụ --no-desktop) đặt sau "--full".
set -euo pipefail

SLUG="anoda-droid/zalo-linux-sync-fix"
BRANCH="main"
TARBALL="https://github.com/${SLUG}/archive/refs/heads/${BRANCH}.tar.gz"

command -v curl >/dev/null 2>&1 || { echo "!! Thiếu curl. Cài: sudo apt install -y curl"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf '%s\n' "== Đang tải bộ cài ($SLUG@$BRANCH) về $WORK"
if ! curl -fsSL "$TARBALL" | tar xz -C "$WORK"; then
  echo "!! Không tải được bộ cài. Kiểm tra mạng / DNS rồi chạy lại." >&2
  exit 1
fi

DIR="$WORK/zalo-linux-sync-fix-$BRANCH"
[ -f "$DIR/install.sh" ] || { echo "!! Gói tải về không đúng cấu trúc." >&2; exit 1; }

chmod +x "$DIR/install.sh" "$DIR/run.sh" 2>/dev/null || true

# Mặc định: cài vào menu ứng dụng (giống double-click file .exe trên Windows)
if [ "$#" -eq 0 ]; then
  exec bash "$DIR/install.sh" --install-desktop
fi
exec bash "$DIR/install.sh" "$@"