#!/usr/bin/env bash
# install.sh — vá lỗi đồng bộ tin nhắn cho AppImage Zalo for Linux
#
# Máy hỗ trợ: Ubuntu / Linux Mint / Zorin OS / Debian / Pop!_OS (apt)
#             Fedora / Bazzite / Nobara (dnf) — và WSL
#
# Dùng:
#   ./install.sh                              # tự tải AppImage mới nhất + vá + cài vào menu
#   ./install.sh --full                       # lấy bản Full (~464MB, có Wine cho zcall)
#   ./install.sh /duong/dan/Zalo-*.AppImage   # vá file AppImage có sẵn
#   ./install.sh --no-desktop /duong/dan/...  # chỉ vá, không cài vào ~/.local/opt
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/opt/zalo-linux"
DESKTOP_ENTRY=1
FULL=0
NEED_MB=2600          # chỗ trống cần cho: bung (~700MB) + bản cài (~700MB) + dư an toàn

while [ $# -gt 0 ]; do
  case "$1" in
    --install-desktop) DESKTOP_ENTRY=1; shift ;;
    --no-desktop)      DESKTOP_ENTRY=0; shift ;;
    --full)            FULL=1; shift ;;
    --dest)            DEST="$2"; shift 2 ;;
    -h|--help)         sed -n '2,14p' "$0"; exit 0 ;;
    *) break ;;
  esac
done

say()  { printf '%s\n' "$*"; }
ok()   { printf '   OK  %s\n' "$*"; }
warn() { printf '   [!] %s\n' "$*"; }
die()  { printf '!! %s\n' "$*" >&2; exit 1; }

# ---------- 0. Nhận diện hệ điều hành ----------
PKG=""
if command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
fi

# Tên gói FUSE khác nhau theo đời distro:
#   Ubuntu 22.04 / Mint 21 / Zorin 17 -> libfuse2
#   Ubuntu 24.04+ / Mint 22 / Zorin 18 -> libfuse2t64   (libfuse2 KHÔNG còn tồn tại)
#   Fedora -> fuse-libs ; Arch -> fuse2
FUSE_PKG="libfuse2"
case "$PKG" in
  apt)
    if ! apt-cache policy libfuse2 2>/dev/null | grep -q "Candidate: [0-9]"; then
      FUSE_PKG="libfuse2t64"
    fi
    ;;
  dnf) FUSE_PKG="fuse-libs" ;;
  pacman) FUSE_PKG="fuse2" ;;
esac

apt_hint() {
  case "$PKG" in
    apt) echo "sudo apt install -y $*" ;;
    dnf) echo "sudo dnf install -y $*" ;;
    pacman) echo "sudo pacman -S --needed $*" ;;
    *) echo "(cài thêm: $*)" ;;
  esac
}
OSNAME="$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -s )"
say "== Hệ thống: $OSNAME   [gói: ${PKG:-không rõ}]"
say ""

# ---------- 1. Kiểm tra môi trường ----------
say "== Kiểm tra môi trường"
command -v python3 >/dev/null 2>&1 || die "Thiếu python3.  ->  $(apt_hint python3)"
python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,6) else 1)' \
  || die "Cần python3 >= 3.6 (đang có $(python3 -V 2>&1))"
ok "python3 $(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')"

if command -v node >/dev/null 2>&1; then
  ok "node $(node -v) (kiểm tra cú pháp JS)"
else
  warn "Không có node — bỏ qua kiểm tra cú pháp (vẫn vá bình thường). Muốn có: $(apt_hint nodejs)"
fi
command -v curl >/dev/null 2>&1 && ok "curl" || warn "Không có curl (chỉ cần khi tải bằng tay)"

HAVE_FUSE=0
ldconfig -p 2>/dev/null | grep -q "libfuse\.so\.2" && HAVE_FUSE=1
if [ "$HAVE_FUSE" = 0 ]; then
  warn "Chưa có FUSE v2 — BẮT BUỘC để chạy AppImage dạng file:"
  say  "        $(apt_hint "$FUSE_PKG")"
  say  "        (Ubuntu 24.04+/Zorin 18/Mint 22 dùng libfuse2t64; Ubuntu 22.04/Zorin 17 dùng libfuse2)"
  say  "        Script vá vẫn chạy; run.sh có chế độ dự phòng khi thiếu FUSE."
fi
command -v xdg-settings >/dev/null 2>&1 \
  || warn "Thiếu xdg-utils (chỉ ảnh hưởng mở link bằng trình duyệt mặc định): $(apt_hint xdg-utils)"
if ! command -v 7z >/dev/null 2>&1 && ! command -v unsquashfs >/dev/null 2>&1; then
  warn "Không có 7z/unsquashfs (chỉ cần nếu cách bung chuẩn gặp lỗi): $(apt_hint p7zip-full squashfs-tools)"
fi

AVAIL_MB="$(df -Pk "${TMPDIR:-/tmp}" 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
if [ -n "${AVAIL_MB:-}" ]; then
  [ "$AVAIL_MB" -ge "$NEED_MB" ] || die "Còn ít chỗ trống (${AVAIL_MB}MB) — cần khoảng ${NEED_MB}MB. Dọn bớt rồi chạy lại."
  ok "chỗ trống: ${AVAIL_MB}MB (cần ~${NEED_MB}MB)"
fi

# ---------- 2. Lấy AppImage ----------
APPIMAGE="${1:-}"
if [ -z "$APPIMAGE" ]; then
  say ""
  say "== Chưa có AppImage — tự tải bản mới nhất từ GitHub"
  EXTRA=""
  [ "$FULL" = 1 ] && EXTRA="--full"
  # shellcheck disable=SC2086
  APPIMAGE="$(python3 "$HERE/tools/fetch_zalo.py" --dest "${XDG_DOWNLOAD_DIR:-$HOME/Downloads}" $EXTRA)" || {
    say "   Tải tự động không được (mạng?). Tải tay rồi chạy lại:"
    say "   https://github.com/doandat943/zalo-for-linux/releases"
    say "   $0 <đường-dẫn-AppImage>"
    exit 1
  }
  say "   -> $APPIMAGE"
fi
[ -f "$APPIMAGE" ] || die "Không thấy file: $APPIMAGE"
APPIMAGE="$(cd "$(dirname "$APPIMAGE")" && pwd)/$(basename "$APPIMAGE")"
SIZE_MB=$(( $(stat -c %s "$APPIMAGE" 2>/dev/null || echo 0) / 1048576 ))
[ "$SIZE_MB" -gt 100 ] || die "File AppImage nhỏ bất thường (${SIZE_MB}MB) — tải lại giúp."
ok "AppImage: $(basename "$APPIMAGE") (${SIZE_MB}MB)"
chmod +x "$APPIMAGE" 2>/dev/null || true

# ---------- 3. Vá ----------
say ""
say "== Vá lỗi đồng bộ"
set +e
python3 "$HERE/patch_zalo_sync.py" --appimage "$APPIMAGE"
RC=$?
set -e
case "$RC" in
  0) ;;
  3) die "Bản Zalo này đã đổi code so với bản script được viết cho (26.8.20) — xem các patch 'KHÔNG KHỚP' ở trên.
   Không có gì bị phá (bản gốc còn ở các file .orig). Báo giúp tại:
   https://github.com/anoda-droid/zalo-linux-sync-fix/issues" ;;
  *) die "Vá thất bại (mã lỗi $RC). Xem thông báo phía trên." ;;
esac
ROOT="${APPIMAGE}.fixed/squashfs-root"
[ -d "$ROOT/app" ] || die "Không thấy $ROOT/app sau khi vá"

# ---------- 4. Kiểm chứng ----------
say ""
say "== Kiểm chứng kết quả"
FAIL=0
PATCHED="$(python3 "$HERE/patch_zalo_sync.py" --check "$ROOT" 2>/dev/null | grep -c "BỎ QUA (đã vá trước đó)" || true)"
if [ "${PATCHED:-0}" -ge 9 ]; then
  ok "9/9 patch đã nằm trong bundle"
else
  warn "chỉ thấy ${PATCHED}/9 patch — xem lại danh sách phía trên"
  FAIL=1
fi

if command -v node >/dev/null 2>&1; then
  for f in "$ROOT"/app/pc-dist/shared-worker.*.js "$ROOT"/app/pc-dist/lazy/main-startup.*.js; do
    [ -e "$f" ] || continue
    if node --check "$f" >/dev/null 2>&1; then
      ok "cú pháp $(basename "$f")"
    else
      warn "cú pháp $(basename "$f") — khôi phục bản gốc: cp '${f}.orig' '${f}'"
      FAIL=1
    fi
  done
  if [ -f "$HERE/test_sync_patch.js" ]; then
    say ""
    node "$HERE/test_sync_patch.js" "$ROOT/app" || true
  fi
else
  warn "không có node nên bỏ qua kiểm tra cú pháp"
fi

[ "$FAIL" = 1 ] && die "Có bước kiểm tra không đạt. Bản gốc vẫn ở các file .orig — không mất gì."

# ---------- 5. Cài vào menu ứng dụng ----------
RUN_PATH="$ROOT/AppRun"
if [ "$DESKTOP_ENTRY" = 1 ]; then
  say ""
  say "== Cài vào $DEST"
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  cp -a "$ROOT" "$DEST"
  chmod +x "$DEST/AppRun" "$DEST/zalo" 2>/dev/null || true

  APPDIR="$HOME/.local/share/applications"
  mkdir -p "$APPDIR"
  ICON="$DEST/.DirIcon"
  if [ ! -f "$ICON" ]; then
    ICON="$(find "$DEST/usr/share/icons" -name 'zalo.png' 2>/dev/null | head -1)"
  fi
  [ -n "$ICON" ] && [ -f "$ICON" ] || ICON="application-x-executable"
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
  chmod +x "$APPDIR/zalo.desktop"
  update-desktop-database "$APPDIR" >/dev/null 2>&1 || true
  ok "đã tạo $APPDIR/zalo.desktop (Zalo hiện trong menu ứng dụng)"
  ok "gỡ cài đặt: rm -rf '$DEST' '$APPDIR/zalo.desktop'"
  RUN_PATH="$DEST/AppRun"
fi

say ""
say "== XONG. Chạy Zalo:"
say "   mở 'Zalo' trong menu ứng dụng"
say "   hoặc:  $RUN_PATH --no-sandbox"
[ -f "$HERE/run.sh" ] && say "   hoặc:  $HERE/run.sh"
if [ "$HAVE_FUSE" = 0 ]; then
  say ""
  warn "Nhớ cài FUSE v2 TRƯỚC khi chạy: $(apt_hint "$FUSE_PKG")"
fi
say ""
say "== Đăng nhập xong, đồng bộ tin nhắn cũ sẽ chạy. Dấu hiệu vá hoạt động:"
say "   ~/.config/ZaloData/Database/_production/*/Sync.db — bảng missing_message_range giảm dần"
say "   Log chẩn đoán: chạy kèm --enable-logging=stderr rồi tìm dòng [SYNC]"