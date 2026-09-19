#!/usr/bin/env bash
# run.sh — chạy Zalo đã vá, tự chọn chế độ phù hợp với máy
# Dùng: ./run.sh [/duong/dan/squashfs-root]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE="${1:-}"

if [ -z "$TREE" ]; then
  for c in "$HERE/squashfs-root" "$HOME/.local/opt/zalo-linux"; do
    [ -d "$c" ] && { TREE="$c"; break; }
  done
fi
[ -n "$TREE" ] && [ -d "$TREE" ] || { echo "Không thấy thư mục Zalo đã vá. Dùng: $0 /duong/dan/squashfs-root"; exit 1; }

# Tìm AppRun / binary
RUN=""
for c in "$TREE/AppRun" "$TREE/zalo"; do [ -x "$c" ] && { RUN="$c"; break; }; done
[ -n "$RUN" ] || { echo "!! Không thấy AppRun/zalo trong $TREE"; exit 1; }

ARGS=(--no-sandbox "$@")

# libfuse2 có sẵn? không thì chạy chế độ dự phòng của AppImage
if ! ldconfig -p 2>/dev/null | grep -q "libfuse\.so\.2"; then
  echo "[i] Không thấy libfuse2 — dùng --appimage-extract-and-run (không cần FUSE)"
  exec "$RUN" --appimage-extract-and-run "${ARGS[@]}"
fi

# WSLg / máy ảo hay lỗi GPU → cho phép bật tắt bằng biến môi trường
if [ "${ZALO_DISABLE_GPU:-0}" = "1" ]; then
  echo "[i] ZALO_DISABLE_GPU=1 — tắt tăng tốc GPU"
  ARGS+=(--disable-gpu --disable-gpu-compositing --disable-software-rasterizer)
fi

exec "$RUN" "${ARGS[@]}"