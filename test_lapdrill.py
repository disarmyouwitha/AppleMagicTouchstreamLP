"""Offline keyboard-drill regressions; no Plover or dictionary required."""
import unittest
from unittest.mock import patch

import lapdrill as drill


class KeyboardDrillTests(unittest.TestCase):
    def test_all_drills_generate_valid_raw_steno(self):
        import re
        self.assertEqual(len(drill.KEYBOARD_DRILLS), 18)
        for lesson in drill.KEYBOARD_DRILLS:
            sequence = drill.keyboard_sequence(lesson, 150)
            self.assertEqual(len(sequence), 150)
            for prompt in sequence:
                self.assertRegex(drill.raw_stroke(prompt),
                                 re.compile(r"^[STKPWHR]*(?:[AOEU]+|-)[FRPBLGTSDZ]*$|^[STKPWHR]+$"))

    def test_pseudo_chords(self):
        expected = {"D-": "TK", "B-": "PW", "L-": "HR", "-N": "-PB",
                    "F-": "TP", "M-": "PH", "Q-": "KW", "-M": "-PL",
                    "-K": "-BG", "N-": "TPH", "Y-": "KWR", "J-": "SKWR",
                    "C-": "KR", "V-": "SR", "G-": "TKPW", "X-": "KP",
                    "Z-": "STKPW", "-J": "-PBLG", "S-F": "S-F", "AF": "AF"}
        for prompt, raw in expected.items():
            self.assertEqual(drill.raw_stroke(prompt), raw)

    def test_intro_order_and_truncation(self):
        lesson = drill.KEYBOARD_DRILLS[0]
        sequence = drill.keyboard_sequence(lesson, 28)
        self.assertEqual(sequence[:16], list("SKWRSKWRRWKSRWKS"))
        triples = [sequence[i:i + 3] for i in range(16, 28, 3)]
        self.assertEqual({t[0] for t in triples}, set("SKWR"))
        self.assertTrue(all(len(set(t)) == 1 for t in triples))
        self.assertEqual(drill.keyboard_sequence(lesson, 2), ["S", "K"])

    def run_session(self, bursts, sequence):
        stats = {}
        ticks = iter(i * .01 for i in range(1000))
        inputs = iter(bursts)
        with patch.object(drill, "keyboard_sequence", return_value=sequence), \
                patch.object(drill, "read_burst", side_effect=lambda: next(inputs, ["\x1b"])), \
                patch.object(drill.time, "monotonic", side_effect=lambda: next(ticks)), \
                patch.object(drill.time, "sleep"), patch.object(drill, "out"):
            drill.keyboard(drill.KEYBOARD_DRILLS[0], stats, length=len(sequence))
        return stats

    def test_wrong_longer_chord_retries_instead_of_accepting_prefix(self):
        stats = self.run_session([list("SK "), list("S "), list("K\r\t")], ["S", "K"])
        self.assertEqual(stats["_keyboard:S"], {"hit": 1, "miss": 1})
        self.assertEqual(stats["_keyboard:K"], {"hit": 1, "miss": 0})

    def test_split_burst_and_silence(self):
        stats = self.run_session([["T"], ["K"]] + [[]] * 12, ["D-"])
        self.assertEqual(stats["_keyboard:TK"], {"hit": 1, "miss": 0})

    def test_correction_and_case(self):
        stats = self.run_session([list("tx\bk\r")], ["D-"])
        self.assertEqual(stats["_keyboard:TK"], {"hit": 1, "miss": 0})


if __name__ == "__main__":
    unittest.main()
