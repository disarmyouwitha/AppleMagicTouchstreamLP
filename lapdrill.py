#!/usr/bin/env python3
"""lapdrill - tiny steno drills for the terminal (Windows).

  python lapdrill.py            word-flash drill (looks like a build log)
  python lapdrill.py fall       falling-words game
  python lapdrill.py commit     type phrases as fake git commits
  python lapdrill.py deploy     progress-bar race (--goal N words)
  python lapdrill.py keyboard   StenoJig-style raw-steno keyboard drills
  python lapdrill.py keyboard 2 right hand, bottom row (numbered submenu)
  python lapdrill.py keyboard --drill vowels --length 100 --hints
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


# --------------------------------------------------------- keyboard drills
# Drill sets and introductory order follow Joshua Grams' StenoJig:
# https://joshuagrams.github.io/steno-jig/learn-keyboard.js
# Entries are (CLI name, display name, choice groups, introductory practice).
LEFT = tuple("STKPWHR")
RIGHT = tuple("-" + k for k in "FRPBLGTSDZ")
VOWELS = tuple("AOEU")
KEYBOARD_DRILLS = [
    ("left-bottom", "Left hand, bottom row", [tuple("SKWR")], True),
    ("right-bottom", "Right hand, bottom row", [("-S", "-G", "-B", "-R")], True),
    ("left-top", "Left hand, top row", [tuple("STPH")], True),
    ("right-top", "Right hand, top row", [("-F", "-P", "-L", "-T")], True),
    ("right-full-bottom", "Right hand, full bottom row", [("-Z", "-S", "-G", "-B", "-R")], True),
    ("right-full-top", "Right hand, full top row", [("-F", "-P", "-L", "-T", "-D")], True),
    ("vowels", "Vowels", [VOWELS], True),
    ("left", "Left hand", [LEFT], False),
    ("right", "Right hand", [RIGHT], False),
    ("all", "All keys", [LEFT + VOWELS + RIGHT], False),
    ("left-right", "Left + Right", [LEFT, RIGHT], False),
    ("left-vowel", "Left + Vowel", [LEFT, VOWELS], False),
    ("vowel-right", "Vowel + Right", [VOWELS, tuple("FRPBLGTSDZ")], False),
    ("left-vowel-right", "Left + Vowel + Right", [LEFT, VOWELS, tuple("FRPBLGTSDZ")], False),
    ("columns", "Columns: D, B, L, -N", [("D-", "B-", "L-", "-N")], True),
    ("rows-two", "Rows (2-key): F, M, Q, -M, -K", [("F-", "M-", "Q-", "-M", "-K")], True),
    ("rows", "Rows: N, Y, J, C, V", [("N-", "Y-", "J-", "C-", "V-")], True),
    ("other", "Other chords: G, X, Z, -J", [("G-", "X-", "Z-", "-J")], True),
]
PSEUDO_LEFT = dict(D="TK", B="PW", L="HR", F="TP", M="PH", Q="KW",
                   N="TPH", Y="KWR", J="SKWR", C="KR", V="SR",
                   G="TKPW", X="KP", Z="STKPW")
PSEUDO_RIGHT = dict(N="PB", M="PL", K="BG", J="PBLG")


def raw_stroke(prompt):
    """Convert the pseudo letters used by the lessons to raw steno notation."""
    if prompt.endswith("-"):
        return PSEUDO_LEFT.get(prompt[:-1], prompt[:-1])
    if prompt.startswith("-"):
        return "-" + PSEUDO_RIGHT.get(prompt[1:], prompt[1:])
    return prompt


def keyboard_sequence(drill, length):
    _, _, groups, intro = drill
    sequence = []
    if intro:
        chords = list(groups[0])
        shuffled = random.sample(chords, len(chords))
        sequence = chords * 2 + chords[::-1] * 2
        sequence += [chord for chord in shuffled for _ in range(3)]
    while len(sequence) < length:
        sequence.append("".join(random.choice(group) for group in groups))
    return sequence[:length]


def resolve_keyboard_drill(choice):
    if choice.isdigit() and 1 <= int(choice) <= len(KEYBOARD_DRILLS):
        return KEYBOARD_DRILLS[int(choice) - 1]
    match = next((d for d in KEYBOARD_DRILLS if d[0] == choice), None)
    if match:
        return match
    raise ValueError(f"Unknown keyboard drill {choice!r}; choose 1-{len(KEYBOARD_DRILLS)} or a name from --list-drills.")


def select_keyboard_drill(name):
    if name:
        return resolve_keyboard_drill(name)
    out("Keyboard drills (StenoJig):\n")
    for i, (_, title, _, _) in enumerate(KEYBOARD_DRILLS, 1):
        out(f"  {i:2}. {title}\n")
    while True:
        try:
            choice = input("Drill [1], or q to quit: ").strip()
        except (EOFError, KeyboardInterrupt):
            return None
        if choice.lower() == "q":
            return None
        if not choice:
            return KEYBOARD_DRILLS[0]
        try:
            return resolve_keyboard_drill(choice)
        except ValueError:
            out("Choose a listed number or CLI name.\n")


def keyboard_line(sequence, index, misses, hinted, width, retry=False, pace=""):
    """One width-bounded command-style row; only the current chord is bright."""
    width = max(1, width - 1)  # Leave the terminal's last column unused.
    active = f"[{sequence[index]}]"
    prefix = '$ drill "'
    status = f'" {index}/{len(sequence)}'
    if misses:
        status += f" x{misses}"
    if retry:
        status += " retry"
    if hinted:
        status += f" raw={raw_stroke(sequence[index])}"
    if pace:
        status += f" {pace}"
    # Keep the active chord visible even in a very narrow window.
    if len(prefix) + len(active) + 1 > width:
        prefix = ""
    status = status[:max(0, width - len(prefix) - len(active))]
    budget = width - len(prefix) - len(status)
    slot_width = max(len(prompt) + 3 for prompt in sequence)
    slots = max(1, budget // slot_width)
    start = index // slots * slots
    tokens = []
    used = 0
    for i in range(start, min(start + slots, len(sequence))):
        token = f"[{sequence[i]}]" if i == index else sequence[i]
        used += len(token) + (1 if tokens else 0)
        if used > budget:
            break
        tokens.append(f"{RST}{token}{DIM}" if i == index else token)
    if not tokens:
        tokens = [f"{RST}{active[:budget]}{DIM}"]
    return f"\r\x1b[2K{DIM}{prefix}{' '.join(tokens)}{status}{RST}"


def keyboard(drill, stats, length=100, hints=False, speed=0):
    """Raw strokes are delimited by whitespace or 80 ms of input silence.

    Waiting for silence lets a Plover output burst span multiple polls, and
    prevents accepting a correct prefix of a wrong, longer chord.
    """
    sequence = keyboard_sequence(drill, length)
    index = misses = 0
    buf = ""
    last_input = 0.0
    hinted = hints
    retry = False
    started = time.monotonic()
    title = f"{drill[1]} | raw steno | esc=quit tab=hint"
    out(f"{DIM}{title[:max(1, shutil.get_terminal_size((80, 24)).columns - 1)]}{RST}\n")

    def draw():
        pace = ""
        if speed:
            delta = time.monotonic() - started - index * 60 / speed
            pace = f"{delta:+.0f}s"
        out(keyboard_line(sequence, index, misses, hinted,
                          shutil.get_terminal_size((80, 24)).columns, retry, pace))

    def submit(stroke):
        nonlocal index, misses, hinted, retry
        if not stroke or index >= length:
            return
        prompt = sequence[index]
        expected = raw_stroke(prompt)
        stat_key = "_keyboard:" + expected
        if stroke.upper() == expected:
            bump(stats, stat_key, "hit")
            index += 1
            hinted = hints
            retry = False
        else:
            misses += 1
            bump(stats, stat_key, "miss")
            hinted = True
            retry = True
        if index < length:
            draw()

    draw()
    try:
        while index < length:
            keys = read_burst()
            if any(ch in ("\x1b", "\x03") for ch in keys):
                break
            for ch in keys:
                if index >= length:
                    break
                if ch == "\t":
                    hinted = True
                    draw()
                elif ch in ("\b", "\x7f"):
                    buf = buf[:-1]
                elif ch.isspace():
                    submit(buf)
                    buf = ""
                elif ch.isprintable():
                    buf += ch
                last_input = time.monotonic()
            if buf and time.monotonic() - last_input >= 0.08:
                submit(buf)
                buf = ""
            time.sleep(0.01)
    except KeyboardInterrupt:
        pass
    elapsed = max(time.monotonic() - started, 0.001)
    total = index + misses
    accuracy = 100 * index / total if total else 0
    summary = (f"{'done' if index == length else 'stopped'} {index}/{length}  "
               f"{misses} misses  {accuracy:.0f}%  {index * 60 / elapsed:.0f}spm")
    out(f"\r\x1b[2K{DIM}{summary[:max(1, shutil.get_terminal_size((80, 24)).columns - 1)]}{RST}\n")


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


def main(argv=None):
    ap = argparse.ArgumentParser(description="steno drills")
    ap.add_argument("mode", nargs="?", default="flash", choices=["flash", "fall", "commit", "deploy", "keyboard"])
    ap.add_argument("drill_choice", nargs="?", help="keyboard: submenu number or drill name")
    ap.add_argument("--drill", help="keyboard: submenu number or drill name (omit for menu)")
    ap.add_argument("--list-drills", action="store_true", help="list keyboard drills and exit")
    ap.add_argument("--length", type=int, default=100, help="keyboard: number of chords")
    ap.add_argument("--hints", action="store_true", help="keyboard: always show raw stroke hints")
    ap.add_argument("--speed", type=float, default=0, help="keyboard: target strokes/minute (0 = untimed)")
    ap.add_argument("--goal", type=int, default=40, help="deploy: words to stroke")
    ap.add_argument("--words", type=int, default=100, help="pool size (most common first)")
    args = ap.parse_args(argv)
    if args.drill_choice and args.drill:
        ap.error("choose a drill using either the positional argument or --drill")
    chosen = args.drill_choice or args.drill
    if chosen and args.mode != "keyboard":
        ap.error("drill selection is only available in keyboard mode")
    if chosen:
        try:
            resolve_keyboard_drill(chosen)
        except ValueError as error:
            ap.error(str(error))
    if args.length < 1 or not 0 <= args.speed < float("inf"):
        ap.error("--length must be positive and --speed must be finite and nonnegative")
    if args.list_drills:
        for number, (name, title, _, _) in enumerate(KEYBOARD_DRILLS, 1):
            print(f"{number:2}. {name:20} {title}")
        return

    if args.mode == "keyboard":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        enable_vt()
        drill = select_keyboard_drill(chosen)
        if drill is not None:
            stats = load_stats()
            try:
                keyboard(drill, stats, args.length, args.hints, args.speed)
            finally:
                save_stats(stats)
        return

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
