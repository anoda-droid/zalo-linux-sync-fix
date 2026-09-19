#!/usr/bin/env bash
# install.sh — vá lỗi đồng bộ tin nhắn cho AppImage Zalo for Linux
# Dùng: ./install.sh /duong/dan/Zalo-*.AppImage
set -euo pipefail

APPIMAGE="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$APPIMAGE" ]; then
  echo "Dùng: $0 /duong/dan/Zalo-*.AppImage"
  exit 1
fi
if [ ! -f "$APPIMAGE" ]; then
  echo "Không thấy file: $APPIMAGE"
  exit 1
fi

chmod +x "$APPIMAGE" 2>/dev/null || true

echo "== Bước 1: bung AppImage + vá"
python3 "$HERE/patch_zalo_sync.py" --appimage "$APPIMAGE"

ROOT="${APPIMAGE}.fixed/squashfs-root"
if [ ! -d "$ROOT" ]; then
  echo "!! Không thấy $ROOT sau khi vá"
  exit 1
fi

echo
echo "== Bước 2: kiểm tra cú pháp JS"
if command -v node >/dev/null 2>&1; then
  for f in "$ROOT"/app/pc-dist/shared-worker.*.js "$ROOT"/app/pc-dist/lazy/main-startup.*.js; do
    [ -e "$f" ] || continue
    if node --check "$f" >/dev/null 2>&1; then
      echo "   OK  $(basename "$f")"
    else
      echo "   LI CÚ PHÁP $(basename "$f") — khôi phục từ $(basename "$f").orig"
      exit 1
    fi
  done
  if [ -f "$HERE/test_sync_patch.js" ]; then
    echo
    echo "== Bước 3: A/B test logic đã vá"
    node "$HERE/test_sync_patch.js" "$ROOT/app" || true
  fi
else
  echo "   (không có node, bỏ qua kiểm tra cú pháp)"
fi

echo
echo "== Bước 4: chạy"
echo "   $ROOT/AppRun --no-sandbox"
echo

if command -v appimagetool >/dev/null 2>&1; then
  OUT="$(dirname "$APPIMAGE")/Zalo-patched.AppImage"
  echo "== Đóng gói lại thành AppImage: $OUT"
  ARCH=x86_64 appimagetool "$ROOT" "$OUT" && chmod +x "$OUT"
  echo "   Chạy: $OUT --no-sandbox"
else
  echo "(Muốn đóng gói lại thành 1 file .AppImage thì cài appimagetool:"
  echo " https://github.com/AppImage/appimagetool/releases)"
fi