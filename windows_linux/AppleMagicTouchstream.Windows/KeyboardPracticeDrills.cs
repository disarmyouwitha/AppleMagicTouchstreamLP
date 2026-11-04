namespace AppleMagicTouchstream;

// Same beginner sets and introductory order as lapdrill.py / StenoJig.
internal static class KeyboardPracticeDrills
{
    internal sealed record Drill(string Title, string[][] Groups, bool Intro);
    internal static readonly Drill[] All =
    [
        new("Left hand, bottom row", [["S", "K", "W", "R"]], true),
        new("Right hand, bottom row", [["-S", "-G", "-B", "-R"]], true),
        new("Left hand, top row", [["S", "T", "P", "H"]], true),
        new("Right hand, top row", [["-F", "-P", "-L", "-T"]], true),
        new("Right hand, full bottom row", [["-Z", "-S", "-G", "-B", "-R"]], true),
        new("Right hand, full top row", [["-F", "-P", "-L", "-T", "-D"]], true),
        new("Vowels", [["A", "O", "E", "U"]], true),
        new("Left hand", [["S", "T", "K", "P", "W", "H", "R"]], false),
        new("Right hand", [["-F", "-R", "-P", "-B", "-L", "-G", "-T", "-S", "-D", "-Z"]], false),
        new("All keys", [["S", "T", "K", "P", "W", "H", "R", "A", "O", "E", "U", "-F", "-R", "-P", "-B", "-L", "-G", "-T", "-S", "-D", "-Z"]], false),
        new("Left + Right", [["S", "T", "K", "P", "W", "H", "R"], ["-F", "-R", "-P", "-B", "-L", "-G", "-T", "-S", "-D", "-Z"]], false),
        new("Left + Vowel", [["S", "T", "K", "P", "W", "H", "R"], ["A", "O", "E", "U"]], false),
        new("Vowel + Right", [["A", "O", "E", "U"], ["F", "R", "P", "B", "L", "G", "T", "S", "D", "Z"]], false),
        new("Left + Vowel + Right", [["S", "T", "K", "P", "W", "H", "R"], ["A", "O", "E", "U"], ["F", "R", "P", "B", "L", "G", "T", "S", "D", "Z"]], false),
        new("Columns: D, B, L, -N", [["D-", "B-", "L-", "-N"]], true),
        new("Rows (2-key): F, M, Q, -M, -K", [["F-", "M-", "Q-", "-M", "-K"]], true),
        new("Rows: N, Y, J, C, V", [["N-", "Y-", "J-", "C-", "V-"]], true),
        new("Other chords: G, X, Z, -J", [["G-", "X-", "Z-", "-J"]], true),
    ];
    private static readonly Dictionary<string, string> Pseudo = new()
    {
        ["D-"] = "TK",
        ["B-"] = "PW",
        ["L-"] = "HR",
        ["F-"] = "TP",
        ["M-"] = "PH",
        ["Q-"] = "KW",
        ["N-"] = "TPH",
        ["Y-"] = "KWR",
        ["J-"] = "SKWR",
        ["C-"] = "KR",
        ["V-"] = "SR",
        ["G-"] = "TKPW",
        ["X-"] = "KP",
        ["Z-"] = "STKPW",
        ["-N"] = "-PB",
        ["-M"] = "-PL",
        ["-K"] = "-BG",
        ["-J"] = "-PBLG",
    };
    internal static string Raw(string prompt) => Pseudo.GetValueOrDefault(prompt, prompt);
    internal static string Generate(int drillIndex, int count, Random random)
    {
        var drill = All[drillIndex];
        count = Math.Clamp(count, 1, 100);
        var sequence = new List<string>();
        if (drill.Intro)
        {
            var chords = drill.Groups[0];
            sequence.AddRange(chords); sequence.AddRange(chords);
            sequence.AddRange(chords.Reverse()); sequence.AddRange(chords.Reverse());
            var shuffled = chords.ToArray(); random.Shuffle(shuffled);
            foreach (string chord in shuffled) sequence.AddRange(Enumerable.Repeat(chord, 3));
        }
        while (sequence.Count < count)
            sequence.Add(string.Concat(drill.Groups.Select(group => group[random.Next(group.Length)])));
        return string.Join(" ", sequence.Take(count).Select(Raw));
    }
    internal static string Guide(int drillIndex) => string.Join("   ", All[drillIndex].Groups.SelectMany(group => group)
        .Where(prompt => Raw(prompt) != prompt).Select(prompt => $"{prompt} = {Raw(prompt)}"));
}
