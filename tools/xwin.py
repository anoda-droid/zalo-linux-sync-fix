#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Liệt kê cửa sổ X11 trên DISPLAY=:0 (WSLg) — kiểm tra cửa sổ Zalo có đang HIỆN không.
Không cần xdotool/xwininfo: nói chuyện trực tiếp với X server qua socket."""
import socket
import struct
import sys


class X:
    def __init__(self, path="/tmp/.X11-unix/X0"):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(path)
        self.seq = 0
        self.setup()

    def _recv(self, n):
        buf = b""
        while len(buf) < n:
            c = self.s.recv(n - len(buf))
            if not c:
                break
            buf += c
        return buf

    def setup(self):
        self.s.sendall(b"l" + struct.pack("<HHHHH", 11, 0, 0, 0, 0) + b"\x00\x00")
        head = self._recv(8)
        ok, _, major, minor, length = struct.unpack("<BBHHH", head)
        if ok != 1:
            raise SystemExit("X11 setup thất bại")
        self.data = self._recv(length * 4)
        vlen = struct.unpack_from("<H", self.data, 24)[0]
        off = 32 + ((vlen + 3) // 4) * 4
        self.root = struct.unpack_from("<I", self.data, off)[0]
        self.screens = struct.unpack_from("<B", self.data, 28)[0]
        print("X11 %d.%d | số màn hình: %d | root=0x%08x" % (major, minor, self.screens, self.root))
        # kích thước màn hình: trong screen, sau root(4) + colormap(4) + white(4) + black(4) + input(4)
        self.win_w, self.win_h = struct.unpack_from("<HH", self.data, off + 20)
        print("Độ phân giải X: %dx%d" % (self.win_w, self.win_h))

    def _send(self, payload):
        self.seq += 1
        self.s.sendall(payload + struct.pack("<H", self.seq))
        return self.seq

    def _reply(self):
        head = self._recv(32)
        ln = struct.unpack_from("<I", head, 4)[0]
        body = self._recv(ln * 4) if ln else b""
        return head, body

    def query_tree(self, win=None):
        win = self.root if win is None else win
        self._send(struct.pack("<BBHI", 15, 0, 1, win))
        head, _ = self._reply()
        n = struct.unpack_from("<H", head, 16)[0]
        kids = self._recv(4 * n)
        return [struct.unpack_from("<I", kids, i * 4)[0] for i in range(n)]

    def attrs(self, win):
        self._send(struct.pack("<BBHII", 3, 0, 2, win, 0))
        head, _ = self._reply()
        return {"map_state": head[26], "class": struct.unpack_from("<H", head, 12)[0]}

    def name(self, win):
        self._send(struct.pack("<BBHIIII", 20, 0, 6, 0, win, 39, 0, 4096))
        head, body = self._reply()
        fmt = head[1]
        n = struct.unpack_from("<I", head, 16)[0]
        if not n:
            return ""
        raw = body[: n * (fmt // 8)]
        return raw.decode("utf-8", "ignore").strip("\x00")

    def geometry(self, win):
        self._send(struct.pack("<BBHI", 14, 0, 2, win))
        head, _ = self._reply()
        return struct.unpack_from("<hhHH", head, 8)  # x, y, w, h


def walk(x, win, depth=0, out=None):
    out = [] if out is None else out
    a = x.attrs(win)
    n = x.name(win)
    g = x.geometry(win)
    out.append((depth, win, a["map_state"], g, n))
    if depth < 3:
        for k in x.query_tree(win):
            walk(x, k, depth + 1, out)
    return out


if __name__ == "__main__":
    try:
        x = X()
    except Exception as e:
        print("Không kết nối được X0:", e)
        sys.exit(1)
    state = {0: "ẩn", 1: "không xem được", 2: "ĐANG HIỆN"}
    found = False
    tops = x.query_tree()
    print("Số cửa sổ gốc:", len(tops))
    print()
    for w in tops:
        for depth, wid, ms, (gx, gy, gw, gh), nm in walk(x, w):
            if ms == 2 and nm:
                found = True
                print("  %s0x%08x  vị trí (%d,%d) kích thước %dx%d  [%s]  '%s'"
                      % ("  " * depth, wid, gx, gy, gw, gh, state[ms], nm))
    if not found:
        print("  -> KHÔNG có cửa sổ nào đang hiển thị (có tên)")
    # cảnh báo cửa sổ nằm ngoài màn hình
    print()
    print("Màn hình ảo: %dx%d" % (x.win_w, x.win_h))