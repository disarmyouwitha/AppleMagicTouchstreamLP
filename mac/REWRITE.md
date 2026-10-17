## Rewrite
**Exclusive HID ownership plus our interpreter:** [IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen) supports the [SeizeDevice option](https://developer.apple.com/documentation/iokit/1556660-anonymous/kiohidoptionstypeseizedevice?changes=_2). This worked incredibly well this is our path forward here 


0. NEXT TEST: Can I allow certain actions to pass through?

===

`gesturepad`: redesign GUI for better visual display of touches. 1. Remove `HID interfaces and report counts` and `Copy Diagnostics` 2. From `Live Values` show left touches on the left of the visualizer and right to the right. Maybe this can all happen under the trackpad visualizer instead of in a pop-out/modal like it is now. 3. lets move the Blackhold target info under the left/right trackpad selectors. 

`AppleMagicTouchstream`: 1. We need to remove all GTK gesture logic entirely and any other features that are not in the original Fingerworks Touchstream to prepare this project for it's role as a faithful recreation of the original Touchstream logic.
> I will need to make a Touchstream keymap / then we can remove Column tuning as well. We will need to scale the touchstream logic for the smaller AMT

`GlassToKey`: Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
> 0. TOGGLE for gestures? 1. remove extra Typing Tuning flags from logic

===

0. Update GTK Windows Driver instructions they should be dead simple now. 

1. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys