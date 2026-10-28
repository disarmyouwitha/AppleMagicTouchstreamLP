using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;

namespace GlassToKey;

public sealed class AutocorrectSession : IDisposable
{
    private const int MinimumWordLength = 3;
    private const int MaximumWordLength = 48;
    private const int CacheCapacity = 2048;
    private const int WordHistoryCapacity = 24;
    private const int MaxEditDistanceMin = 1;
    private const int MaxEditDistanceMax = 2;

    private readonly IAutocorrectLexicon _lexicon;
    private readonly StringBuilder _wordBuffer = new(24);
    private readonly Dictionary<string, string?> _cache = new(StringComparer.Ordinal);
    private readonly HashSet<string> _blacklist = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _overrides = new(StringComparer.Ordinal);
    private readonly string[] _wordHistory = new string[WordHistoryCapacity];
    private bool _enabled;
    private string _contextKey = string.Empty;
    private string _currentApp = "unknown";
    private string _lastCorrected = "none";
    private string _bufferSnapshot = string.Empty;
    private string _skipReason = "idle";
    private string _lastResetSource = "none";
    private string _wordHistorySnapshot = "<empty>";
    private int _wordHistoryWriteIndex;
    private int _wordHistoryCount;
    private int _maxEditDistance = MaxEditDistanceMax;
    private bool _dryRunEnabled;
    private long _counterCorrected;
    private long _counterSkipped;
    private long _counterResetByClick;
    private long _counterResetByAppChange;
    private long _counterShortcutBypass;

    public AutocorrectSession()
        : this(new SymSpellAutocorrectLexicon())
    {
    }

    public AutocorrectSession(IAutocorrectLexicon lexicon)
    {
        _lexicon = lexicon ?? throw new ArgumentNullException(nameof(lexicon));
    }

    public void Dispose()
    {
        _lexicon.Unload();
    }

    public void SetEnabled(bool enabled)
    {
        _enabled = enabled;
        if (enabled)
        {
            _ = _lexicon.EnsureLoaded();
            _skipReason = "enabled";
            return;
        }

        ResetState("disabled");
        _contextKey = string.Empty;
        _currentApp = "unknown";
        _lexicon.Unload();
        _cache.Clear();
    }

    public void Configure(AutocorrectOptions options)
    {
        int normalizedMaxDistance = Math.Clamp(options.MaxEditDistance, MaxEditDistanceMin, MaxEditDistanceMax);
        bool cacheInvalidated = normalizedMaxDistance != _maxEditDistance;
        _maxEditDistance = normalizedMaxDistance;
        _dryRunEnabled = options.DryRunEnabled;

        HashSet<string> parsedBlacklist = ParseWordSet(options.BlacklistCsv);
        Dictionary<string, string> parsedOverrides = ParseOverrides(options.OverridesCsv);
        if (!SetEquals(_blacklist, parsedBlacklist))
        {
            _blacklist.Clear();
            foreach (string word in parsedBlacklist)
            {
                _blacklist.Add(word);
            }

            cacheInvalidated = true;
        }

        if (!MapEquals(_overrides, parsedOverrides))
        {
            _overrides.Clear();
            foreach ((string key, string value) in parsedOverrides)
            {
                _overrides[key] = value;
            }

            cacheInvalidated = true;
        }

        if (cacheInvalidated)
        {
            _cache.Clear();
        }
    }

    public AutocorrectStatusSnapshot GetStatus()
    {
        return new AutocorrectStatusSnapshot(
            Enabled: _enabled,
            DryRunEnabled: _dryRunEnabled,
            MaxEditDistance: _maxEditDistance,
            CurrentApp: _currentApp,
            LastCorrected: _lastCorrected,
            CurrentBuffer: _bufferSnapshot,
            SkipReason: _skipReason,
            LastResetSource: _lastResetSource,
            CorrectedCount: _counterCorrected,
            SkippedCount: _counterSkipped,
            ResetByClickCount: _counterResetByClick,
            ResetByAppChangeCount: _counterResetByAppChange,
            ShortcutBypassCount: _counterShortcutBypass,
            WordHistory: _wordHistorySnapshot);
    }

    public void UpdateContext(string? contextKey, string? contextLabel)
    {
        if (string.IsNullOrWhiteSpace(contextKey))
        {
            return;
        }

        bool changed = !string.Equals(_contextKey, contextKey, StringComparison.Ordinal);
        if (_contextKey.Length > 0 && changed)
        {
            ResetState("app_changed");
        }

        if (changed)
        {
            _currentApp = string.IsNullOrWhiteSpace(contextLabel) ? "unknown" : contextLabel.Trim();
        }

        _contextKey = contextKey;
    }

    public void NotifyPointerActivity()
    {
        ResetState("pointer_click");
    }

    public void NotifyShortcutBypass()
    {
        _counterShortcutBypass++;
        ResetState("shortcut_active");
    }

    public void TrackBackspace()
    {
        if (_wordBuffer.Length > 0)
        {
            _wordBuffer.Length--;
            _bufferSnapshot = _wordBuffer.ToString();
        }

        _skipReason = "manual_backspace";
    }

    public void TrackLetter(char letter)
    {
        if (_wordBuffer.Length < MaximumWordLength)
        {
            _wordBuffer.Append(letter);
            _bufferSnapshot = _wordBuffer.ToString();
        }

        _skipReason = "tracking";
    }

    public void NotifyNonWordKey()
    {
        ResetState("non_word_key");
    }

    public bool TryCompleteWord(out AutocorrectReplacement replacement)
    {
        replacement = default;

        string typedWord = _wordBuffer.ToString();
        if (typedWord.Length == 0)
        {
            _skipReason = "word_empty";
            ResetState();
            return false;
        }

        RecordWordHistory(typedWord);

        if (_wordBuffer.Length < MinimumWordLength || _wordBuffer.Length > MaximumWordLength)
        {
            RegisterSkip("word_length");
            ResetState();
            return false;
        }

        if (!_lexicon.EnsureLoaded())
        {
            RegisterSkip("dictionary_unavailable");
            ResetState();
            return false;
        }

        string typedLower = typedWord.ToLowerInvariant();
        if (_blacklist.Contains(typedLower))
        {
            RegisterSkip("blacklisted");
            ResetState();
            return false;
        }

        string resolutionSource;
        string? correctedLower;
        if (_overrides.TryGetValue(typedLower, out string? overrideCorrection))
        {
            correctedLower = overrideCorrection;
            resolutionSource = "override";
        }
        else
        {
            correctedLower = ResolveCorrection(typedLower);
            resolutionSource = "symspell";
        }

        if (string.IsNullOrEmpty(correctedLower))
        {
            RegisterSkip("no_suggestion");
            ResetState();
            return false;
        }

        string corrected = ApplyWordCasePattern(correctedLower, typedWord);
        if (string.Equals(corrected, typedWord, StringComparison.Ordinal))
        {
            RegisterSkip("already_correct");
            ResetState();
            return false;
        }

        if (_dryRunEnabled)
        {
            _counterSkipped++;
            _lastCorrected = $"{typedWord} -> {corrected} (dry-run)";
            _skipReason = "dry_run_preview";
            ResetState();
            return false;
        }

        _counterCorrected++;
        _lastCorrected = resolutionSource == "override"
            ? $"{typedWord} -> {corrected} (override)"
            : $"{typedWord} -> {corrected}";
        _skipReason = "corrected";
        replacement = new AutocorrectReplacement(typedWord.Length, corrected);
        ResetState();
        return true;
    }

    public void ForceReset(string reason)
    {
        ResetState(reason);
    }

    private string? ResolveCorrection(string typedLower)
    {
        string cacheKey = $"{_maxEditDistance}:{typedLower}";
        if (_cache.TryGetValue(cacheKey, out string? cached))
        {
            return cached;
        }

        string? correction = _lexicon.ResolveCorrection(typedLower, _maxEditDistance);
        if (_cache.Count >= CacheCapacity)
        {
            _cache.Clear();
        }

        _cache[cacheKey] = correction;
        return correction;
    }

    private void ResetState(string? reason = null)
    {
        _wordBuffer.Clear();
        _bufferSnapshot = string.Empty;
        if (string.IsNullOrWhiteSpace(reason))
        {
            return;
        }

        _skipReason = reason;
        _lastResetSource = reason;
        if (string.Equals(reason, "pointer_click", StringComparison.Ordinal))
        {
            _counterResetByClick++;
        }
        else if (string.Equals(reason, "app_changed", StringComparison.Ordinal))
        {
            _counterResetByAppChange++;
        }
    }

    private void RegisterSkip(string reason)
    {
        _counterSkipped++;
        _skipReason = reason;
    }

    private void RecordWordHistory(string word)
    {
        if (string.IsNullOrWhiteSpace(word))
        {
            return;
        }

        _wordHistory[_wordHistoryWriteIndex] = word;
        _wordHistoryWriteIndex = (_wordHistoryWriteIndex + 1) % _wordHistory.Length;
        if (_wordHistoryCount < _wordHistory.Length)
        {
            _wordHistoryCount++;
        }

        _wordHistorySnapshot = BuildWordHistorySnapshot();
    }

    private string BuildWordHistorySnapshot()
    {
        if (_wordHistoryCount == 0)
        {
            return "<empty>";
        }

        StringBuilder builder = new(capacity: 128);
        for (int i = 0; i < _wordHistoryCount; i++)
        {
            int index = (_wordHistoryWriteIndex - _wordHistoryCount + i + _wordHistory.Length) % _wordHistory.Length;
            if (i > 0)
            {
                builder.Append(' ');
            }

            builder.Append(_wordHistory[index]);
        }

        return builder.ToString();
    }

    private static string ApplyWordCasePattern(string correction, string original)
    {
        if (string.IsNullOrEmpty(correction) || string.IsNullOrEmpty(original))
        {
            return correction;
        }

        bool allUpper = true;
        bool firstUpperRestLower = char.IsUpper(original[0]);
        for (int i = 0; i < original.Length; i++)
        {
            char ch = original[i];
            if (char.IsLetter(ch))
            {
                if (!char.IsUpper(ch))
                {
                    allUpper = false;
                }

                if (i > 0 && !char.IsLower(ch))
                {
                    firstUpperRestLower = false;
                }
            }
            else
            {
                allUpper = false;
                firstUpperRestLower = false;
            }
        }

        if (allUpper)
        {
            return correction.ToUpperInvariant();
        }

        if (firstUpperRestLower)
        {
            return correction.Length == 1
                ? correction.ToUpperInvariant()
                : char.ToUpperInvariant(correction[0]) + correction.Substring(1).ToLowerInvariant();
        }

        return correction.ToLowerInvariant();
    }

    private static bool IsAsciiLetterWord(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return false;
        }

        for (int i = 0; i < value.Length; i++)
        {
            char ch = value[i];
            if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')))
            {
                return false;
            }
        }

        return true;
    }

    private static HashSet<string> ParseWordSet(string? source)
    {
        HashSet<string> values = new(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(source))
        {
            return values;
        }

        ReadOnlySpan<char> span = source.AsSpan();
        int start = 0;
        for (int i = 0; i <= span.Length; i++)
        {
            bool boundary = i == span.Length ||
                span[i] == ',' ||
                span[i] == ';' ||
                span[i] == ' ' ||
                span[i] == '\n' ||
                span[i] == '\r' ||
                span[i] == '\t';
            if (!boundary)
            {
                continue;
            }

            ReadOnlySpan<char> token = span[start..i].Trim();
            start = i + 1;
            if (token.IsEmpty)
            {
                continue;
            }

            string word = token.ToString().ToLowerInvariant();
            if (IsAsciiLetterWord(word))
            {
                values.Add(word);
            }
        }

        return values;
    }

    private static Dictionary<string, string> ParseOverrides(string? source)
    {
        Dictionary<string, string> map = new(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(source))
        {
            return map;
        }

        string normalized = source.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        string[] lines = normalized.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].Trim();
            if (line.Length == 0)
            {
                continue;
            }

            string[] segments = line.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            for (int segmentIndex = 0; segmentIndex < segments.Length; segmentIndex++)
            {
                if (!TryParseOverride(segments[segmentIndex], out string from, out string to))
                {
                    continue;
                }

                map[from] = to;
            }
        }

        return map;
    }

    private static bool TryParseOverride(string text, out string from, out string to)
    {
        from = string.Empty;
        to = string.Empty;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        string line = text.Trim();
        int separatorIndex = line.IndexOf("->", StringComparison.Ordinal);
        int separatorLength = 2;
        if (separatorIndex < 0)
        {
            separatorIndex = line.IndexOf('=', StringComparison.Ordinal);
            separatorLength = 1;
        }

        if (separatorIndex < 0)
        {
            separatorIndex = line.IndexOf(':', StringComparison.Ordinal);
            separatorLength = 1;
        }

        if (separatorIndex <= 0 || separatorIndex >= line.Length - separatorLength)
        {
            return false;
        }

        string left = line.Substring(0, separatorIndex).Trim().ToLowerInvariant();
        string right = line.Substring(separatorIndex + separatorLength).Trim().ToLowerInvariant();
        if (!IsAsciiLetterWord(left) || !IsAsciiLetterWord(right))
        {
            return false;
        }

        from = left;
        to = right;
        return true;
    }

    private static bool SetEquals(HashSet<string> existing, HashSet<string> next)
    {
        return existing.Count == next.Count && existing.SetEquals(next);
    }

    private static bool MapEquals(Dictionary<string, string> existing, Dictionary<string, string> next)
    {
        if (existing.Count != next.Count)
        {
            return false;
        }

        foreach ((string key, string value) in next)
        {
            if (!existing.TryGetValue(key, out string? existingValue) ||
                !string.Equals(existingValue, value, StringComparison.Ordinal))
            {
                return false;
            }
        }

        return true;
    }

    public interface IAutocorrectLexicon
    {
        bool EnsureLoaded();
        string? ResolveCorrection(string typedLower, int maxEditDistance);
        void Unload();
    }

    private sealed class SymSpellAutocorrectLexicon : IAutocorrectLexicon
    {
        private const int SymSpellDictionaryMaxEditDistance = 2;
        private const int SymSpellPrefixLength = 7;
        private const int SymSpellDictionaryWordCount = 82765;
        private const string DictionaryResourceName = "GlassToKey.SymSpell.frequency_dictionary_en_82_765.txt";

        private SymSpell? _symSpell;
        private bool _loadAttempted;

        public bool EnsureLoaded()
        {
            if (_symSpell != null)
            {
                return true;
            }

            if (_loadAttempted)
            {
                return false;
            }

            _loadAttempted = true;
            _symSpell = CreateSymSpell();
            return _symSpell != null;
        }

        public string? ResolveCorrection(string typedLower, int maxEditDistance)
        {
            if (!EnsureLoaded() || _symSpell == null)
            {
                return null;
            }

            List<SymSpell.SuggestItem> suggestions = _symSpell.Lookup(
                typedLower,
                SymSpell.Verbosity.Top,
                maxEditDistance);
            if (suggestions.Count == 0)
            {
                return null;
            }

            SymSpell.SuggestItem suggestion = suggestions[0];
            if (suggestion.distance <= 0 ||
                !IsAsciiLetterWord(suggestion.term) ||
                string.Equals(suggestion.term, typedLower, StringComparison.Ordinal))
            {
                return null;
            }

            return suggestion.term;
        }

        public void Unload()
        {
            _symSpell = null;
            _loadAttempted = false;
        }

        private static SymSpell? CreateSymSpell()
        {
            try
            {
                SymSpell symSpell = new(
                    initialCapacity: SymSpellDictionaryWordCount,
                    maxDictionaryEditDistance: SymSpellDictionaryMaxEditDistance,
                    prefixLength: SymSpellPrefixLength);
                using Stream? stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(DictionaryResourceName);
                if (stream == null)
                {
                    return null;
                }

                return symSpell.LoadDictionary(stream, termIndex: 0, countIndex: 1) ? symSpell : null;
            }
            catch
            {
                return null;
            }
        }
    }
}
