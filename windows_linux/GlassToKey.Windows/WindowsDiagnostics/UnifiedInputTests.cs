using System.Diagnostics;

namespace GlassToKey;

internal static class UnifiedInputTests
{
    public static bool Run(out string failure)
    {
        try
        {
            var settings = new UserSettings { KeyboardModeEnabled = true, TypingEnabled = false };
            var keymap = KeymapStore.LoadBundledDefault();
            string key = GridKeyPosition.StorageKey(TrackpadSide.Left,0,1);
            keymap.Mappings[0][key] = new KeyMapping { Primary = new KeyAction { Label = "A" }, Hold = null };
            var core = TouchProcessorFactory.CreateConfigured(keymap,settings);
            core.UseHandGestureRecognition(); core.UseUnifiedInputPolicy();
            core.SetTypingEnabled(false); core.SetKeyboardModeEnabled(true); core.SetTypingToggleActionsEnabled(true);
            if (!core.Snapshot().TypingEnabled || core.Snapshot().KeyboardModeEnabled) throw new Exception("Legacy mode setter affected unified input.");
            WindowsInputPolicy.NormalizeLegacyModes(settings);
            if (settings.KeyboardModeEnabled || !settings.TypingEnabled) throw new Exception("Old profile modes were not neutralized.");
            var preset = TrackpadLayoutPreset.SixByThree;
            var layout = LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(preset.Columns),true);
            var rect = layout.Rects[0][1];
            var down = new InputFrame { ContactCount = 1 };
            down.SetContact(0,new(1,(ushort)((rect.X+rect.Width*.5)*7612),(ushort)((rect.Y+rect.Height*.5)*5065),3,HasForceData:false));
            var up = new InputFrame();
            long time(double ms) => (long)(Stopwatch.Frequency*ms/1000);
            core.ProcessFrame(TrackpadSide.Left,in down,7612,5065,time(1000));
            core.ProcessFrame(TrackpadSide.Left,in down,7612,5065,time(1040));
            core.ProcessFrame(TrackpadSide.Left,in up,7612,5065,time(1080));
            var events = new DispatchEvent[32]; int n = core.DrainDispatchEvents(events);
            if (!events.Take(n).Any(e=>e.Kind == DispatchEventKind.KeyTap && e.VirtualKey == 0x41)) throw new Exception("Unified input did not preserve a keyboard tap.");
            keymap.Mappings[0][key] = new KeyMapping { Primary = new KeyAction { Label = "Typing Toggle" }, Hold = null };
            core.ConfigureKeymap(keymap);
            core.ProcessFrame(TrackpadSide.Left,in down,7612,5065,time(1200));
            core.ProcessFrame(TrackpadSide.Left,in up,7612,5065,time(1240));
            if (!core.Snapshot().TypingEnabled) throw new Exception("Imported typing toggle disabled unified typing.");
            var legacy = TouchProcessorFactory.CreateDefault(KeymapStore.LoadBundledDefault());
            legacy.SetKeyboardModeEnabled(true); legacy.SetTypingEnabled(false);
            if (!legacy.Snapshot().KeyboardModeEnabled || legacy.Snapshot().TypingEnabled) throw new Exception("Shared Linux policy changed.");
            var image = ApplicationHandIcon.CreateImage();
            if (image.PixelWidth != 32 || image.PixelHeight != 32 || image.Format.BitsPerPixel != 32) throw new Exception("Hand image dimensions/format are invalid.");
            var pixels = new byte[32*32*4]; image.CopyPixels(pixels,32*4,0);
            int visible = 0;
            for (int i = 0; i < pixels.Length; i+=4) if (pixels[i+3] != 0)
            {
                visible++;
                if (pixels[i] != 0 || pixels[i+1] != 0 || pixels[i+2] != 0) throw new Exception("Hand fill is not black.");
            }
            if (visible == 0 || visible == 1024) throw new Exception("Hand silhouette/transparency is invalid.");
            using var icon = ApplicationHandIcon.CreateTrayIcon();
            if (icon.Width != 32 || icon.Height != 32) throw new Exception("Tray icon could not load at native resolution.");
            failure = ""; return true;
        }
        catch (Exception ex) { failure = ex.Message; return false; }
    }
}
