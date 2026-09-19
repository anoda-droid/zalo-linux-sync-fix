#!/usr/bin/env bash
# run.sh — chạy Zalo đã vá, tự chọn chế độ phù hợp với máy
#
# Dùng:
#   ./run.sh                                  # tự tìm bản đã vá (./squashfs-root hoặc ~/.local/opt/zalo-linux)
#   ./run.sh /duong/dan/squashfs-root         # chạy từ thư mục đã bung
#   ./run.sh /duong/dan/Zalo-*.AppImage       # chạy file AppImage (tự lo thiếu libfuse2)
#   ZALO_DISABLE_GPU=1 ./run.sh               # máy ảo/WSLg bị lỗi GPU
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
shift || true

have_fuse() { ldconfig -p 2>/dev/null | grep -q "libfuse\.so\.2"; }

# ---- Nếu người dùng trỏ vào file AppImage ----
if [ -n "$TARGET" ] && [ -f "$TARGET" ]; then
  chmod +x "$TARGET" 2>/dev/null || true
  if have_fuse; then
    exec "$TARGET" --no-sandbox "$@"
  fi
  echo "[i] Không thấy libfuse2 — chạy AppImage ở chế độ extract-and-run (không cần FUSE)"
  echo "    Cài đầy đủ: sudo apt install libfuse2   (Ubuntu/Mint/Zorin)"
  exec "$TARGET" --appimage-extract-and-run --no-sandbox "$@"
fi

# ---- Tìm thư mục đã vá ----
TREE="$TARGET"
if [ -z "$TREE" ]; then
  for c in "$HERE/squashfs-root" "$HOME/.local/opt/zalo-linux"; do
    [ -d "$c" ] && { TREE="$c"; break; }
  done
fi
[ -n "$TREE" ] && [ -d "$TREE" ] || {
  echo "Không thấy thư mục Zalo đã vá."
  echo "Dùng: $0 /duong/dan/squashfs-root"
  exit 1
}

RUN=""
for c in "$TREE/AppRun" "$TREE/zalo"; do [ -x "$c" ] && { RUN="$c"; break; }; done
[ -n "$RUN" ] || { echo "!! Không thấy AppRun/zalo trong $TREE"; exit 1; }

ARGS=(--no-sandbox "$@")

# Trong thư mục đã bung thì KHÔNG cần FUSE (chỉ file .AppImage mới cần).
# WSLg / máy ảo hay lỗi GPU -> ZALO_DISABLE_GPU=1
if [ "${ZALO_DISABLE_GPU:-0}" = "1" ]; then
  echo "[i] ZALO_DISABLE_GPU=1 — tắt tăng tốc GPU"
  ARGS+=(--disable-gpu --disable-gpu-compositing --disable-software-rasterizer)
fi

# Máy dùng Wayland (Zorin 17, Ubuntu 24.04...) mà cửa sổ/khay hệ thống lỗi:
#   ZALO_OZONE=x11      -> ép chạy qua XWayland (mặc định của Electron)
#   ZALO_OZONE=wayland  -> ép chạy Wayland gốc
case "${ZALO_OZONE:-}" in
  x11)     echo "[i] Ép nền tảng X11";     ARGS+=(--ozone-platform=x11) ;;
  wayland) echo "[i] Ép nền tảng Wayland"; ARGS+=(--ozone-platform=wayland) ;;
esac

exec "$RUN" "${ARGS[@]}"