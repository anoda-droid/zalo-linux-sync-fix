#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tải AppImage Zalo for Linux mới nhất từ GitHub release (không cần token).

In tiến độ ra stderr, in ĐƯỜNG DẪN file cuối cùng ra stdout để script khác dùng:

    APPIMAGE="$(python3 tools/fetch_zalo.py --dest ~/Downloads)"

Tùy chọn:
    --full        lấy bản Full (có Wine, dùng được gọi điện zcall — nặng ~464MB)
    --tag X.Y.Z   lấy đúng bản phát hành đó (mặc định: mới nhất)
    --dest DIR    thư mục lưu (mặc định ~/Downloads)
    --check       chỉ xem có bản nào, không tải
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

REPO = "doandat943/zalo-for-linux"
UA = {"User-Agent": "zalo-linux-sync-fix (github.com/anoda-droid/zalo-linux-sync-fix)"}


def api(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def get_release(tag=None):
    if tag:
        return api("https://api.github.com/repos/%s/releases/tags/%s" % (REPO, tag))
    return api("https://api.github.com/repos/%s/releases/latest" % REPO)


def pick_asset(release, kind="normal"):
    cands = [a for a in release.get("assets", []) if a["name"].lower().endswith(".appimage")]
    if not cands:
        return None
    pool = [a for a in cands if ("full" in a["name"].lower()) == (kind == "full")]
    pool = pool or cands
    # ưu tiên bản gốc (không kèm ZaDark) cho nhẹ và ít can thiệp
    vanilla = [a for a in pool if "zadark" not in a["name"].lower()]
    pool = vanilla or pool
    return sorted(pool, key=lambda a: a["size"])[0]


def download(url, dest, size):
    os.makedirs(os.path.dirname(os.path.abspath(dest)) or ".", exist_ok=True)
    have = os.path.getsize(dest) if os.path.exists(dest) else 0
    if have == size and size > 0:
        print("[i] Đã có sẵn file đủ dung lượng: %s" % dest, file=sys.stderr)
        return dest
    if have > size:
        print("[i] File cũ lớn hơn (tải dở, hỏng?) — tải lại từ đầu", file=sys.stderr)
        have = 0
        os.remove(dest)

    headers = dict(UA)
    if have:
        headers["Range"] = "bytes=%d-" % have
        print("[i] Tải tiếp từ %.1f MB / %.1f MB" % (have / 1048576, size / 1048576), file=sys.stderr)

    req = urllib.request.Request(url, headers=headers)
    mode = "ab" if have else "wb"
    done = have
    last = 0
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, mode) as f:
        total = size or int(r.headers.get("Content-Length") or 0) + have
        while True:
            chunk = r.read(262144)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if done - last > 10 * 1048576:
                last = done
                pct = (done * 100.0 / total) if total else 0
                print("    ... %.1f MB / %.1f MB  (%.0f%%)"
                      % (done / 1048576, total / 1048576, pct), file=sys.stderr)

    real = os.path.getsize(dest)
    if size and real != size:
        print("!! Tải thiếu: %d / %d byte — chạy lại lệnh này để tải tiếp" % (real, size), file=sys.stderr)
        return None
    return dest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--full", action="store_true", help="lấy bản Full (có Wine cho zcall)")
    ap.add_argument("--tag", help="lấy đúng bản phát hành này")
    ap.add_argument("--dest", default=os.path.expanduser("~/Downloads"), help="thư mục lưu")
    ap.add_argument("--check", action="store_true", help="chỉ liệt kê, không tải")
    a = ap.parse_args()

    try:
        rel = get_release(a.tag)
    except urllib.error.HTTPError as e:
        print("!! Không hỏi được GitHub API (%s). Kiểm tra mạng, hoặc tải tay từ "
              "https://github.com/%s/releases" % (e, REPO), file=sys.stderr)
        return 2
    except Exception as e:
        print("!! Lỗi mạng: %s" % e, file=sys.stderr)
        return 2

    asset = pick_asset(rel, "full" if a.full else "normal")
    if not asset:
        print("!! Bản phát hành %s không có file .AppImage nào" % rel.get("tag_name"), file=sys.stderr)
        return 2

    if a.check:
        print("Bản mới nhất: %s (%s)" % (rel.get("tag_name"), rel.get("published_at")))
        for x in rel.get("assets", []):
            print("   %-55s %6.1f MB" % (x["name"], x["size"] / 1048576))
        print("Sẽ chọn: %s" % asset["name"])
        return 0

    dest = os.path.join(os.path.expanduser(a.dest), asset["name"])
    print("== Tải Zalo %s: %s (%.1f MB)"
          % (rel.get("tag_name"), asset["name"], asset["size"] / 1048576), file=sys.stderr)
    out = download(asset["browser_download_url"], dest, asset["size"])
    if not out:
        return 1
    print("[i] Xong: %s" % out, file=sys.stderr)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())