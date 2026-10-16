#!/usr/bin/env bash
#
# scripts/status-render on what scripts/status-collect measured in the
# fixture world, with 30 days of history, and on a collect that read
# nothing.
#
# Each site must hold the page, the data, every chart in both widths and
# every badge. Every SVG must parse as XML, with a title and a dark style.
# No text may say NaN, None, null, undefined or inf. A port whose values did
# not read must say unknown in its badges. The page must:
#   - reference every chart and badge
#   - reference no file that does not exist
#   - have one inline script and no other
#   - show each time as UTC text in a <time> element
#
# Then, on changed records:
#   - a per port parity with a rolling tag that did not read draws no bar
#   - the GHCR tile changes when a port has no image
#   - the build table counts the 30 days of the build chart, not the whole
#     history
#   - the mirror word takes its lag from the targets that are not current
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib/harness.sh
. "$REPO_ROOT/tests/lib/harness.sh"

FIX="$REPO_ROOT/tests/fixtures/status"
RENDER="$REPO_ROOT/scripts/status-render"
work="$(work_dir)"
trap 'rm -rf "$work"' EXIT

expect() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: $2" "got:      $3" "reproduce: $4"
  fi
}

if ! need_tool jq python3 awk sha256sum timeout; then
  summary
  exit $?
fi

export PORTS_DIR="$FIX/ports"
NOW="$(jq -r '.now | fromdateiso8601' "$FIX/world.json")"
# The chart names the README and the page link to
CHARTS='["freshness","size","packages","coverage","build","history-age","history-size","history-build"]'
# The fixture port whose image GHCR does not serve
UNKNOWN=ppc64
RP="python3 -I scripts/status-render IN SITE"

# world NAME [ENV=VALUE ...]: the fixture world, collected into $work/NAME/in
world() {
  local w="$work/$1"
  shift
  bash "$FIX/make-world" "$w" > "$w.make" 2>&1
  env STATUS_FIXTURE_DIR="$w/fx" STATUS_NOW="$NOW" GITHUB_REPOSITORY=test-owner/docker-archlinux \
    GHCR_IMAGE=ghcr.io/test-owner/archlinux HUB_IMAGE=docker.io/test/archlinux "$@" \
    "$REPO_ROOT/scripts/status-collect" "$w/in" > "$w.collect" 2>&1
}

cat > "$work/check.py" << 'EOF'
import json, os, re, sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

site, spec = sys.argv[1], json.loads(sys.argv[2])
BAD = re.compile(r"\b(NaN|nan|None|null|undefined|Infinity|inf)\b")


def say(ok, desc, detail=""):
    print("%s\t%s\t%s" % ("PASS" if ok else "FAIL", desc, detail.replace("\n", " ")[:600]))


def svg_text(path):
    root = ET.parse(path).getroot()
    return " ".join("".join(e.itertext()) for e in root.iter() if e.tag.endswith("}text"))


missing = [f for f in spec["files"] if not os.path.isfile(os.path.join(site, f))]
say(not missing, "every page, chart, badge, data and evidence file is written", " ".join(missing))

bad, sizes, texts = [], [], {}
for d in ("charts", "badges"):
    for dirpath, _, names in os.walk(os.path.join(site, d)):
        for f in sorted(names):
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, site).replace(os.sep, "/")
            try:
                root = ET.parse(p).getroot()
            except ET.ParseError as e:
                bad.append("%s: %s" % (rel, e))
                continue
            if not root.tag.endswith("}svg"):
                bad.append("%s: the root is %s" % (rel, root.tag))
            if not any(e.tag.endswith("}title") and "".join(e.itertext()).strip() for e in root):
                bad.append("%s: no title" % rel)
            style = " ".join("".join(e.itertext()) for e in root.iter() if e.tag.endswith("}style"))
            if "prefers-color-scheme:dark" not in style.replace(" ", ""):
                bad.append("%s: no dark style" % rel)
            if rel.startswith("charts/"):
                sizes.append((rel, root.get("width")))
            texts[rel] = svg_text(p)
say(not bad and len(texts) == spec["svgs"],
    "all %d SVG files parse as XML, each with a title and a dark style" % spec["svgs"],
    "found %d; %s" % (len(texts), "; ".join(bad)))
wrong = [(r, w) for r, w in sizes if w != ("420" if r.startswith("charts/narrow/") else "760")]
say(not wrong, "each chart is 760 wide, and 420 wide under charts/narrow", str(wrong))

seen = sorted("%s: %s" % (r, m.group(0)) for r, t in texts.items() for m in [BAD.search(t)] if m)
say(not seen, "no chart or badge says NaN, None, null, undefined or inf", "; ".join(seen))

cls_bad = []
for rel in texts:
    if not rel.startswith("charts/"):
        continue
    for e in ET.parse(os.path.join(site, rel)).getroot().iter():
        cls = (e.get("class") or "").split()
        if "line" in cls:
            cls_bad += ["%s: %r" % (rel, e.get("class")) for c in cls
                        if c not in ("line", "ref") and not re.fullmatch(r"l(?:x[0-9]+|[0-9]+)", c)]
        cls_bad += ["%s: %r" % (rel, e.get("class")) for c in cls if re.match(r"^[sl]-[0-9]", c)]
say(not cls_bad, "every chart mark names a defined slot class", "; ".join(sorted(set(cls_bad))))

for name in spec["arch_charts"]:
    t = texts.get("charts/%s.svg" % name, "")
    lost = [a for a in spec["arches"] if a not in t]
    say(not lost, "chart %s names every port" % name, "not found: %s" % lost)

legend = {}
src = open(os.path.join(site, "charts", "size.svg"), encoding="utf-8").read()
for m in re.finditer(r'<rect[^>]*class="(s\d+|sx\d+)"[^>]*/>\s*<text[^>]*class="lg">([a-z0-9_]+)</text>', src):
    legend[m.group(2)] = m.group(1)
cls = [legend.get(a) for a in spec["arches"]]
say(None not in cls and len(set(cls)) == len(cls) and "s0" not in cls,
    "each port has a colour swatch of its own, and none is the grey", str(legend))

for name in spec["unknown_badges"]:
    t = texts.get("badges/%s.svg" % name, "")
    say("unknown" in t.split(), "badge %s says unknown" % name, "text: %s" % t)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs, self.times, self.scripts, self.handlers, self.text = set(), [], [], [], []
        self.time = self.script = None
        self.style = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        for k, v in attrs:
            if k in ("src", "href", "srcset") and v and "://" not in v and not v.startswith("#"):
                self.refs.add(v)
            if k.startswith("on") or (k in ("href", "src") and (v or "").lower().startswith("javascript:")):
                self.handlers.append("%s=%s" % (k, v))
        if tag == "time":
            self.time = [a.get("datetime"), ""]
        elif tag == "script":
            self.script = [a, ""]
        elif tag == "style":
            self.style = True

    def handle_endtag(self, tag):
        if tag == "time" and self.time is not None:
            self.times.append(tuple(self.time))
            self.time = None
        elif tag == "script" and self.script is not None:
            self.scripts.append(tuple(self.script))
            self.script = None
        elif tag == "style":
            self.style = False

    def handle_data(self, data):
        if self.script is not None:
            self.script[1] += data
        elif not self.style:
            self.text.append(data)
            if self.time is not None:
                self.time[1] += data


pg = Page()
pg.feed(open(os.path.join(site, "index.html"), encoding="utf-8").read())
text = " ".join(" ".join(pg.text).split())
m = BAD.search(text)
say(not m, "the page says no NaN, None, null, undefined or inf", m.group(0) if m else "")
want = (["charts/%s.svg" % c for c in spec["charts"]] + ["charts/narrow/%s.svg" % c for c in spec["charts"]]
        + ["badges/%s.svg" % b for b in spec["badges"]])
lost = [w for w in want if w not in pg.refs]
say(not lost, "index.html references every chart, in both widths, and every badge", " ".join(lost))
broken = sorted(x for x in pg.refs if not os.path.isfile(os.path.join(site, x)))
say(not broken, "every file index.html references exists", " ".join(broken))
srcs = [a.get("src") for a, _ in pg.scripts if "src" in a]
say(len(pg.scripts) == 1 and not srcs, "index.html has one script, inline, and no other",
    "%d script(s), src: %s" % (len(pg.scripts), srcs))
say(not pg.handlers, "index.html has no event handler attribute and no javascript: URL", " ".join(pg.handlers))
TIME = re.compile(r"^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}):\d{2}Z$")
badt = []
for dt, t in pg.times:
    mt = TIME.match(dt or "")
    if not mt or t != "%s %s UTC" % (mt.group(1), mt.group(2)):
        badt.append("%s shows %r" % (dt, t))
say(pg.times and not badt, "every <time> has a datetime in UTC and shows it as UTC text",
    "%d <time>; %s" % (len(pg.times), "; ".join(badt)))
with open(os.path.join(site, "history.json"), encoding="utf-8") as f:
    h = json.load(f)
say(isinstance(h, list) and len(h) == spec["history"], "history.json holds %d line(s)" % spec["history"],
    "found %s" % (len(h) if isinstance(h, list) else type(h).__name__))
with open(os.path.join(site, "status.json"), encoding="utf-8") as f:
    st = json.load(f)
say(st.get("schema") == 1 and [p["arch"] for p in st["ports"]] == spec["arches"],
    "status.json on the site is the collected record", str(st.get("schema")))
EOF

# spec STATUS_JSON HISTORY_LINES UNKNOWN_BADGES_JSON: what check.py expects
spec() {
  jq -c --argjson charts "$CHARTS" --argjson history "$2" --argjson unknown "$3" '
    [.ports[].arch] as $a
    | ([.ports[] | select(.evidence.packages != null) | .arch]) as $ev
    | ($a + ["all", "latest", "registries", "build"] + ($a | map("size-" + .)) + ($a | map("packages-" + .))) as $badges
    | {charts: $charts, arches: $a, history: $history, badges: $badges, unknown_badges: $unknown,
       arch_charts: ["freshness", "size", "packages", "coverage", "build", "history-build"],
       svgs: (($charts | length) * 2 + ($badges | length)),
       files: (["index.html", "status.json", "history.json", "history.jsonl"]
               + ($charts | map("charts/\(.).svg")) + ($charts | map("charts/narrow/\(.).svg"))
               + ($badges | map("badges/\(.).svg"))
               + ($ev | map("evidence/\(.).json", "evidence/\(.).digest")))}' "$1"
}

# render IN SITE SPEC: status-render, then the verdicts of check.py as TAP
render() {
  local rc=0 verdict desc detail
  python3 -I "$RENDER" "$1" "$2" > "$2.out" 2> "$2.err" || rc=$?
  expect "status-render $(basename "$2") exits 0" 0 "$rc" "$RP; $(awk 'NR == 1' "$2.err")"
  [ "$rc" -eq 0 ] || return 0
  rc=0
  python3 -I "$work/check.py" "$2" "$3" > "$2.check" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "the site checks of $(basename "$2") run" "$(awk 'NR <= 20' "$2.check")" "reproduce: python3 -I check.py SITE SPEC"
    return 0
  fi
  while IFS=$'\t' read -r verdict desc detail; do
    if [ "$verdict" = PASS ]; then
      ok "$(basename "$2"): $desc"
    else
      fail "$(basename "$2"): $desc" "$detail" "reproduce: $RP"
    fi
  done < "$2.check"
}

#---------------------------------------------------------------------------#
# The fixture world, with 30 days of hourly history before it
#---------------------------------------------------------------------------#
rc=0
world w1 || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "the fixture world is collected" "$(awk 'END { print }' "$work/w1.collect")" \
    "reproduce: bash tests/fixtures/status/make-world W; STATUS_FIXTURE_DIR=W/fx ... scripts/status-collect W/in"
  summary
  exit $?
fi
in="$work/w1/in"
# One line per hour for 30 days: each port built at 05:30 each day; a port
# whose image is 41 days old in the fixture grows older each hour.
jq -c --argjson end "$NOW" '
  (.ports | map(.arch)) as $a
  | range(720; 0; -1) as $i | ($end - $i * 3600) as $t
  | {t: ($t | todate), p: 1, dr: 0,
     x: ([range(0; $a | length) as $k
          | {key: $a[$k], value: {a: (if $k % 4 == 0 and $k > 0 then ($t - 1788599700) else (($t - 19800) % 86400 + 600) end),
                                  s: (80000000 + $k * 4000000 + (720 - $i) * 2000), i: null, n: 3, l: 0,
                                  b: [((($t - 19800) / 86400 | floor) * 10 + $k),
                                      (if $k == 4 then "failure" else "success" end),
                                      ((($t - 19800) / 86400 | floor) * 86400 + 19860), 900]}}] | from_entries)}' \
  "$in/status.json" > "$work/hours.jsonl"
cat "$work/hours.jsonl" "$in/history.jsonl" > "$in/history.new"
mv "$in/history.new" "$in/history.jsonl"
lines="$(awk 'END { print NR }' "$in/history.jsonl")"
render "$in" "$work/site1" "$(spec "$in/status.json" "$lines" \
  "$(jq -nc --arg u "$UNKNOWN" '[$u, "size-" + $u, "packages-" + $u]')")"

#---------------------------------------------------------------------------#
# A collect that read nothing: STATUS_BUDGET=4
#---------------------------------------------------------------------------#
world w2 STATUS_BUDGET=4
in2="$work/w2/in"
render "$in2" "$work/site2" "$(spec "$in2/status.json" "$(awk 'END { print NR }' "$in2/history.jsonl")" \
  "$(jq -c '[.ports[].arch | ., "size-" + .] + ["latest", "registries", "build"]' "$in2/status.json")")"

#---------------------------------------------------------------------------#
# Changed records, from the record of the fixture world
#---------------------------------------------------------------------------#
cat > "$work/check2.py" << 'EOF'
import importlib.machinery, importlib.util, json, sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser


def say(ok, desc, detail=""):
    print("%s\t%s\t%s" % ("PASS" if ok else "FAIL", desc, detail.replace("\n", " ")[:600]))


class Page(HTMLParser):
    """The tiles (key, sub-line) and the rows of the table of each figure."""
    def __init__(self):
        super().__init__()
        self.tiles, self.tables, self.div = [], {}, []
        self.in_fig, self.fig, self.row, self.cell = False, None, None, None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "div":
            self.div.append(a.get("class"))
            if a.get("class") == "tile":
                self.tiles.append({"k": "", "s": ""})
        elif tag == "figure":
            self.in_fig = True
        elif tag == "a" and self.in_fig and self.fig is None and (a.get("href") or "").startswith("charts/"):
            self.fig = a["href"][len("charts/"):-len(".svg")]
            self.tables[self.fig] = []
        elif tag == "tr" and self.fig is not None:
            self.row = []
        elif tag == "td" and self.row is not None:
            self.cell = ""

    def handle_endtag(self, tag):
        if tag == "div" and self.div:
            self.div.pop()
        elif tag == "figure":
            self.in_fig, self.fig = False, None
        elif tag == "td" and self.row is not None and self.cell is not None:
            self.row.append(self.cell.strip())
            self.cell = None
        elif tag == "tr" and self.row is not None:
            if self.row:
                self.tables[self.fig].append(self.row)
            self.row = None

    def handle_data(self, data):
        if self.cell is not None:
            self.cell += data
        if self.div and self.div[-1] in ("k", "s") and self.tiles and "tile" in self.div:
            self.tiles[-1][self.div[-1]] += data


def page(site):
    p = Page()
    p.feed(open(site + "/index.html", encoding="utf-8").read())
    return p


def rows_after_label(svg_path):
    """{label: the elements of the <g> after the label text of a bar row}"""
    out = {}
    for parent in ET.parse(svg_path).getroot().iter():
        kids = list(parent)
        for i, c in enumerate(kids[:-1]):
            if c.tag.endswith("}text") and c.get("class") == "lb" and kids[i + 1].tag.endswith("}g"):
                out[(c.text or "").strip()] = list(kids[i + 1])
    return out


def marks_per_row(svg_path):
    """{port: [the class of the mark of each day]}, from the cells of the build grid"""
    out = {}
    for parent in ET.parse(svg_path).getroot().iter():
        kids = list(parent)
        for i, c in enumerate(kids[:-1]):
            if c.tag.endswith("}rect") and c.get("class") == "cell":
                t = "".join(e.text or "" for e in c if e.tag.endswith("}title")).split()
                if t:
                    out.setdefault(t[0], []).append(kids[i + 1].get("class"))
    return out


mode = sys.argv[1]
if mode == "coverage":
    site, arch = sys.argv[2], sys.argv[3]
    kids = rows_after_label(site + "/charts/coverage.svg").get(arch)
    bars = [k.get("class") for k in kids or [] if k.tag.endswith("}path")]
    say(kids is not None and not bars, "a port parity whose same did not read draws no bar in the coverage chart",
        "the %s row draws %s" % (arch, bars if kids is not None else "no row"))
elif mode == "tile":
    a, b, absent = page(sys.argv[2]).tiles, page(sys.argv[3]).tiles, sys.argv[4]
    sa = a[0]["s"].strip() if a else ""
    sb = b[0]["s"].strip() if b else ""
    say(a and b and sa != sb and absent in sb.replace(",", " ").split(),
        "the sub-line of the first tile changes, and counts %s port(s), when a port has no image" % absent,
        "tile %r: every port published %r, one absent %r" % (a[0]["k"] if a else None, sa, sb))
elif mode == "grid":
    site = sys.argv[2]
    rows = page(site).tables.get("history-build", [])
    table = {r[0]: r[1] for r in rows if len(r) > 1}
    chart = {k: str(v.count("st-good")) for k, v in marks_per_row(site + "/charts/history-build.svg").items()}
    say(table and table == chart, "the build table counts the passed days that the 30 day build chart shows",
        "table %s, chart %s" % (json.dumps(table, sort_keys=True), json.dumps(chart, sort_keys=True)))
elif mode == "mirror":
    path = sys.argv[2]
    # ⛔ A load writes bytecode next to the script by default. A file under
    # scripts/__pycache__ then fails the tracked-file check of test 70.
    sys.dont_write_bytecode = True
    loader = importlib.machinery.SourceFileLoader("status_render", path)
    sr = importlib.util.module_from_spec(importlib.util.spec_from_loader("status_render", loader))
    loader.exec_module(sr)
    incomplete = {"mirror": {"current": False, "lag_seconds": 0, "targets": [
        {"current": True, "lag_seconds": 0, "ratio_files": 1},
        {"current": False, "lag_seconds": 0, "ratio_files": 0.99993}]}}
    lvl, word = sr.mirror_state(incomplete)
    say(lvl == "warning" and sr.fmt_age(0) not in word and sr.fmt_pct(0.99993) in word,
        "a target not current with lag 0 states no lag, and gives its share of files",
        "%s %r" % (lvl, word))
    mixed = {"mirror": {"current": False, "lag_seconds": 7200, "targets": [
        {"current": True, "lag_seconds": 7200, "ratio_files": 1},
        {"current": False, "lag_seconds": 1800, "ratio_files": 1}]}}
    lvl, word = sr.mirror_state(mixed)
    say(lvl == "warning" and sr.fmt_age(1800) in word and sr.fmt_age(7200) not in word,
        "the lag comes from the target that is not current, not from a current target",
        "%s %r" % (lvl, word))
EOF

# verdicts NAME FILE: the lines of check2.py as TAP
verdicts() {
  local verdict desc detail
  while IFS=$'\t' read -r verdict desc detail; do
    if [ "$verdict" = PASS ]; then
      ok "$1: $desc"
    else
      fail "$1: $desc" "$detail" "reproduce: $RP"
    fi
  done < "$2"
  [ -s "$2" ] || fail "$1: check2.py gives verdicts" "no verdict" "reproduce: python3 -I check2.py"
}

# variant NAME JQ [HISTORY]: a copy of the fixture record, changed by JQ,
# with HISTORY as its history, rendered into $work/site-NAME
variant() {
  local d="$work/in-$1" rc=0
  mkdir -p "$d"
  cp -R "$in/evidence" "$d/"
  cp "${3:-$in/history.jsonl}" "$d/history.jsonl"
  jq "$2" "$in/status.json" > "$d/status.json"
  python3 -I "$RENDER" "$d" "$work/site-$1" > "$work/site-$1.out" 2> "$work/site-$1.err" || rc=$?
  expect "status-render site-$1 exits 0" 0 "$rc" "$RP, with status.json | jq '$2'; $(awk 'NR == 1' "$work/site-$1.err")"
}

first_port="$(jq -r '.ports[0].arch' "$in/status.json" | tr -d '\r')"
variant parity "(.ports[0].parity) = {tags: 8, same: null, unknown: 1, ratio: null}"
python3 -I "$work/check2.py" coverage "$work/site-parity" "$first_port" > "$work/v-parity" 2>&1
verdicts site-parity "$work/v-parity"

variant all-published '.ports[].ghcr.state = "published"'
variant one-absent '.ports[].ghcr.state = "published" | .ports[-1].ghcr.state = "absent"'
python3 -I "$work/check2.py" tile "$work/site-all-published" "$work/site-one-absent" 1 > "$work/v-tile" 2>&1
verdicts site-one-absent "$work/v-tile"

# 46 days of passed builds of the first port, 31 to 76 days old, before
# the 30 days of hourly history
jq -c -n --argjson end "$NOW" --arg a "$first_port" '
  range(76; 30; -1) as $d | ($end - $d * 86400) as $t
  | {t: ($t | todate), p: 1, dr: 0, x: {($a): {a: 600, s: 80000000, i: null, n: 3, l: 0, b: [(900000 + $d), "success", $t, 900]}}}' \
  > "$work/old.jsonl"
cat "$work/old.jsonl" "$in/history.jsonl" > "$work/history-long.jsonl"
variant long-history '.' "$work/history-long.jsonl"
python3 -I "$work/check2.py" grid "$work/site-long-history" > "$work/v-grid" 2>&1
verdicts site-long-history "$work/v-grid"

pyc_before="$(find "$(dirname "$RENDER")" -name '*.pyc' | LC_ALL=C sort)"
python3 -I "$work/check2.py" mirror "$RENDER" > "$work/v-mirror" 2>&1
verdicts mirror_state "$work/v-mirror"
pyc_after="$(find "$(dirname "$RENDER")" -name '*.pyc' | LC_ALL=C sort)"
expect "the load of status-render as a module writes no bytecode into the tree" "$pyc_before" "$pyc_after" \
  "python3 -I check2.py mirror scripts/status-render; find scripts -name '*.pyc'"

#---------------------------------------------------------------------------#
# Refusals, and the start without -I
#---------------------------------------------------------------------------#
mkdir -p "$work/bad"
jq '.ports[0].arch = "latest"' "$in/status.json" > "$work/bad/status.json"
rc=0
python3 -I "$RENDER" "$work/bad" "$work/site-bad" > /dev/null 2> "$work/bad.err" || rc=$?
expect "a port named like a summary badge stops the render with exit 1" 1 "$rc" "$RP, with a port named latest"
rc=0
python3 -I "$RENDER" "$work/none" "$work/site-none" > /dev/null 2> "$work/none.err" || rc=$?
expect "no status.json stops the render with exit 1" 1 "$rc" "$RP, with IN empty"
jq '.schema = 2' "$in/status.json" > "$work/bad/status.json"
rc=0
python3 -I "$RENDER" "$work/bad" "$work/site-bad" > /dev/null 2> "$work/bad.err" || rc=$?
expect "a status.json of another schema stops the render with exit 1" 1 "$rc" "$RP, with schema 2"
rc=0
python3 -I "$RENDER" "$in" > /dev/null 2> "$work/usage.err" || rc=$?
expect "a call with one argument is a usage error, exit 2" 2 "$rc" "python3 -I scripts/status-render IN"
# Without -I, python3 puts the directory of the script first on sys.path.
# A json.py there stops the render, unless the renderer starts itself again
# with -I before it reads json.
mkdir -p "$work/shadow"
cp "$RENDER" "$work/shadow/status-render"
printf 'raise SystemExit(7)\n' > "$work/shadow/json.py"
rc=0
python3 "$work/shadow/status-render" "$in" "$work/site3" > /dev/null 2> "$work/site3.err" || rc=$?
expect "run without -I, the renderer starts itself with -I: a json.py beside it is not read" "0 present" \
  "$rc $([ -f "$work/site3/index.html" ] && echo present || echo absent)" \
  "cp scripts/status-render D/; echo 'raise SystemExit(7)' > D/json.py; python3 D/status-render IN SITE"

summary
