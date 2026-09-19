#!/usr/bin/env bash
# install.sh — vá lỗi đồng bộ tin nhắn cho AppImage Zalo for Linux
# Hỗ trợ: Ubuntu / Linux Mint / Zorin OS / Debian / Fedora (và WSL)
#
# Dùng:
#   ./install.sh /duong/dan/Zalo-*.AppImage                 # vá, chạy từ thư mục hiện tại
#   ./install.sh --install-desktop /duong/dan/Zalo-*.AppImage
#        -> cài vào ~/.local/opt/zalo-linux + tạo mục trong menu ứng dụng
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/opt/zalo-linux"
DESKTOP_ENTRY=0
FULL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install-desktop) DESKTOP_ENTRY=1; shift ;;
    --full) FULL=1; shift ;;
    --dest) DEST="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) break ;;
  esac
done

APPIMAGE="${1:-}"
if [ -z "$APPIMAGE" ]; then
  echo "== Không truyền đường dẫn AppImage — tự tải bản mới nhất từ GitHub"
  APPIMAGE="$(python3 "$HERE/tools/fetch_zalo.py" --dest "${XDG_DOWNLOAD_DIR:-$HOME/Downloads}" $([ "$FULL" = 1 ] && echo --full))" || {
    echo "!! Tự tải không được. Anh/chị tải tay AppImage từ:"
    echo "   https://github.com/doandat943/zalo-for-linux/releases"
    echo "   rồi chạy lại:  $0 <đường-dẫn-AppImage>"
    exit 1
  }
  echo "   -> $APPIMAGE"
fi
[ -f "$APPIMAGE" ] || { echo "!! Không thấy file: $APPIMAGE"; exit 1; }
APPIMAGE="$(cd "$(dirname "$APPIMAGE")" && pwd)/$(basename "$APPIMAGE")"
chmod +x "$APPIMAGE" 2>/dev/null || true

# ---------- 1. Kiểm tra môi trường ----------
echo "== Kiểm tra môi trường"
MISSING=()
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")
if command -v python3 >/dev/null 2>&1; then
  PYV="$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  echo "   python3 $PYV"
  python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,6) else 1)' || { echo "!! Cần python3 >= 3.6"; exit 1; }
fi
command -v node >/dev/null 2>&1 && echo "   node $(node -v)  (dùng để kiểm tra cú pháp)" || echo "   (không có node — bỏ qua kiểm tra cú pháp, vẫn vá bình thường)"

# libfuse2: cần để CHẠY AppImage (Ubuntu 22.04+/Mint 21+/Zorin 17 trở lên không cài sẵn)
HAVE_FUSE=0
if ldconfig -p 2>/dev/null | grep -q "libfuse\.so\.2"; then HAVE_FUSE=1; fi
if [ "$HAVE_FUSE" = 0 ]; then
  echo "   [!] Chưa có libfuse2 — cần để chạy AppImage dạng file."
  echo "       Cài:  sudo apt install libfuse2        (Ubuntu/Mint/Zorin)"
  echo "            sudo dnf install fuse-libs        (Fedora)"
  echo "       (Script vá vẫn chạy được — chỉ lúc CHẠY mới cần; run.sh có chế độ dự phòng.)"
fi
command -v xdg-settings >/dev/null 2>&1 || echo "   [i] Thiếu xdg-utils (chỉ ảnh hưởng mở link bằng trình duyệt mặc định): sudo apt install xdg-utils"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "!! Thiếu: ${MISSING[*]}  ->  sudo apt install ${MISSING[*]}"
  exit 1
fi

# ---------- 2. Vá ----------
echo
echo "== Vá lỗi đồng bộ"
OUTDIR="${APPIMAGE}.fixed"
python3 "$HERE/patch_zalo_sync.py" --appimage "$APPIMAGE"
ROOT="$OUTDIR/squashfs-root"
[ -d "$ROOT" ] || { echo "!! Không thấy $ROOT sau khi vá"; exit 1; }

# ---------- 3. Kiểm chứng ----------
echo
echo "== Kiểm chứng kết quả"
FAIL=0
python3 "$HERE/patch_zalo_sync.py" --check "$ROOT" | grep -q "BỎ QUA (đã vá trước đó)" \
  && echo "   OK  các patch đã nằm trong bundle" \
  || { echo "   LI patch chưa được áp đầy đủ (chạy lại xem chi tiết)"; FAIL=1; }

if command -v node >/dev/null 2>&1; then
  for f in "$ROOT"/app/pc-dist/shared-worker.*.js "$ROOT"/app/pc-dist/lazy/main-startup.*.js; do
    [ -e "$f" ] || continue
    if node --check "$f" >/dev/null 2>&1; then
      echo "   OK  cú pháp $(basename "$f")"
    else
      echo "   LI cú pháp $(basename "$f") — khôi phục bản gốc:"
      echo "       cp '${f}.orig' '${f}'"
      FAIL=1
    fi
  done
  [ -f "$HERE/test_sync_patch.js" ] && { echo; node "$HERE/test_sync_patch.js" "$ROOT/app" || true; }
fi

if [ "$FAIL" = 1 ]; then
  echo
  echo "!! Có bước kiểm tra không đạt. Bản gốc vẫn còn ở các file .orig"
  exit 1
fi

# ---------- 4. Cài vào menu (tuỳ chọn) ----------
RUN_PATH="$ROOT/AppRun"
if [ "$DESKTOP_ENTRY" = 1 ]; then
  echo
  echo "== Cài vào $DEST"
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  cp -a "$ROOT" "$DEST"
  chmod +x "$DEST/AppRun" "$DEST/zalo" 2>/dev/null || true

  APPDIR="$HOME/.local/share/applications"
  mkdir -p "$APPDIR"
  ICON="$DEST/.DirIcon"
  [ -f "$ICON" ] || ICON="$(find "$DEST/usr/share/icons" -name 'zalo.png' -o -name '*zalo*.png' 2>/dev/null | head -1)"
  cat > "$APPDIR/zalo.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Zalo
Comment=Nhắn tin Zalo (bản vá đồng bộ tin nhắn)
Exec=$DEST/AppRun --no-sandbox %u
Icon=$ICON
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=Zalo
EOF
  update-desktop-database "$APPDIR" >/dev/null 2>&1 || true
  RUN_PATH="$DEST/AppRun"
  echo "   OK  đã tạo $APPDIR/zalo.desktop (Zalo sẽ hiện trong menu ứng dụng)"
  echo "   Gỡ cài đặt: rm -rf '$DEST' '$APPDIR/zalo.desktop'"
fi

echo
echo "== Xong. Chạy:"
echo "   $RUN_PATH --no-sandbox"
[ "$HAVE_FUSE" = 0 ] && echo "   (thiếu libfuse2 thì dùng: ./run.sh  — script tự chọn chế độ dự phòng)"
[ -f "$HERE/run.sh" ] && echo "   hoặc:  $HERE/run.sh '$ROOT'"