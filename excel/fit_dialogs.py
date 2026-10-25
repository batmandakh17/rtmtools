"""Fit the labels of the rtmtools dialogs to their controls.

Stata draws dialog text in the system font and clips it at the control's width, so a label longer
than its control is cut off on screen (static lints do not see it). This script measures every
label with the system font at 13 pt, switches each dialog to the widest standard size
(_std_xxwide: inner width 680), widens a label that needs more room, and moves the control that
sits beside it on the same row to the right. Labels that cannot fit are listed for shortening.

Run from the package folder:  python3 excel/fit_dialogs.py [--check]
"""
import glob
import os
import re
import sys

from PIL import ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 13)
IWD = 680
RIGHT = 10 + IWD                         # the inner right edge of an _std_xxwide dialog
XMAP = {"_lft": 10, "_ilft": 20, "_iilft": 30, "_lft2": 360, "_indent": None}
WMAP = {"_iwd": IWD, "_vnwd": 120, "_inwd": IWD - 20, "_ibwd": IWD - 20, "_cwd1": 330}
PAD = {"TEXT": 6, "RADIO": 26, "CHECKBOX": 26, "GROUPBOX": 16}
HDR = re.compile(r"^(\s*)(TEXT|RADIO|CHECKBOX|GROUPBOX|EDIT|VARNAME|VARLIST|COMBOBOX|SPINNER|FILE|BUTTON|LISTBOX|EXP)(\s+)(\w+)(\s+)(\S+)(\s+)(\S+)(\s+)(\S+)(\s+)(\S+?)(,.*)$")


def textw(s):
    return FONT.getlength(s)


def parse(lines):
    """Controls in order with their header line index, fields, label and absolute x."""
    ctrls = []
    prev_x = 10
    for i, ln in enumerate(lines):
        m = HDR.match(ln)
        if not m:
            continue
        typ, name, x, y, w = m.group(2), m.group(4), m.group(6), m.group(8), m.group(10)
        if x.startswith(("+", "-")) and x[1:].isdigit():
            ax = prev_x + int(x)
        elif x == "@":
            ax = prev_x
        elif x.isdigit():
            ax = int(x)
        elif x in XMAP and XMAP[x] is not None:
            ax = XMAP[x]
        else:
            ax = prev_x
        label = None
        for k in range(i, min(i + 6, len(lines))):
            lm = re.search(r'label\("((?:[^"\\]|\\.)*)"\)', lines[k])
            if lm:
                label = lm.group(1)
                break
            if k > i and HDR.match(lines[k]):
                break
        ctrls.append({"i": i, "typ": typ, "name": name, "x": x, "y": y, "w": w, "ax": ax, "label": label, "m": m})
        prev_x = ax
    return ctrls


def width_of(c, prev_w):
    w = c["w"]
    if w.isdigit():
        return int(w)
    if w in WMAP:
        return WMAP[w]
    if w == "@":
        return prev_w
    return None


def set_field(lines, c, field, value):
    m = HDR.match(lines[c["i"]])
    g = list(m.groups())
    idx = {"x": 5, "w": 9}[field]
    old = g[idx]
    g[idx] = value
    # keep the columns: pad the following whitespace by the change in length
    sp = idx + 1
    g[sp] = " " * max(1, len(g[sp]) - (len(value) - len(old)))
    lines[c["i"]] = "".join(g)


def fit(path, check=False):
    lines = open(path, encoding="utf-8").read().split("\n")
    if not check:
        lines = [re.sub(r"INCLUDE _std_\w+", "INCLUDE _std_xxwide", ln) if ln.startswith("INCLUDE _std_") else ln for ln in lines]
    ctrls = parse(lines)
    todo = []
    pairs = []          # (label control, control beside it, room needed)
    alone = []
    prev_w = IWD
    for n, c in enumerate(ctrls):
        cw = width_of(c, prev_w)
        if cw is not None:
            prev_w = cw
        if c["label"] is None or c["typ"] not in PAD or cw is None:
            continue
        need = int(textw(c["label"]) + PAD[c["typ"]]) + 2
        nxt = ctrls[n + 1] if n + 1 < len(ctrls) else None
        if nxt is not None and nxt["y"] == "@" and nxt["ax"] > c["ax"]:
            pairs.append((c, nxt, need, n))
        elif need > cw:
            alone.append((c, need))
    # a column = the controls beside a label that share one absolute x; it moves as one, far enough
    # for the longest label of the column
    cols = {}
    for c, nxt, need, n in pairs:
        if nxt["x"].isdigit():
            cols.setdefault(int(nxt["x"]), []).append((c, nxt, need, n))
    newx = {}
    for x0, members in cols.items():
        req = max(c["ax"] + need + 6 for c, nxt, need, n in members)
        newx[x0] = max(x0, req)
        widest = max((width_of(nxt, IWD) or 0) for c, nxt, need, n in members)
        if newx[x0] + widest > RIGHT:
            for c, nxt, need, n in members:
                if c["ax"] + need + 6 > x0:
                    todo.append((os.path.basename(path), c["name"], need, RIGHT - widest - c["ax"] - 6, c["label"]))
            newx[x0] = x0
    if not check:
        for c, nxt, need, n in pairs:
            if nxt["x"].isdigit():
                x1 = newx[int(nxt["x"])]
                if x1 != int(nxt["x"]):
                    set_field(lines, nxt, "x", str(x1))
                set_field(lines, c, "w", str(max(int(width_of(c, IWD) or 0), x1 - c["ax"] - 6)) if (width_of(c, IWD) or 0) < x1 - c["ax"] - 6 or need > (width_of(c, IWD) or 0) else c["w"])
            elif nxt["x"].startswith("+") and nxt["x"][1:].isdigit():
                room = int(nxt["x"][1:]) - 6
                if need > room:
                    nw = width_of(nxt, IWD) or 0
                    if c["ax"] + need + 6 + nw > RIGHT:
                        todo.append((os.path.basename(path), c["name"], need, RIGHT - nw - c["ax"] - 6, c["label"]))
                        continue
                    set_field(lines, nxt, "x", "+" + str(need + 6))
                    set_field(lines, c, "w", str(need))
        for c, need in alone:
            if c["ax"] + need > RIGHT:
                todo.append((os.path.basename(path), c["name"], need, RIGHT - c["ax"], c["label"]))
                continue
            if not (c["w"] == "_iwd" and need <= IWD):
                set_field(lines, c, "w", str(need))
        # absolute controls that follow a moved one on the same row move too
        open(path, "w", encoding="utf-8").write("\n".join(lines))
    else:
        for c, nxt, need, n in pairs:
            cw = width_of(c, IWD) or 0
            if need > cw:
                todo.append((os.path.basename(path), c["name"], need, cw, c["label"]))
        for c, need in alone:
            todo.append((os.path.basename(path), c["name"], need, width_of(c, IWD), c["label"]))
    return todo


if __name__ == "__main__":
    check = "--check" in sys.argv
    left = []
    for f in sorted(glob.glob(os.path.join(ROOT, "*.dlg"))):
        left += fit(f, check)
    for t in left:
        print(f"{t[0]}: {t[1]} needs {t[2]} px, has {t[3]}: {t[4]}")
    print(f"{len(left)} labels still too long")
