using System.Globalization;

namespace AppleMagicTouchstream;

// Local practice scoring only. No runtime, device, preferences or output access.
internal sealed class TypingPracticeSession(string prompt, bool ignoresCase = false)
{
    internal enum Mode { Words, Steno, Custom }
    internal static readonly string[] CommonWords = "the be to of and a in that have for it not on with he as you do at this but his by from they we say her she or an will my one all would there their what so up out if about who get which go me when make can like time no just him know take people into year your good some could them see other than then now look only come its over think also back after use two how our work first well way even new want because any these give day most us water home hand place small great again around every word light right left read write world school still long little help sound move turn play learn".Split(' ');
    internal static readonly string[] StenoWords = "cat cats cap caps tap taps pat pats bat bats mat mats sat sad set sit pin pins pit pits tip tips top tops pot pots stop stops star stars start starts art arts part parts cart carts car cars bar bars far farm park parks hard heart hearts red read road rat rats rate rates late light lights night nights net nets ten tent tents test tests best bet bets bed beds bend bent rest rent run runs sun fun fan fans can cans pan pans plan plans plant plants sand hand hands land lands stand stands stone stones tone tones train trains rain rains brain brains".Split(' ');
    internal string Prompt { get; } = prompt;
    internal string Input { get; private set; } = "";
    internal DateTimeOffset? StartedAt { get; private set; }
    internal DateTimeOffset? FinishedAt { get; private set; }
    internal bool IgnoresCase { get; } = ignoresCase;
    internal static string[] Characters(string text) => StringInfo.GetTextElementEnumerator(text).AsEnumerable().ToArray();
    internal static string Limit(string text, int count) => string.Concat(Characters(text).Take(count));
    internal static string[] Words(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
        .Take(500).Select(word => Limit(word, 40)).ToArray();
    internal static string Generate(Mode mode, int count, string custom, Random random)
    {
        var source = (mode == Mode.Custom ? Words(custom) : mode == Mode.Steno ? StenoWords : CommonWords).Distinct().ToArray();
        if (source.Length == 0) return "";
        var result = new List<string>();
        for (int i = 0; i < Math.Clamp(count, 1, 100); ++i)
        {
            var choices = source.Length > 1 ? source.Where(word => word != result.LastOrDefault()).ToArray() : source;
            result.Add(choices[random.Next(choices.Length)]);
        }
        return string.Join(" ", result);
    }
    internal string Compare(string text)
    {
        string normalized = string.Join(" ", text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return IgnoresCase ? normalized.ToLowerInvariant() : normalized;
    }
    internal string ComparisonInput => Compare(Input);
    internal bool IsComplete => Prompt.Length > 0 && ComparisonInput == Compare(Prompt);
    internal void Update(string text, DateTimeOffset now)
    {
        if (FinishedAt != null) return;
        Input = Limit(text, 6000);
        if (StartedAt == null && Input.Length > 0) StartedAt = now;
        if (StartedAt != null && IsComplete) FinishedAt = now;
    }
    internal int CorrectCharacters => Characters(ComparisonInput).Zip(Characters(Compare(Prompt))).Count(pair => pair.First == pair.Second);
    internal double Accuracy => ComparisonInput.Length == 0 ? 100 : 100.0 * CorrectCharacters / Characters(ComparisonInput).Length;
    internal double Progress => Prompt.Length == 0 ? 0 : Math.Min(1, (double)CorrectCharacters / Characters(Compare(Prompt)).Length);
    internal double Elapsed(DateTimeOffset now) => StartedAt is {} start ? Math.Max(0, ((FinishedAt ?? now) - start).TotalSeconds) : 0;
    internal double Wpm(DateTimeOffset now) => Elapsed(now) < 1 ? 0 : CorrectCharacters / 5.0 / (Elapsed(now) / 60);
}

internal static class PracticeTextElements
{
    internal static IEnumerable<string> AsEnumerable(this TextElementEnumerator enumerator)
    {
        while (enumerator.MoveNext()) yield return enumerator.GetTextElement();
    }
}
