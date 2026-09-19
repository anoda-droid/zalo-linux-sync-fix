#!/usr/bin/env bash
# qa_local.sh — kiểm tra repo trước khi phát hành (không cần Zalo thật, chạy nhanh)
# Dùng: ./tools/qa_local.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { printf '   [ĐẠT]  %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '   [HỎNG] %s\n' "$*"; FAIL=$((FAIL+1)); }
head_() { printf '\n== %s\n' "$*"; }

head_ "1. Cú pháp"
for f in install.sh run.sh; do
  bash -n "$HERE/$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"
done
python3 - <<EOF && ok "python: patch_zalo_sync.py + tools/fetch_zalo.py" || bad "python syntax"
import ast
for f in ("$HERE/patch_zalo_sync.py", "$HERE/tools/fetch_zalo.py"):
    ast.parse(open(f, encoding="utf-8").read())
EOF
command -v node >/dev/null 2>&1 && { node --check "$HERE/test_sync_patch.js" && ok "node --check test_sync_patch.js" || bad "test_sync_patch.js"; }

head_ "2. install.sh --help"
"$HERE/install.sh" --help >/dev/null 2>&1 && ok "install.sh --help" || bad "install.sh --help"

head_ "3. Phát hiện Zalo đổi code (patch không khớp -> mã lỗi 3)"
T="$(mktemp -d)"
mkdir -p "$T/squashfs-root/app/pc-dist/lazy"
: > "$T/squashfs-root/app/bootstrap.js"
echo 'console.log("bundle gia, khong co pattern nao")' > "$T/squashfs-root/app/pc-dist/shared-worker.gia.js"
python3 "$HERE/patch_zalo_sync.py" "$T/squashfs-root" >"$T/out.txt" 2>&1
RC=$?
grep -q "KHÔNG KHỚP" "$T/out.txt" && ok "báo đúng 'KHÔNG KHỚP'" || bad "không báo KHÔNG KHỚP"
[ "$RC" = 3 ] && ok "mã lỗi = 3" || bad "mã lỗi = $RC (mong đợi 3)"
rm -rf "$T"

head_ "4. Chạy khi thiếu node (cảnh báo, không chết)"
B="$(mktemp -d)"
for c in bash env python3 cp mv rm mkdir df awk stat grep find chmod sed basename dirname tail head cat tr ldconfig date uname; do
  p="$(command -v $c 2>/dev/null)" && ln -sf "$p" "$B/$c"
done
OUT="$(PATH="$B" "$HERE/install.sh" /khong/co/that.AppImage 2>&1 || true)"
if echo "$OUT" | grep -q "Không có node"; then ok "cảnh báo thiếu node"; else bad "không cảnh báo thiếu node"; echo "$OUT" | head -5 | sed 's/^/        /'; fi
if echo "$OUT" | grep -q "Không thấy file"; then ok "vẫn kiểm tra tiếp rồi báo thiếu AppImage"; else bad "dừng sai chỗ"; fi
rm -rf "$B"

head_ "5. Tự tải: hỏi được GitHub API (cần mạng)"
if python3 "$HERE/tools/fetch_zalo.py" --check 2>/dev/null | grep -q "Sẽ chọn"; then
  ok "chọn đúng file AppImage mới nhất: $(python3 "$HERE/tools/fetch_zalo.py" --check 2>/dev/null | grep 'Sẽ chọn' | cut -d' ' -f3-)"
else
  bad "không hi được GitHub API (bỏ qua nếu máy không có mạng)"
fi

printf '\n== KẾT QUẢ: %d đạt, %d hỏng\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]