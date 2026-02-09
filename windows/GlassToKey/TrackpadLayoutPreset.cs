using System;

namespace GlassToKey;

public sealed class TrackpadLayoutPreset
{
    public static TrackpadLayoutPreset SixByThree { get; } = new(
        name: "6x3",
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
        columns: 6,
        rows: 4,
        columnAnchorsMm: new[]
        {
            new PointMm(24.0, 10.0),
            new PointMm(44.0, 10.0),
            new PointMm(64.0, 10.0),
            new PointMm(84.0, 10.0),
            new PointMm(104.0, 10.0),
            new PointMm(124.0, 10.0)
        },
        rightLabels: new[]
        {
            new[] { "Q", "W", "E", "R", "T", "Y" },
            new[] { "A", "S", "D", "F", "G", "H" },
            new[] { "Z", "X", "C", "V", "B", "N" },
            new[] { "TT", "Space", "MO(1)", "TO(1)", "Back", "Ret" }
        }
    );

    public static TrackpadLayoutPreset[] All { get; } =
    {
        SixByThree,
        SixByFour,
        FiveByThree,
        FiveByFour,
        Mobile
    };

    public string Name { get; }
    public int Columns { get; }
    public int Rows { get; }
    public PointMm[] ColumnAnchorsMm { get; }
    public string[][] RightLabels { get; }
    public string[][] LeftLabels => Mirror(RightLabels);

    private TrackpadLayoutPreset(string name, int columns, int rows, PointMm[] columnAnchorsMm, string[][] rightLabels)
    {
        Name = name;
        Columns = columns;
        Rows = rows;
        ColumnAnchorsMm = columnAnchorsMm;
        RightLabels = rightLabels;
    }

    public override string ToString()
    {
        return Name;
    }

    public static TrackpadLayoutPreset ResolveByNameOrDefault(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return SixByThree;
        }

        for (int i = 0; i < All.Length; i++)
        {
            if (string.Equals(All[i].Name, name, StringComparison.OrdinalIgnoreCase))
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
