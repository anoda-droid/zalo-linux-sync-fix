# zalo-linux-sync-fix

Vá lỗi **không đồng bộ được tin nhắn** (sync từ điện thoại / tin nhắn cũ) cho
[Zalo for Linux](https://github.com/doandat943/zalo-for-linux) — bản port
macOS → Linux.

> Không liên kết với VNG/Zalo. Đây là script cộng đồng, dùng AppImage bạn tự tải về.
> Chạy client không chính thức có thể vi phạm điều khoản sử dụng của Zalo — nên
> thử bằng tài khoản phụ trước.

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

## 4. Cách dùng

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