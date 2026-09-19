# zalo-linux-sync-fix

Vá lỗi **không đồng bộ được tin nhắn** (sync từ điện thoại / tin nhắn cũ) cho
[Zalo for Linux](https://github.com/doandat943/zalo-for-linux) — bản port
macOS → Linux.

> Không liên kết với VNG/Zalo. Đây là script cộng đồng, dùng AppImage bạn tự tải về.
> Chạy client không chính thức có thể vi phạm điều khoản sử dụng của Zalo — nên
> thử bằng tài khoản phụ trước.

## 0. Cách nhanh nhất — tải 1 file, chạy như file .exe

Vào **[Releases](https://github.com/anoda-droid/zalo-linux-sync-fix/releases)**,
tải file `Zalo-<phiên bản>-syncfix-x86_64.AppImage` (~243MB, **đã vá sẵn**):

```bash
# Ubuntu 24.04+ / Zorin 18 / Mint 22 dùng libfuse2t64; Ubuntu 22.04 / Zorin 17 / Mint 21 dùng libfuse2
sudo apt install -y libfuse2t64        # (máy cũ hơn: sudo apt install -y libfuse2)
chmod +x Zalo-*-syncfix-x86_64.AppImage
./Zalo-*-syncfix-x86_64.AppImage --no-sandbox
```

Hoặc không dùng dòng lệnh: chuột phải file → **Properties → Permissions → tick
"Allow executing file"**, rồi **double-click** — giống hệt mở file `.exe` bên Windows.

Muốn có icon trong menu ứng dụng (như cài đặt thật):

* Cài **GearLever** (Ubuntu/Mint/Zorin — `flatpak install flathub it.mijorus.gearlever`)
  rồi bấm **Integrate**; hoặc **AppImageLauncher**.
* Hoặc chạy `./install.sh` — tự tải, vá và tạo mục Zalo trong menu.

File này được tạo tự động bằng CI (xem `.github/workflows/build-appimage.yml`), mỗi khi
Zalo ra bản mới thì workflow tạo release mới. Vẫn có thể tự vá bằng script nếu muốn
(phần dưới).

## 1. Triệu chứng

- Đăng nhập được nhưng đồng bộ tin nhắn cũ từ điện thoại không chạy / chạy xong thiếu
- Hội thoại hiện ra nhưng không có tin nhắn
- Ảnh cũ không hiện

Kiểm tra dấu vết lỗi trong profile Zalo (`~/.config/ZaloData`):

| File | Bảng | Ý nghĩa |
|---|---|---|
| `Database/_production/*/Res.db` | `SyncDownload` | dòng có `errorName = SYNC_ACTION_MSG_NOT_READY` → tin nhắn điều khiển đồng bộ không sẵn sàng |
| `Database/_production/*/Sync.db` | `missing_message_range` | các khoảng tin nhắn cũ bị đánh dấu thiếu (`reason = first_sync`) |

## 2. Nguyên nhân gốc

Bản dựng 26.8.20 **có** phần C++ giải mã file backup (`db-cross-v4`) nhưng
**thiếu toàn bộ phần vá phía JavaScript** của tác giả reverse-engineer
([realdtn2](https://github.com/realdtn2/zalo-linux-2026) — PR #24, commit
`08046b8` *"Completely fixed sync process"*). PR đó **không được merge**: repo chỉ
nhận mã nguồn C++, 2 script vá JS (`patch-shared-worker.js`,
`patch-main-startup.js`) bị bỏ lại.

Trong bundle JS của Zalo (đã kiểm chứng bằng cách chạy thật):

| Vấn đề | Hệ quả |
|---|---|
| `crossMsgToNormalMsg()` trả `undefined` khi `idStore` thiếu ánh xạ | **tin nhắn bị bỏ rơi im lặng** — đúng tình huống lần đồng bộ đầu tiên, vì bảng ánh xạ id chưa có dữ liệu |
| Khôi phục hội thoại: `noiseIdStore.get(e.ownerId)` không có fallback | hội thoại không có noiseId bị loại khỏi danh sách |
| `convertCrossV2ToCrossV1()`: `if(!t) return null` | loại tin nhắn lạ bị bỏ; `fromId`/`ownerId` không chuẩn hoá tiền tố `g` của nhóm |
| media cũ mất `localPath` | ảnh cũ không hiện |
| module ảnh JXL: JS đòi `build/linux_x64/jxl.node` nhưng file build ra tên `zjxl.node` | module ảnh không tải được |

## 3. Script này làm gì

`patch_zalo_sync.py` áp **9 patch** (8 vào `pc-dist/shared-worker.*.js`, 1 vào
`pc-dist/lazy/main-startup.*.js`) + **1 fix tên file**:

| ID | Việc |
|---|---|
| SW1 | không bỏ rơi tin nhắn khi `idStore` rỗng; tách JSON nằm sau `\|\|` trong `msg` và trộn vào `attach` |
| SW2 | hội thoại khôi phục luôn được giữ (`noiseIdStore.get(ownerId) \|\| ownerId`) |
| SW3 | nhớ `convId` suy ra từ tên file `.db` |
| SW4 | không bỏ loại tin nhắn lạ (`\|\| "webchat"`), chuyển `BinNet` thành `Buffer` |
| SW4b | trả `fromId`/`ownerId` đã chuẩn hoá (bỏ tiền tố `g`) + `localPathRaw` |
| SW5 | giữ `localPath` của media cũ |
| SW6, SW7 | log chẩn đoán `[SYNC]` (số tin nhắn ghi được, định dạng backup) |
| MS1 | xoá hội thoại: chuẩn hoá `convId` nhóm + thử lại khi không tìm thấy |
| FIX-JXL | tạo `jxl.node` từ `zjxl.node` |

## 4. Cài nhanh trên Ubuntu / Linux Mint / Zorin OS

```bash
# 1. Cài sẵn mấy gói cần thiết
#    Ubuntu 24.04+/Zorin 18/Mint 22: libfuse2t64   |   Ubuntu 22.04/Zorin 17/Mint 21: libfuse2
sudo apt update && sudo apt install -y git python3 libfuse2t64 xdg-utils

# 2. Lấy script vá
git clone https://github.com/anoda-droid/zalo-linux-sync-fix.git
cd zalo-linux-sync-fix

# 3. Vá + cài vào menu ứng dụng. Không truyền gì thì script TỰ TẢI AppImage
#    Zalo mới nhất từ GitHub release của doandat943 (~263MB) rồi vá luôn.
./install.sh --install-desktop

# 4. Chạy: mở "Zalo" trong menu, hoặc
./run.sh
```

Muốn dùng file AppImage anh/chị đã tải sẵn (hoặc bản Full có Wine để gọi điện):

```bash
./install.sh --install-desktop ~/Downloads/Zalo-26.8.20-ecfb96a.AppImage
./install.sh --install-desktop --full          # bản Full (~464MB, có zcall qua Wine)
```

`install.sh` tự làm hết: kiểm tra python3/node/libfuse2 → tự tải AppImage (nếu chưa có)
→ bung → vá 9 patch → kiểm tra cú pháp JS → chạy A/B test → copy vào
`~/.local/opt/zalo-linux` và tạo `~/.local/share/applications/zalo.desktop`.

Gỡ cài đặt:

```bash
rm -rf ~/.local/opt/zalo-linux ~/.local/share/applications/zalo.desktop
```

Fedora/Bazzite: thay bước 1 bằng `sudo dnf install -y git python3 fuse-libs xdg-utils`.

> **Vì sao repo không để sẵn file AppImage?** Vì bên trong AppImage là mã của
> Zalo/VNG. Đưa bản đã đóng gói lên repo là phân phối lại phần mềm của họ (dễ bị
> gỡ, và không cần thiết). Repo chỉ chứa **script**; `install.sh` tự tải bản
> chính thức rồi vá **ngay trên máy bạn** — kết quả y như nhau, mà không phân
> phối lại gì của Zalo.

## 4c. Yêu cầu & dung lượng

| Mục | Cần gì |
|---|---|
| Kiến trúc | x86_64 (bản port này **chưa** hỗ trợ ARM/aarch64 — xem issue #70 của repo gốc) |
| Hệ điều hành | Ubuntu 22.04+, Linux Mint 21+, Zorin OS 17+, Debian 12+, Pop!_OS, Fedora — và WSL |
| python3 | >= 3.6 (mặc định có sẵn trên các distro trên) |
| FUSE v2 | **bắt buộc** để chạy AppImage: `libfuse2t64` (Ubuntu 24.04+/Zorin 18/Mint 22) hoặc `libfuse2` (Ubuntu 22.04/Zorin 17/Mint 21); Fedora: `fuse-libs` |
| node | tuỳ chọn — chỉ để kiểm tra cú pháp sau khi vá |
| 7z hoặc squashfs-tools | tuỳ chọn — chỉ dùng khi cách bung chuẩn gặp lỗi |
| Dung lượng trống | ~2.6GB (AppImage ~264MB + bản bung ~700MB + bản cài ~700MB) |
| Mạng | cần khi để script tự tải AppImage (~264MB) |

## 4d. Cách dùng thủ công (không cần install.sh)

```bash
# 1. Tải AppImage Zalo for Linux (bản mới nhất)
#    https://github.com/doandat943/zalo-for-linux/releases

# 2. Vá trực tiếp vào AppImage (bung ra <tên>.fixed/ rồi sửa)
python3 patch_zalo_sync.py --appimage Zalo-26.8.20-ecfb96a.AppImage

# 3. Chạy
./Zalo-26.8.20-ecfb96a.AppImage.fixed/squashfs-root/AppRun --no-sandbox
```

Hoặc vá trên thư mục đã bung sẵn:

```bash
python3 patch_zalo_sync.py /duong/dan/squashfs-root
# xem trước, không sửa gì:
python3 patch_zalo_sync.py --check /duong/dan/squashfs-root
```

Hoặc dùng script gộp (`install.sh`) để vá + đóng gói lại thành AppImage mới:

```bash
./install.sh Zalo-26.8.20-ecfb96a.AppImage     # -> Zalo-patched.AppImage
```

An toàn: mỗi file được sao lưu `.orig` trước khi sửa; chạy lại nhiều lần **không**
bị vá chồng (có marker kiểm tra); patch nào không khớp (Zalo đổi code) sẽ báo
`KHÔNG KHỚP` chứ không phá file.

## 5. Kiểm chứng

```bash
# cú pháp JS sau khi vá
node --check squashfs-root/app/pc-dist/shared-worker.*.js

# A/B test logic đã vá (không cần đăng nhập)
node test_sync_patch.js squashfs-root/app
```

Kết quả chạy thật trên AppImage 26.8.20:

```
[1] idStore RỖNG (lúc khôi phục từ điện thoại)
    TRƯỚC khi vá: undefined  -> TIN NHẮN BỊ BỎ RƠI
    SAU khi vá  : giữ lại: fromId=555 ownerId=9999
    => ĐÃ SỬA ĐƯỢC LỖI MẤT TIN NHẮN
[2] idStore ĐÃ CÓ ánh xạ -> GIỮ NGUYÊN hành vi cũ
[3] msg chứa JSON sau "||" -> ĐÃ tách JSON và trộn vào attach
[4] Chuẩn hoá id nhóm ("g123456" -> "123456") -> ĐÚNG
[5] Hội thoại khôi phục khi chưa có ánh xạ noiseId -> được giữ
```

Log chẩn đoán sau khi vá (chạy kèm `--enable-logging=stderr`, tìm `[SYNC]`):

```
[SYNC] decrypt format=1 convCount=... in=/...
[SYNC] insertToDb ok=1234 fail=0
```

## 5b. Xử lý sự cố (máy mới cài lần đầu)

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `AppImages require FUSE to run` / AppImage không mở | thiếu FUSE v2 | `sudo apt install libfuse2t64` (Ubuntu 24.04+/Zorin 18) hoặc `libfuse2` (Ubuntu 22.04/Zorin 17); Fedora: `fuse-libs`. Hoặc chạy `./run.sh /duong/dan/Zalo-*.AppImage` — tự dùng chế độ extract-and-run |
| `The SUID sandbox helper binary was found, but is not configured correctly` | chrome-sandbox không có setuid root | chạy kèm `--no-sandbox` (file `.desktop` do `install.sh` tạo đã có sẵn) |
| `GPU process isn't usable. Goodbye.` (máy ảo / WSLg) | tăng tốc GPU không khả dụng | `ZALO_DISABLE_GPU=1 ./run.sh` |
| Cửa sổ không hiện nhưng tiến trình vẫn chạy | lệch màn hình / WSLg | kiểm tra bằng `python3 tools/xwin.py`; thử `ZALO_OZONE=x11 ./run.sh` |
| Vá báo `KHÔNG KHỚP` | Zalo ra bản mới, code đã đổi | không sao — bản gốc còn ở `*.orig`. Báo issue kèm phiên bản Zalo |
| Vá báo không bung được AppImage | thiếu công cụ bung | `sudo apt install p7zip-full squashfs-tools`, hoặc bung tay: `<AppImage> --appimage-extract` rồi `python3 patch_zalo_sync.py ./squashfs-root` |
| Dán ảnh từ clipboard không được | thiếu công cụ clipboard | `sudo apt install wl-clipboard xclip` |
| Gọi điện báo `no usable wine` | bản thường không kèm Wine | cài lại bằng `./install.sh --full` |
| Không mở được vì đã có phiên khác | Zalo chỉ cho 1 phiên | đóng phiên đang chạy trước |
| Đồng bộ bị dừng giữa đường, WSL tự tắt | ổ đĩa chứa WSL hết chỗ | giải phóng ổ, hoặc chuyển distro sang ổ khác: `wsl --shutdown` rồi `wsl --manage Ubuntu --move F:\WSL\Ubuntu` |
| Cài xong không thấy Zalo trong menu | cache menu | `update-desktop-database ~/.local/share/applications` rồi đăng nhập lại; kiểm tra file `~/.local/share/applications/zalo.desktop` |
| Vẫn thiếu tin nhắn cũ sau khi đồng bộ xong | giới hạn của bản port (cấu trúc DB khác bản Windows) | dùng đường xuất/nhập `.zip` ở mục 6 |

Đăng nhập được nhưng danh sách hội thoại còn trống: bình thường — đồng bộ chạy **dần
theo từng đợt** (incremental). Theo dõi tiến độ:

```bash
python3 - <<'EOF'
import sqlite3, glob
for p in glob.glob("~/.config/ZaloData/Database/_production/*/Sync.db".replace("~", __import__("os").path.expanduser("~"))):
    c = sqlite3.connect("file:" + p + "?mode=ro", uri=True)
    print(p.split("/")[-2], c.execute("select status,count(*) from missing_message_range group by status").fetchall())
    c.close()
EOF
```

Muốn xem log chẩn đoán của bản vá:

```bash
ZALO_DISABLE_GPU=1 ./run.sh --enable-logging=stderr 2>&1 | grep "\[SYNC\]"
# [SYNC] decrypt format=1 convCount=...
# [SYNC] insertToDb ok=1234 fail=0
```

## 6. Đường bảo đảm cho tin nhắn cũ (khuyến nghị của maintainer)

Đồng bộ trực tiếp từ điện thoại trên bản port macOS→Linux vẫn có thể thiếu dữ liệu
(cấu trúc DB khác bản Windows). Cách chắc ăn:

1. Trên **Zalo Windows**: menu → **Xuất dữ liệu** → lưu file `.zip`
2. Trên **Zalo Linux**: xoá `~/.config/ZaloData`, đăng nhập lại
3. Trên **Zalo Linux**: **Nhập dữ liệu** → chọn file `.zip` vừa xuất

## 7. Ghi chú / giới hạn

- Gọi điện (zcall) vẫn cần Wine — không liên quan lỗi đồng bộ.
- `zwalker` (dọn tài nguyên media) không có binary Linux trong bản dựng → chức
  năng dọn file cũ báo *"not support"*; không ảnh hưởng đồng bộ tin nhắn.
- Chạy trong WSL cần `--no-sandbox`; nếu WSLg crash GPU thì thêm `--disable-gpu`.
  Ổ đĩa chứa WSL (thường C:) cần đủ trống — hết chỗ sẽ làm WSL tự tắt giữa lúc đồng bộ.
  Kiểm tra cửa sổ có thật sự hiện trên WSLg không: `python3 tools/xwin.py`
  (nói chuyện trực tiếp với X server, không cần xdotool/xwininfo).
- Script chỉ sửa bundle **trên máy bạn**, không phân phối lại mã của Zalo.

## 8. Giấy phép

MIT (xem `LICENSE`) — chỉ áp dụng cho script trong repo này.