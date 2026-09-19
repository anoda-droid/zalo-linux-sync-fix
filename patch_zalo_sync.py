#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_zalo_sync.py — Vá lỗi ĐỒNG BỘ TIN NHẮN (sync từ điện thoại / tin nhắn cũ)
cho Zalo for Linux (doandat943/zalo-for-linux) và các bản port từ macOS khác.

VÌ SAO CẦN VÁ
-------------
Bản dựng hiện tại chỉ có phần C++ (db-cross-v4) để GIẢI MÃ file backup, nhưng
THIẾU toàn bộ phần vá phía JavaScript mà tác giả reverse-engineer đã viết
(realdtn2 — PR #24, commit 08046b8 "Completely fixed sync process").
PR đó không được merge: chỉ mã nguồn C++ được đưa vào, 2 script vá JS bị bỏ.

Hệ quả thực tế (đo được trên dữ liệu thật):
  * crossMsgToNormalMsg() bỏ rơi IM LẶNG mọi tin nhắn khi bảng ánh xạ id
    (idStore) chưa có dữ liệu — đúng tình huống của lần đồng bộ đầu tiên.
  * Hội thoại khôi phục về nhưng không có noiseId -> bị loại khỏi danh sách.
  * id nhóm ("g123...") không được chuẩn hoá -> tin nhắn nhóm sai người nhận.
  * Tin nhắn/hội thoại vẫn có dấu vết "SYNC_ACTION_MSG_NOT_READY" trong Res.db
    và hàng nghìn khoảng tin nhắn cũ nằm trong missing_message_range (Sync.db).

CÁCH DÙNG
---------
    python3 patch_zalo_sync.py --check                 # chỉ xem, không sửa
    python3 patch_zalo_sync.py                         # vá (tự dò thư mục app)
    python3 patch_zalo_sync.py /duong/dan/squashfs-root
    python3 patch_zalo_sync.py --appimage Zalo.AppImage
        # bung AppImage ra <tên>.fixed/ rồi vá

Sau khi vá AppImage, chạy bằng:
    /duong/dan/<tên>.fixed/AppRun --no-sandbox

An toàn: mỗi file được sao lưu thành <tên>.orig trước khi sửa; script chạy lại
nhiều lần không bị vá chồng (đã có marker kiểm tra).
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

# --------------------------------------------------------------------------
# Danh sách patch: (id, mô tả, regex, thay thế, thay_tất_cả, marker_đã_vá)
# --------------------------------------------------------------------------

P_SW_MSG = (
    "SW1-keep-message",
    "Không bỏ rơi tin nhắn khi idStore thiếu ánh xạ + tách JSON trong msg",
    r'if\(s===ee\.MSG_UNKNOWN\)return void 0;let r=e\.parsedIdTo\|\|this\.idStore\.get\(e\.ownerId\),'
    r'i=e\.parsedUidFrom\|\|e\.fromId==e\.userId\?"0":this\.idStore\.get\(e\.fromId\);'
    r'if\(!i\|\|!r\)return void 0;let n=e\.msg,a=e\.attachData;',
    'if(s===ee.MSG_UNKNOWN)return void 0;'
    'const m=e=>{if("string"!=typeof e||!e)return e;const _t=e.indexOf("||");'
    'if(_t>=0){const _s=e.slice(_t+2).trim();if(_s&&("{"===_s[0]||"["===_s[0]))return _s}return e},'
    'y=e=>{if("string"!=typeof e||!e)return null;const _t=m(e);if("string"!=typeof _t||!_t)return null;'
    'try{const _e=JSON.parse(_t);return _e&&"object"==typeof _e?_e:null}catch{return null}};'
    'let r=e.parsedIdTo||this.idStore.get(e.ownerId)||e.ownerId,'
    'i=e.parsedUidFrom||(e.fromId==e.userId?"0":(this.idStore.get(e.fromId)||e.fromId));'
    'if(!i||!r)return void 0;let n=m(e.msg),a=e.attachData;const c0=y(n);'
    'c0&&c0.data&&"object"==typeof c0.data&&(a.attach||(a.attach={}),Object.assign(a.attach,c0.data));',
    True,
    "Object.assign(a.attach,c0.data)",
)

P_SW_CONV = (
    "SW2-keep-conversation",
    "Hội thoại khôi phục không có noiseId vẫn được giữ (trước đây bị loại)",
    r'this\.noiseIdStore\.get\(e\.ownerId\)',
    'this.noiseIdStore.get(e.ownerId)||e.ownerId',
    True,
    'this.noiseIdStore.get(e.ownerId)||e.ownerId',
)

P_SW_CTOR = (
    "SW3-backupConvId",
    "Lấy convId từ tên file .db (dùng khi dựng lại tin nhắn)",
    r'this\.noiseId=void 0,this\._db=\$zsqlite\.createConnection\(e\.path,\{OPEN_CREATE:!0,OPEN_READWRITE:!0\}\)',
    'this.noiseId=void 0,this.backupConvId=(()=>{const _m=/([g]?\\d+)\\.db$/i.exec(e.path||"");'
    'return _m&&_m[1]?_m[1].replace(/^g/i,""):""})(),'
    'this._db=$zsqlite.createConnection(e.path,{OPEN_CREATE:!0,OPEN_READWRITE:!0})',
    False,
    "backupConvId=(()=>{",
)

P_SW_CONVERT = (
    "SW4-convert-message",
    "Không bỏ loại tin nhắn lạ + chuyển BinNet thành Buffer",
    r'convertCrossV2ToCrossV1\(e\)\{const t=je\[e\.MsgType\];if\(!t\)return null;'
    r'const s=Ue\.parseBinNet\(e\.BinNet\)\|\|\{\};',
    'convertCrossV2ToCrossV1(e){const t=je[e.MsgType]||"webchat";let _bin=e.BinNet;'
    'try{if("undefined"!=typeof Buffer&&Buffer&&Buffer.from&&_bin&&!Buffer.isBuffer(_bin)){'
    'if("undefined"!=typeof ArrayBuffer&&ArrayBuffer.isView&&ArrayBuffer.isView(_bin)&&_bin.buffer)'
    '_bin=Buffer.from(new Uint8Array(_bin.buffer,_bin.byteOffset||0,_bin.byteLength||_bin.length||0));'
    'else if(_bin instanceof Uint8Array)_bin=Buffer.from(_bin);'
    'else if(_bin&&"Buffer"===_bin.type&&Array.isArray(_bin.data))_bin=Buffer.from(_bin.data);'
    'else if(_bin&&Array.isArray(_bin.data)&&_bin.data.length&&"number"==typeof _bin.data[0])'
    '_bin=Buffer.from(_bin.data)}}catch{}'
    'const s=Ue.parseBinNet(_bin)||{};',
    False,
    'const t=je[e.MsgType]||"webchat"',
)

P_SW_CONVERT2 = (
    "SW4b-convert-return",
    "Trả về id đã chuẩn hoá (bỏ tiền tố g) + localPathRaw",
    r',\{fromId:e\.SenderId\.toString\(\),fromName:"",attach:"\{\}",attachData:r,'
    r'globalMsgId:e\.GlbMsgId,cliMsgId:e\.CliMsgId,msg:e\.MsgContent,ownerId:this\.noiseId,'
    r'ownerType:0,sequenseId:e\.TimeStamp,ts:e\.TimeStamp,ttl:e\.TTL,type:t,userId:this\.plainUserId\}\}',
    ',(_f=>{const _n=e=>{if(null===e||void 0===e)return"";const _s=String(e);'
    'return/^g\\d+$/.test(_s)?_s.slice(1):_s};'
    'const _from=[e.SenderId,e.FromId,e.fromId,e.FromUid,e.fromUid,r.fromD,r.uid]'
    '.find(e=>null!==e&&void 0!==e&&""!==e);'
    'const _own=[e.OwnerId,e.ownerId,e.ToId,e.toId,e.ReceiverId,e.ConversationId,this.backupConvId,this.noiseId]'
    '.find(e=>null!==e&&void 0!==e&&""!==e);'
    'const _o=null!==_from&&void 0!==_from?_from:this.noiseId;'
    'return{fromId:_n(_o),fromName:"",attach:"{}",attachData:r,globalMsgId:e.GlbMsgId,'
    'cliMsgId:e.CliMsgId,msg:e.MsgContent,ownerId:_n(_own),ownerType:0,sequenseId:e.TimeStamp,'
    'ts:e.TimeStamp,ttl:e.TTL,localPathRaw:e.LocalPath,type:t,userId:this.plainUserId}})()}',
    False,
    "localPathRaw:e.LocalPath",
)

P_SW_LOCALPATH = (
    "SW5-localPath",
    "Giữ localPath của media cũ khi khôi phục tin nhắn",
    r'l\.msgType!==ee\.MSG_UNKNOWN\?t\.push\(l\):',
    '(function(){const _p=e.localPathRaw;"string"==typeof _p&&_p.length>3'
    '&&/^[\\x20-\\x7E]+$/.test(_p)&&(l.localPath=_p)})(),'
    'l.msgType!==ee.MSG_UNKNOWN?t.push(l):',
    True,
    "const _p=e.localPathRaw",
)

P_SW_LOG = (
    "SW6-log-insert",
    "Log số tin nhắn ghi được khi đồng bộ (để kiểm chứng)",
    r'e=await this\._filterDeletedMessages\(e\);const t=await this\._insertMessage\(e\);return J\.a\.mediaRes\.start\(\)',
    'e=await this._filterDeletedMessages(e);const t=await this._insertMessage(e);'
    'console.error("[SYNC] insertToDb ok="+(t&&t.success?t.success.length:0)+'
    '" fail="+(t&&t.fail?t.fail.length:0));return J.a.mediaRes.start()',
    False,
    '[SYNC] insertToDb ok=',
)

P_SW_LOG2 = (
    "SW7-log-decrypt",
    "Log định dạng backup khi giải mã (0 = bản cũ, 1 = bản mới)",
    r'async _decyptBackup\(e\)\{const\{params:t,report:s\}=e;',
    'async _decyptBackup(e){const{params:t,report:s}=e;'
    'console.error("[SYNC] decrypt format="+t.format+" convCount="+t.numberOfConversationsCount+" in="+t.inputPath);',
    False,
    '[SYNC] decrypt format=',
)

P_MS_DELETE = (
    "MS1-delete-conversation",
    "Xoá hội thoại: chuẩn hoá convId nhóm + thử lại khi không tìm thấy",
    r'runDeleteMessages\(e,t,s\)\{try\{if\(e\.convId&&!this\.isNewDeleteEvent\(e\.convId,e\.initialDeleteTime\)\)'
    r'return void s\(new qp\(\{code:"CANCEL_DELETE_CONVERSATION",'
    r'message:`\$\{e\.convId\} Delete batch messages is canceled`\}\)\);'
    r'const i=await this\.getDeleteInfoByThread\(e\);',
    'runDeleteMessages(e,t,s){try{'
    'const _r0="string"==typeof e.convId&&e.convId.startsWith("g")?e.convId.slice(1):e.convId;'
    '_r0&&_r0!==e.convId&&(e=Object.assign({},e,{convId:_r0}));'
    'if(e.convId&&!this.isNewDeleteEvent(e.convId,e.initialDeleteTime))'
    'return void s(new qp({code:"CANCEL_DELETE_CONVERSATION",'
    'message:`${e.convId} Delete batch messages is canceled`}));'
    'let i=await this.getDeleteInfoByThread(e);'
    'if(!i&&"string"==typeof e.convId&&e.convId.startsWith("g"))'
    'try{i=await this.getDeleteInfoByThread(Object.assign({},e,{convId:e.convId.slice(1)}))}catch(_){}',
    False,
    'const _r0="string"==typeof e.convId',
)

PATCHES_SW = [P_SW_MSG, P_SW_CONV, P_SW_CTOR, P_SW_CONVERT, P_SW_CONVERT2, P_SW_LOCALPATH, P_SW_LOG, P_SW_LOG2]
PATCHES_MS = [P_MS_DELETE]


def find_app_root(path):
    """Trả về thư mục app/ (chứa bootstrap.js, main-dist, pc-dist)."""
    path = os.path.abspath(path)
    for c in (path, os.path.join(path, "app"), os.path.join(path, "resources", "app")):
        if os.path.isfile(os.path.join(c, "bootstrap.js")) and os.path.isdir(os.path.join(c, "pc-dist")):
            return c
    for root, dirs, files in os.walk(path):
        if root[len(path):].count(os.sep) > 2:
            dirs[:] = []
            continue
        if "bootstrap.js" in files and "pc-dist" in dirs:
            return root
    return None


def fix_jxl(root, dry):
    """Lỗi tên file: JS đòi build/linux_x64/jxl.node nhưng bản dựng đặt tên zjxl.node.
    Hậu quả: module ảnh JPEG-XL không tải được -> Zalo báo lỗi khi xử lý ảnh."""
    d = os.path.join(root, "native", "nativelibs", "zjxl", "build", "linux_x64")
    src, dst = os.path.join(d, "zjxl.node"), os.path.join(d, "jxl.node")
    if not os.path.isdir(d):
        return "SKIP (không thấy zjxl/build/linux_x64)"
    if os.path.exists(dst):
        return "SKIP (jxl.node đã có)"
    if not os.path.exists(src):
        return "SKIP (không thấy zjxl.node)"
    if dry:
        return "SẴN SÀNG tạo jxl.node (từ zjxl.node)"
    shutil.copy2(src, dst)
    return "ĐÃ tạo jxl.node (copy từ zjxl.node)"


def apply_to_file(fpath, patches, dry):
    src = open(fpath, encoding="utf-8", errors="surrogateescape").read()
    out = src
    report = []
    for pid, desc, pat, rep, all_, marker in patches:
        if marker and marker in out:
            report.append((pid, desc, "BỎ QUA (đã vá trước đó)", 0))
            continue
        rx = re.compile(pat)
        n = len(rx.findall(out))
        if n == 0:
            report.append((pid, desc, "KHÔNG KHỚP (bản Zalo khác?)", 0))
            continue
        if dry:
            report.append((pid, desc, "SẴN SÀNG vá %d chỗ" % n, n))
            continue
        out = rx.sub(lambda m: rep, out) if all_ else rx.sub(lambda m: rep, out, count=1)
        if marker and marker not in out:
            report.append((pid, desc, "LỖI (thay rồi nhưng không thấy marker)", n))
        else:
            report.append((pid, desc, "ĐÃ VÁ %d chỗ" % n, n))
    if not dry and out != src:
        if not os.path.exists(fpath + ".orig"):
            shutil.copy2(fpath, fpath + ".orig")
        open(fpath, "w", encoding="utf-8", errors="surrogateescape").write(out)
    return report


def squashfs_offset(path):
    """Tìm offset của hệ thống file squashfs bên trong AppImage (magic 'hsqs')."""
    with open(path, "rb") as f:
        pos = 0
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                return None
            i = chunk.find(b"hsqs")
            if i >= 0:
                return pos + i
            pos += len(chunk)


def extract_appimage(appimage, outdir, dry=False):
    """Bung AppImage. Cách 1: runtime có sẵn (--appimage-extract, KHÔNG cần FUSE).
    Cách 2: 7z. Cách 3: unsquashfs (tự dò offset)."""
    os.makedirs(outdir, exist_ok=True)
    root = os.path.join(outdir, "squashfs-root")
    if dry:
        return root

    def ok():
        return os.path.isdir(root) and os.path.isdir(os.path.join(root, "app"))

    # 1) runtime chuẩn của AppImage
    if os.path.exists(root):
        shutil.rmtree(root)          # bung lại từ đầu, tránh lẫn bản đã vá lần trước
    try:
        subprocess.run([appimage, "--appimage-extract"], cwd=outdir, check=True,
                       stdout=subprocess.DEVNULL)
    except Exception as e:
        print("   [!] Bung bằng AppImage runtime không được (%s)" % str(e).split("\n")[0])
        print("       Thử cách khác...")
    if ok():
        return root

    # 2) 7z / 7za / 7zz
    for tool in ("7z", "7za", "7zz"):
        if shutil.which(tool):
            try:
                subprocess.run([tool, "x", appimage, "-o" + outdir, "-y"], check=True,
                               stdout=subprocess.DEVNULL)
            except Exception:
                continue
            if ok():
                return root

    # 3) unsquashfs (cần dò offset đầu của squashfs)
    if shutil.which("unsquashfs"):
        off = squashfs_offset(appimage)
        if off:
            try:
                subprocess.run(["unsquashfs", "-o", str(off), "-f", "-d", root, appimage],
                               check=True, stdout=subprocess.DEVNULL)
            except Exception:
                pass
            if ok():
                return root

    print("!! Không bung được AppImage. Cách khắc phục:")
    print("   - Cài công cụ bung:  sudo apt install p7zip-full squashfs-tools")
    print("   - Hoặc bung tay rồi trỏ script vào thư mục:")
    print("       %s --appimage-extract            # tạo ./squashfs-root" % appimage)
    print("       python3 patch_zalo_sync.py ./squashfs-root")
    return root


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", nargs="?", help="thư mục app/ (hoặc thư mục chứa app/)")
    ap.add_argument("--appimage", help="file .AppImage cần bung ra rồi vá")
    ap.add_argument("--check", action="store_true", help="chỉ kiểm tra, không sửa")
    a = ap.parse_args()

    outdir = None
    if a.appimage:
        appimage = os.path.abspath(a.appimage)
        if not os.path.isfile(appimage):
            print("!! Không thấy file AppImage:", appimage)
            return 2
        outdir = appimage + ".fixed"
        print("== Bung AppImage:", appimage)
        print("   ->", outdir)
        target = extract_appimage(appimage, outdir, a.check)
        if not a.check and not os.path.isdir(os.path.join(target, "app")):
            return 2
    else:
        target = a.target or "."

    root = find_app_root(target)
    if not root:
        print("!! Không tìm thấy thư mục app (bootstrap.js + pc-dist) trong:", target)
        return 2

    print("== Thư mục app:", root)
    sw = sorted(glob.glob(os.path.join(root, "pc-dist", "shared-worker.*.js")))
    ms = sorted(glob.glob(os.path.join(root, "pc-dist", "lazy", "main-startup.*.js")))
    if not sw:
        print("!! Không thấy pc-dist/shared-worker.*.js")
        return 2

    missing = []

    def show(rep):
        for pid, desc, st, n in rep:
            print("   [%-24s] %-60s %s" % (pid, desc, st))
            if "KHÔNG KHỚP" in st:
                missing.append(pid)

    print("\n---- SHARED-WORKER:", os.path.basename(sw[0]))
    show(apply_to_file(sw[0], PATCHES_SW, a.check))

    if ms:
        print("\n---- MAIN-STARTUP:", os.path.basename(ms[0]))
        show(apply_to_file(ms[0], PATCHES_MS, a.check))
    else:
        print("\n!! Không thấy pc-dist/lazy/main-startup.*.js (bỏ qua patch xoá hội thoại)")

    if missing:
        print("\n!! %d patch KHÔNG khớp: %s" % (len(missing), ", ".join(missing)))
        print("   Nghĩa là bản Zalo này đã đổi code so với bản script được viết cho (26.8.20).")
        print("   - Không có gì bị phá: các file .orig vẫn giữ bản gốc.")
        print("   - Báo lỗi kèm phiên bản Zalo tại: https://github.com/anoda-droid/zalo-linux-sync-fix/issues")
        if not a.check:
            return 3

    print("\n---- FIX khác")
    print("   [%-24s] %-60s %s" % ("FIX-JXL", "Sửa tên file module ảnh JPEG-XL", fix_jxl(root, a.check)))

    if a.appimage and not a.check and outdir:
        print("\n== Bản đã vá:", os.path.join(outdir, "squashfs-root"))
        print("== Chạy:  %s/AppRun --no-sandbox" % os.path.join(outdir, "squashfs-root"))
        print("== Đóng gói lại thành AppImage (nếu muốn): cài appimagetool rồi")
        print("   ARCH=x86_64 appimagetool %s Zalo-patched.AppImage" % os.path.join(outdir, "squashfs-root"))
    return 0


if __name__ == "__main__":
    sys.exit(main())