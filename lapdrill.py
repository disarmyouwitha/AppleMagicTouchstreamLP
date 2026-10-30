#!/usr/bin/env python3
"""lapdrill - tiny steno drills for the terminal (Windows).

  python lapdrill.py            word-flash drill (looks like a build log)
  python lapdrill.py fall       falling-words game
  python lapdrill.py commit     type phrases as fake git commits
  python lapdrill.py deploy     progress-bar race (--goal N words)
  python lapdrill.py --words 300  use the 300 most common words you can stroke

Words come from your Plover Lapwing dictionary, so every word on screen is
one you can actually stroke. Misses are remembered and shown more often.
Esc quits. Tab shows the stroke hint in flash mode.
"""
import argparse
import json
import msvcrt
import os
import random
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATS = HERE / "lapdrill_stats.json"
DICT = Path(os.environ.get("LOCALAPPDATA", "")) / "plover" / "plover" / "lapwing-base.json"

# roughly by frequency; filtered against your dictionary at load time
COMMON = """the of and to a in is it you that he was for on are with as I his they be at one have this
from or had by hot but some what there we can out other were all your when up use word how said an each
she which do their time if will way about many then them would write like so these her long make thing
see him two has look more day could go come did my sound no most number who over know water than call
first people may down side been now find any new work part take get place made live where after back
little only round man year came show every good me give our under name very through just form much great
think say help low line before turn cause same mean differ move right boy old too does tell sentence set
three want air well also play small end put home read hand port large spell add even land here must big
high such follow act why ask men change went light kind off need house picture try us again animal point
mother world near build self earth father head stand own page should country found answer school grow study
still learn plant cover food sun four between state keep eye never last let thought city tree cross farm
hard start might story saw far sea draw left late run don't while press close night real life few north
open seem together next white children begin got walk example ease paper group always music those both
mark often letter until mile river car feet care second book carry took science eat room friend began idea
fish mountain stop once base hear horse cut sure watch color face wood main enough plain girl usual young
ready above ever red list though feel talk bird soon body dog family direct pose leave song measure door
product black short numeral class wind question happen complete ship area half rock order fire south
problem piece told knew pass since top whole king space heard best hour better true during hundred five
remember step early hold west ground interest reach fast verb sing listen six table travel less morning
ten simple several vowel toward war lay against pattern slow center love person money serve appear road
map rain rule govern pull cold notice voice unit power town fine certain fly fall lead cry dark machine
note wait plan figure star box noun field rest correct able pound done beauty drive stood contain front
teach week final gave green oh quick develop ocean warm free minute strong special mind behind clear tail
produce fact street inch multiply nothing course stay wheel full force blue object decide surface deep
moon island foot system busy test record boat common gold possible plane stead dry wonder laugh thousand
ago ran check game shape equate hot miss brought heat snow tire bring yes distant fill east paint language
among cat""".split()


def load_dictionary():
    """word -> best stroke string (fewest strokes, then shortest)."""
    if not DICT.exists():
        sys.exit(f"Can't find {DICT}\nEdit DICT at the top of lapdrill.py.")
    raw = json.loads(DICT.read_text(encoding="utf-8"))
    best = {}
    for stroke, word in raw.items():
        if not word.isalpha() or not word.islower():
            continue
        key = (stroke.count("/"), len(stroke))
        if word not in best or key < best[word][0]:
            best[word] = (key, stroke)
    return {w: s for w, (_, s) in best.items()}


def build_pool(strokes, n):
    pool, seen = [], set()
    for w in COMMON:
        if w in strokes and w not in seen and strokes[w].count("/") <= 1:
            pool.append(w)
            seen.add(w)
        if len(pool) >= n:
            break
    return pool


def load_stats():
    try:
        return json.loads(STATS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_stats(stats):
    try:
        STATS.write_text(json.dumps(stats, indent=1), encoding="utf-8")
    except OSError:
        pass


def pick(pool, stats, avoid=()):
    """Weighted random choice: missed words come up more often."""
    weights = []
    for w in pool:
        s = stats.get(w, {})
        wt = 1 + 3 * s.get("miss", 0) - 0.1 * min(s.get("hit", 0), 5)
        weights.append(0 if w in avoid else max(wt, 0.3))
    if not any(weights):
        weights = [1] * len(pool)
    return random.choices(pool, weights)[0]


def bump(stats, word, key, ms=None):
    s = stats.setdefault(word, {"hit": 0, "miss": 0})
    s[key] += 1
    if ms is not None and (s.get("best_ms") is None or ms < s["best_ms"]):
        s["best_ms"] = ms


# ---------------------------------------------------------------- terminal
def enable_vt():
    try:
        import ctypes
        k = ctypes.windll.kernel32
        h = k.GetStdHandle(-11)
        mode = ctypes.c_uint()
        k.GetConsoleMode(h, ctypes.byref(mode))
        k.SetConsoleMode(h, mode.value | 0x0004)
    except Exception:
        os.system("")


def out(s):
    sys.stdout.write(s)
    sys.stdout.flush()


DIM, GRN, RED, YEL, CYN, RST = "\x1b[90m", "\x1b[32m", "\x1b[31m", "\x1b[33m", "\x1b[36m", "\x1b[0m"


def read_burst():
    """Drain every pending key. Plover sends a stroke as one quick burst."""
    keys = []
    while msvcrt.kbhit():
        ch = msvcrt.getwch()
        if ch in ("\x00", "\xe0"):
            msvcrt.getwch()  # swallow arrow/function keys
            continue
        keys.append(ch)
    return keys


class Buffer:
    def __init__(self):
        self.text = ""

    def feed(self, keys):
        """Returns 'quit', 'tab', or None. Spaces/Enter are ignored so it
        doesn't matter where Plover puts its spaces."""
        sig = None
        for ch in keys:
            if ch == "\x1b" or ch == "\x03":
                return "quit"
            if ch == "\t":
                sig = "tab"
            elif ch == "\b" or ch == "\x7f":
                self.text = self.text[:-1]
            elif ch.isprintable() and ch != " ":
                self.text += ch.lower()
        return sig


# ---------------------------------------------------------------- flash
def flash(pool, strokes, stats):
    hits = misses = 0
    times = []
    word = pick(pool, stats)
    buf, shown, hinted = Buffer(), time.time(), False
    out(f"{DIM}lapdrill {datetime.now():%H:%M:%S}  pool={len(pool)}  esc=quit tab=hint{RST}\n")

    def prompt():
        hint = f"  {DIM}{strokes[word]}{RST}" if hinted else ""
        out(f"\r\x1b[2K> {word}{hint}")

    prompt()
    try:
        while True:
            time.sleep(0.01)
            keys = read_burst()
            if not hinted and time.time() - shown > 6:
                hinted = True
                prompt()
            if not keys:
                continue
            sig = buf.feed(keys)
            if sig == "quit":
                break
            if sig == "tab" and not hinted:
                hinted = True
                prompt()
                continue
            if not buf.text:
                continue
            if buf.text == word:
                ms = int((time.time() - shown) * 1000)
                hits += 1
                times.append(ms)
                bump(stats, word, "hit", ms)
                out(f"\r\x1b[2K{DIM}[{datetime.now():%H:%M:%S}] {GRN}OK  {RST}{DIM} {word:<12}{ms:>5}ms{RST}\n")
            elif not word.startswith(buf.text):
                misses += 1
                bump(stats, word, "miss")
                out(f"\r\x1b[2K{DIM}[{datetime.now():%H:%M:%S}] {RED}FAIL{RST}{DIM} {word:<12}"
                    f"got '{buf.text}'  stroke: {YEL}{strokes[word]}{RST}\n")
            else:
                continue  # still fingerspelling a prefix
            buf.text = ""
            word = pick(pool, stats, avoid=(word,))
            shown, hinted = time.time(), False
            prompt()
    except KeyboardInterrupt:
        pass
    out("\r\x1b[2K")
    total = hits + misses
    if total:
        avg = sum(times) // len(times) if times else 0
        out(f"{DIM}session: {hits}/{total} correct ({100 * hits // total}%), avg {avg}ms{RST}\n")


# ---------------------------------------------------------------- fall
def fall(pool, strokes, stats):
    lives, score, combo = 5, 0, 0
    words = []  # [text, col, row(float)]
    buf = Buffer()
    last, spawn_at, t0 = time.time(), 0.0, time.time()
    out("\x1b[?1049h\x1b[?25l")
    try:
        while lives > 0:
            now = time.time()
            dt, last = now - last, now
            cols, rows = shutil.get_terminal_size((80, 24))
            level = score // 10
            speed = 0.8 + 0.12 * level
            if now >= spawn_at:
                w = pick(pool, stats, avoid={x[0] for x in words})
                words.append([w, random.randint(1, max(1, cols - len(w) - 2)), 0.0])
                spawn_at = now + max(0.9, 2.6 - 0.12 * level)
            for w in words:
                w[2] += speed * dt
            keys = read_burst()
            if keys:
                if buf.feed(keys) == "quit":
                    break
                hit = next((w for w in sorted(words, key=lambda x: -x[2]) if w[0] == buf.text), None)
                if hit:
                    words.remove(hit)
                    score += 1
                    combo += 1
                    bump(stats, hit[0], "hit")
                    buf.text = ""
                elif buf.text and not any(w[0].startswith(buf.text) for w in words):
                    combo = 0
                    buf.text = ""
            for w in [w for w in words if w[2] >= rows - 3]:
                words.remove(w)
                lives -= 1
                combo = 0
                bump(stats, w[0], "miss")
            frame = [f"\x1b[H\x1b[2J{DIM}score {RST}{score}{DIM}  lives {RST}{'♥' * lives}"
                     f"{DIM}  combo {RST}{combo}{DIM}  lvl {level}  esc=quit{RST}"]
            for text, col, row in words:
                n = len(buf.text)
                if buf.text and text.startswith(buf.text):
                    label = f"{GRN}{text[:n]}{RST}{text[n:]}"
                else:
                    label = text
                frame.append(f"\x1b[{int(row) + 2};{col}H{label}")
            frame.append(f"\x1b[{rows - 1};1H{DIM}{'-' * (cols - 1)}{RST}")
            frame.append(f"\x1b[{rows};1H{CYN}> {RST}{buf.text}")
            out("".join(frame))
            time.sleep(0.04)
    except KeyboardInterrupt:
        pass
    high = stats.get("_high_fall", 0)
    new = score > high
    if new:
        stats["_high_fall"] = score
    out("\x1b[?25h\x1b[?1049l")
    out(f"score {score}  ({time.time() - t0:.0f}s)  "
        f"{'NEW HIGH SCORE!' if new else f'high {high}'}\n")


# ---------------------------------------------------------------- commit
def commit(pool, strokes, stats):
    """Type short phrases as a fake git commit. One line, redrawn in place."""
    buf = Buffer()
    done_phrases = hits = misses = 0
    times = []

    def new_phrase():
        ws = []
        for _ in range(random.randint(4, 6)):
            ws.append(pick(pool, stats, avoid=set(ws[-1:])))
        return ws

    def draw(ws, n_done, flag=""):
        cols = shutil.get_terminal_size((80, 24)).columns
        tail = f"{DIM}{flag}{RST}"
        good = " ".join(ws[:n_done])
        rest = " ".join(ws[n_done:])
        sep = " " if good and rest else ""
        line = f'{DIM}${RST} git commit -m "{GRN}{good}{RST}{sep}{rest}"  {tail}'
        out("\r\x1b[2K" + line[:cols * 3])

    out(f"{DIM}lapdrill commit  pool={len(pool)}  esc=quit{RST}\n")
    ws = new_phrase()
    n_done, started, flag = 0, time.time(), ""
    draw(ws, n_done)
    try:
        while True:
            time.sleep(0.01)
            keys = read_burst()
            if not keys:
                continue
            if buf.feed(keys) == "quit":
                break
            target = "".join(ws)
            if target.startswith(buf.text):
                flag = ""
                covered, k = 0, 0
                while k < len(ws) and covered + len(ws[k]) <= len(buf.text):
                    covered += len(ws[k])
                    k += 1
                while n_done < k:
                    bump(stats, ws[n_done], "hit")
                    hits += 1
                    n_done += 1
            else:
                # rewind to the start of the current word
                buf.text = "".join(ws[:n_done])
                bump(stats, ws[n_done], "miss")
                misses += 1
                flag = f"x  {strokes[ws[n_done]]}"
            if n_done == len(ws):
                secs = time.time() - started
                times.append(len(ws) / secs * 60)
                done_phrases += 1
                out(f"\r\x1b[2K{DIM}[{datetime.now():%H:%M:%S}] {GRN}committed{RST}{DIM} "
                    f"{' '.join(ws)}  ({times[-1]:.0f} wpm){RST}\n")
                ws, n_done, buf.text = new_phrase(), 0, ""
                started, flag = time.time(), ""
            draw(ws, n_done, flag)
    except KeyboardInterrupt:
        pass
    out("\r\x1b[2K")
    if done_phrases:
        out(f"{DIM}session: {done_phrases} commits, avg {sum(times) / len(times):.0f} wpm, "
            f"{misses} misses{RST}\n")


# ---------------------------------------------------------------- deploy
def deploy(pool, strokes, stats, goal=40):
    """Progress-bar race: stroke `goal` words as fast as you can."""
    buf = Buffer()
    word = pick(pool, stats)
    n = misses = 0
    streak = best_streak = 0
    t0 = time.time()
    last_t = 0.0

    def draw(flag=""):
        el = time.time() - t0
        pct = n / goal
        filled = int(pct * 20)
        wpm = n / el * 60 if el > 1 and n else 0
        hint = f" {YEL}{strokes[word]}{RST}" if flag else ""
        out(f"\r\x1b[2K{DIM}Deploying{RST} [{GRN}{'#' * filled}{RST}{DIM}{'-' * (20 - filled)}{RST}] "
            f"{int(pct * 100):>3}% {DIM}{n}/{goal} {el:>4.0f}s {wpm:>3.0f}wpm x{streak}{RST}  > {word}{hint}")

    out(f"{DIM}lapdrill deploy  {goal} words  esc=quit{RST}\n")
    draw()
    try:
        while n < goal:
            time.sleep(0.01)
            keys = read_burst()
            now = time.time()
            if int(now - t0) != int(last_t - t0) and not keys:
                draw()  # tick the clock
            last_t = now
            if not keys:
                continue
            if buf.feed(keys) == "quit":
                break
            if not buf.text:
                continue
            if buf.text == word:
                n += 1
                streak += 1
                best_streak = max(best_streak, streak)
                bump(stats, word, "hit")
                buf.text = ""
                word = pick(pool, stats, avoid=(word,))
                draw()
            elif not word.startswith(buf.text):
                misses += 1
                streak = 0
                bump(stats, word, "miss")
                buf.text = ""
                draw(flag="x")
    except KeyboardInterrupt:
        pass
    el = time.time() - t0
    out("\r\x1b[2K")
    if n >= goal:
        best = stats.get("_best_deploy_%d" % goal)
        new = best is None or el < best
        if new:
            stats["_best_deploy_%d" % goal] = round(el, 1)
        out(f"{GRN}deploy succeeded{RST}{DIM} in {el:.1f}s, {goal / el * 60:.0f} wpm, {misses} misses, "
            f"best streak {best_streak}  "
            f"{'NEW BEST' if new else f'best {best}s'}{RST}\n")
    elif n:
        out(f"{DIM}deploy aborted at {n}/{goal}{RST}\n")


def main():
    ap = argparse.ArgumentParser(description="steno drills")
    ap.add_argument("mode", nargs="?", default="flash", choices=["flash", "fall", "commit", "deploy"])
    ap.add_argument("--goal", type=int, default=40, help="deploy: words to stroke")
    ap.add_argument("--words", type=int, default=100, help="pool size (most common first)")
    args = ap.parse_args()

    strokes = load_dictionary()
    pool = build_pool(strokes, args.words)
    if not pool:
        sys.exit("No words found in your dictionary.")
    stats = load_stats()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    enable_vt()
    try:
        if args.mode == "deploy":
            deploy(pool, strokes, stats, args.goal)
        else:
            {"flash": flash, "fall": fall, "commit": commit}[args.mode](pool, strokes, stats)
    finally:
        out("\x1b[?25h")
        save_stats(stats)


if __name__ == "__main__":
    main()
