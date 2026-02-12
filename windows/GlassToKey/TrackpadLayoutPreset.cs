using System;

namespace GlassToKey;

public sealed class TrackpadLayoutPreset
{
    public static TrackpadLayoutPreset Blank { get; } = new(
        name: "Blank",
        displayName: "Blank",
        columns: 0,
        rows: 0,
        columnAnchorsMm: Array.Empty<PointMm>(),
        rightLabels: Array.Empty<string[]>()
    );

    public static TrackpadLayoutPreset SixByThree { get; } = new(
        name: "6x3",
        displayName: "6x3",
        columns: 6,
        rows: 3,
        columnAnchorsMm: new[]
        {
            new PointMm(35.0, 20.9),
            new PointMm(53.0, 19.2),
            new PointMm(71.0, 17.5),
            new PointMm(89.0, 19.2),
            new PointMm(107.0, 22.6),
            new PointMm(125.0, 22.6)
        },
        rightLabels: new[]
        {
            new[] { "Y", "U", "I", "O", "P", "Back" },
            new[] { "H", "J", "K", "L", ";", "Ret" },
            new[] { "N", "M", ",", ".", "/", "Ret" }
        }
    );

    public static TrackpadLayoutPreset SixByFour { get; } = new(
        name: "6x4",
        displayName: "6x4",
        columns: 6,
        rows: 4,
        columnAnchorsMm: new[]
        {
            new PointMm(32.0, 14.0),
            new PointMm(50.0, 14.0),
            new PointMm(68.0, 14.0),
            new PointMm(86.0, 14.0),
            new PointMm(104.0, 14.0),
            new PointMm(122.0, 14.0)
        },
        rightLabels: new[]
        {
            new[] { "6", "7", "8", "9", "0", "Back" },
            new[] { "Y", "U", "I", "O", "P", "]" },
            new[] { "H", "J", "K", "L", ";", "Ret" },
            new[] { "N", "M", ",", ".", "/", "Ret" }
        }
    );

    public static TrackpadLayoutPreset FiveByThree { get; } = new(
        name: "5x3",
        displayName: "5x3",
        columns: 5,
        rows: 3,
        columnAnchorsMm: new[]
        {
            new PointMm(36.0, 19.0),
            new PointMm(56.0, 19.0),
            new PointMm(76.0, 19.0),
            new PointMm(96.0, 19.0),
            new PointMm(116.0, 19.0)
        },
        rightLabels: new[]
        {
            new[] { "Y", "U", "I", "O", "P" },
            new[] { "H", "J", "K", "L", ";" },
            new[] { "N", "M", ",", ".", "/" }
        }
    );

    public static TrackpadLayoutPreset FiveByFour { get; } = new(
        name: "5x4",
        displayName: "5x4",
        columns: 5,
        rows: 4,
        columnAnchorsMm: new[]
        {
            new PointMm(34.0, 12.0),
            new PointMm(54.0, 12.0),
            new PointMm(74.0, 12.0),
            new PointMm(94.0, 12.0),
            new PointMm(114.0, 12.0)
        },
        rightLabels: new[]
        {
            new[] { "5", "6", "7", "8", "9" },
            new[] { "T", "Y", "U", "I", "O" },
            new[] { "G", "H", "J", "K", "L" },
            new[] { "B", "N", "M", ",", "." }
        }
    );

    public static TrackpadLayoutPreset Mobile { get; } = new(
        name: "mobile",
        displayName: "Mobile",
        columns: 10,
        rows: 4,
        columnAnchorsMm: new[]
        {
            new PointMm(8.0, 10.0),
            new PointMm(22.0, 10.0),
            new PointMm(36.0, 10.0),
            new PointMm(50.0, 10.0),
            new PointMm(64.0, 10.0),
            new PointMm(78.0, 10.0),
            new PointMm(92.0, 10.0),
            new PointMm(106.0, 10.0),
            new PointMm(120.0, 10.0),
            new PointMm(134.0, 10.0)
        },
        rightLabels: new[]
        {
            new[] { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
            new[] { "A", "S", "D", "F", "G", "H", "J", "K", "L", "Ret" },
            new[] { "Z", "X", "C", "V", "B", "N", "M", ",", ".", "Back" },
            new[] { "Space" }
        },
        blankLeftSide: true,
        useFixedRightStaggeredQwerty: true,
        fixedKeyScale: 0.75
    );

    public static TrackpadLayoutPreset MobileOrthoTwelveByFour { get; } = new(
        name: "mobile-ortho-12x4",
        displayName: "Planck",
        columns: 12,
        rows: 4,
        columnAnchorsMm: new[]
        {
            new PointMm(6.0, 10.0),
            new PointMm(18.0, 10.0),
            new PointMm(30.0, 10.0),
            new PointMm(42.0, 10.0),
            new PointMm(54.0, 10.0),
            new PointMm(66.0, 10.0),
            new PointMm(78.0, 10.0),
            new PointMm(90.0, 10.0),
            new PointMm(102.0, 10.0),
            new PointMm(114.0, 10.0),
            new PointMm(126.0, 10.0),
            new PointMm(138.0, 10.0)
        },
        rightLabels: new[]
        {
            new[] { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "Back" },
            new[] { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]" },
            new[] { "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Ret" },
            new[] { "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Shift", "Space" }
        },
        blankLeftSide: true,
        fixedKeyScale: 0.70,
        allowsColumnSettings: true
    );

    public static TrackpadLayoutPreset[] All { get; } =
    {
        Blank,
        SixByThree,
        SixByFour,
        FiveByThree,
        FiveByFour,
        MobileOrthoTwelveByFour,
        Mobile
    };

    public string Name { get; }
    public string DisplayName { get; }
    public int Columns { get; }
    public int Rows { get; }
    public PointMm[] ColumnAnchorsMm { get; }
    public string[][] RightLabels { get; }
    public bool BlankLeftSide { get; }
    public bool UseFixedRightStaggeredQwerty { get; }
    public double FixedKeyScale { get; }
    public bool AllowsColumnSettings { get; }
    public string[][] LeftLabels => Mirror(RightLabels);

    private TrackpadLayoutPreset(
        string name,
        string displayName,
        int columns,
        int rows,
        PointMm[] columnAnchorsMm,
        string[][] rightLabels,
        bool blankLeftSide = false,
        bool useFixedRightStaggeredQwerty = false,
        double fixedKeyScale = 1.0,
        bool? allowsColumnSettings = null)
    {
        Name = name;
        DisplayName = string.IsNullOrWhiteSpace(displayName) ? name : displayName;
        Columns = columns;
        Rows = rows;
        ColumnAnchorsMm = columnAnchorsMm;
        RightLabels = rightLabels;
        BlankLeftSide = blankLeftSide;
        UseFixedRightStaggeredQwerty = useFixedRightStaggeredQwerty;
        FixedKeyScale = Math.Clamp(fixedKeyScale, 0.25, 2.0);
        AllowsColumnSettings = allowsColumnSettings ?? !useFixedRightStaggeredQwerty;
    }

    public override string ToString()
    {
        return DisplayName;
    }

    public static TrackpadLayoutPreset ResolveByNameOrDefault(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return SixByThree;
        }

        string trimmed = name.Trim();
        if (string.Equals(trimmed, "Mobile QWERTY", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(trimmed, "mobile-qwerty", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(trimmed, "mobile_qwerty", StringComparison.OrdinalIgnoreCase))
        {
            return Mobile;
        }

        for (int i = 0; i < All.Length; i++)
        {
            if (string.Equals(All[i].Name, trimmed, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(All[i].DisplayName, trimmed, StringComparison.OrdinalIgnoreCase))
            {
                return All[i];
            }
        }

        return SixByThree;
    }

    private static string[][] Mirror(string[][] labels)
    {
        string[][] output = new string[labels.Length][];
        for (int r = 0; r < labels.Length; r++)
        {
            string[] row = labels[r];
            string[] mirrored = new string[row.Length];
            for (int c = 0; c < row.Length; c++)
            {
                mirrored[c] = row[row.Length - 1 - c];
            }
            output[r] = mirrored;
        }
        return output;
    }
}

public readonly record struct PointMm(double X, double Y);
