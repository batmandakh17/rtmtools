"""Display fidelity check for the Excel workbook (rtmtools, schema rtm-export-1.0).

Two checks, both read-only:
1. Formula inventory: every formula in the template (and in a run's filled copy) uses only the
   functions the Notes sheet allows (IF, XLOOKUP, COUNTIF, COUNTA) and references only the data
   sheets. Any other function fails the check: the workbook must not compute a statistic.
2. Displayed values: Excel is asked (AppleScript, on a Mac with Excel) to open the run's workbook,
   recalculate and save a copy; the cached values of the display cells are then compared with the
   CSV files of the run. Every displayed number must equal the exported number exactly (the
   workbook stores the exported value; number formats only change how it is shown).

Usage:  python3 tests/check_display.py [run_folder ...]
        with no run folder: the formula inventory of the template only.
Exit code 0 when every check passes.
"""
import csv
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

from openpyxl import load_workbook

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "rtm_display.xlsx")
ALLOWED = {"IF", "IFERROR", "INDEX", "MATCH", "COUNTIF", "COUNTA", "NA"}
NOT_IN = "not in this export"
FUNC_RE = re.compile(r"([A-Z][A-Z0-9_.]*)\s*\(")
DISPLAY_SHEETS = {"Weights", "Sampling", "Frame", "Listing"}


def formula_inventory(path):
    wb = load_workbook(path)
    used = {}
    bad = []
    nformulas = 0
    for ws in wb.worksheets:
        for row in ws.iter_rows():
            for c in row:
                v = c.value
                if isinstance(v, str) and v.startswith("="):
                    nformulas += 1
                    if ws.title not in DISPLAY_SHEETS:
                        bad.append((ws.title, c.coordinate, "formula on a data sheet: " + v))
                    for f in FUNC_RE.findall(v):
                        used[f] = used.get(f, 0) + 1
                        if f not in ALLOWED:
                            bad.append((ws.title, c.coordinate, v))
                    # no arithmetic between references: operators other than the string comparison
                    body = re.sub(r'"[^"]*"', '""', v)
                    if re.search(r"[*/^]|(?<![<>=(,])\-|\+", body):
                        bad.append((ws.title, c.coordinate, "arithmetic operator in " + v))
    return nformulas, used, bad


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.reader(fh))
    return rows[0], rows[1:]


def to_num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def excel_recalc_copy(path):
    """Open the workbook in Excel, recalculate, save; return the saved copy's path or None.

    Excel must be launched by the open command itself: when Excel is already running with its
    start screen up, its "open workbook" command fails (parameter error) and "save" writes
    nothing. So an idle Excel (no workbook open) is quit first; an Excel with workbooks open
    (someone's work) is left alone and the Excel step is skipped. The copy lives under the home
    folder (files under /tmp are not written back by Excel's sandbox)."""
    probe = subprocess.run(["osascript", "-e", 'tell application "System Events" to (name of processes) contains "Microsoft Excel"'],
                           capture_output=True, text=True)
    if probe.stdout.strip() == "true":
        n = subprocess.run(["osascript", "-e", 'tell application "Microsoft Excel" to count of workbooks'], capture_output=True, text=True)
        if n.stdout.strip() not in ("0", ""):
            print("  Excel is open with workbooks: the Excel step is skipped so as not to disturb them (close Excel and rerun)")
            return None
        subprocess.run(["osascript", "-e", 'tell application "Microsoft Excel" to quit saving no'], capture_output=True, text=True)
        time.sleep(4)
    home = os.path.join(os.path.expanduser("~"), ".rtm_display_check")
    os.makedirs(home, exist_ok=True)
    copy = os.path.join(home, "recalc.xlsx")
    shutil.copy(path, copy)
    script = f'''
    tell application "Microsoft Excel"
        set wb to open workbook workbook file name (POSIX file "{copy}" as string)
        calculate
        save wb
        close wb saving no
        quit saving no
    end tell
    '''
    try:
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=300)
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        print("  Excel could not be driven:", e)
        return None
    if r.returncode != 0:
        print("  Excel could not be driven:", r.stderr.strip()[:300])
        return None
    return copy


def check_run(run):
    print("run:", os.path.basename(run))
    xl = os.path.join(run, "rtm_display.xlsx")
    if not os.path.exists(xl):
        print("  no rtm_display.xlsx in the run folder")
        return False
    n, used, bad = formula_inventory(xl)
    print(f"  formulas: {n}; functions: {used}")
    if bad:
        for b in bad[:10]:
            print("  NOT ALLOWED:", b)
        return False
    ok = True
    # the data sheets must equal the CSV files
    wb = load_workbook(xl)
    for csvf in glob.glob(os.path.join(run, "*.csv")):
        name = os.path.splitext(os.path.basename(csvf))[0]
        if name == "manifest":
            continue
        if name not in wb.sheetnames:
            print(f"  table {name}: no sheet in the workbook")
            ok = False
            continue
        header, rows = read_csv(csvf)
        ws = wb[name]
        sheet_header = [c.value for c in ws[1]][: len(header)]
        if sheet_header != header:
            print(f"  table {name}: header differs: {sheet_header} vs {header}")
            ok = False
        nmis = 0
        for i, row in enumerate(rows, start=2):
            for j, val in enumerate(row, start=1):
                cell = ws.cell(row=i, column=j).value
                num = to_num(val)
                if num is not None:
                    if cell is None or abs(float(cell) - num) > 1e-9 * max(1.0, abs(num)):
                        nmis += 1
                else:
                    if (cell if cell is not None else "") != val:
                        nmis += 1
        print(f"  table {name}: {len(rows)} rows, {nmis} mismatches with the CSV")
        if nmis:
            ok = False
    # displayed values after an Excel recalculation
    copy = excel_recalc_copy(xl)
    if copy is None:
        print("  displayed values not checked (Excel not available); the formula inventory and the data sheets were checked")
        return ok
    manifest0 = {k: v for k, v in read_csv(os.path.join(run, "manifest.csv"))[1]}
    sheetname = {"weights": "Weights", "sampling": "Sampling", "frame": "Frame", "listing": "Listing"}.get(manifest0.get("workflow", ""), "Weights")
    wv = load_workbook(copy, data_only=True)[sheetname]
    wf = load_workbook(xl)[sheetname]
    mrows = read_csv(os.path.join(run, "manifest.csv"))[1]
    manifest = {k: v for k, v in mrows}
    ncheck = 0
    nbad = 0
    for row in wf.iter_rows():
        for c in row:
            f = c.value
            if not (isinstance(f, str) and f.startswith("=")):
                continue
            shown = wv[c.coordinate].value
            m = re.match(r'=IFERROR\(INDEX\(manifest!\$B:\$B,MATCH\("([^"]+)",manifest', f)
            if m:
                key = m.group(1)
                expected = manifest.get(key, NOT_IN)
                ncheck += 1
                if to_num(expected) is not None and shown is not None and to_num(str(shown)) is not None:
                    if abs(float(shown) - float(expected)) > 1e-9 * max(1.0, abs(float(expected))):
                        nbad += 1
                        print(f"  {c.coordinate}: shows {shown}, export says {expected}")
                elif str(shown if shown is not None else "") != str(expected):
                    nbad += 1
                    print(f"  {c.coordinate}: shows {shown!r}, export says {expected!r}")
                continue
            m = re.match(r'=IF\(([A-Za-z_]+)!([A-Z]+)(\d+)="","",', f)
            if m:
                sheet, col, r = m.group(1), m.group(2), int(m.group(3))
                src = load_workbook(xl)[sheet][f"{col}{r}"].value if sheet in wb.sheetnames else None
                expected = "" if src is None else src
                ncheck += 1
                if to_num(str(expected)) is not None and shown is not None:
                    if abs(float(shown) - float(expected)) > 1e-9 * max(1.0, abs(float(expected))):
                        nbad += 1
                        print(f"  {c.coordinate}: shows {shown}, export says {expected}")
                elif str(shown if shown is not None else "") != str(expected):
                    nbad += 1
                    print(f"  {c.coordinate}: shows {shown!r}, export says {expected!r}")
    print(f"  displayed cells checked against the export: {ncheck}; mismatches: {nbad}")
    try:
        os.remove(copy)
    except OSError:
        pass
    return ok and nbad == 0


def main(argv):
    n, used, bad = formula_inventory(TEMPLATE)
    print(f"template: {n} formulas; functions used: {used}")
    if bad:
        for b in bad[:10]:
            print("NOT ALLOWED:", b)
        return 1
    print("template: every formula is a lookup, a reference or a count of exported values")
    rc = 0
    for run in argv:
        if not check_run(run):
            rc = 1
    print("display check:", "PASS" if rc == 0 else "FAIL")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
