## Rewrite
0. **Exclusive HID ownership plus our interpreter:** [IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen) supports the [SeizeDevice option](https://developer.apple.com/documentation/iokit/1556660-anonymous/kiohidoptionstypeseizedevice?changes=_2). This worked incredibly well this is our path forward here 
> NEXT TEST: Can I allow certain actions to pass through?

I would like to restructure our projects a bit:

`mac_gesturepad`: 
> Faithful recreation of Touchstream gesture logic, no keyboard for eventual port to `AppleMagicTouchstream`.

`mac_keyboard`: (AppleMagicTouchstream)
> I want to use this specifically as the new AMT-Touchstream project where we emulate the touchstream fully without any GTK (except what you find useful). We need to rename the folder and Project within it to `AppleMagicTouchstream`.

`mac`: GlassToKey. I will cherry-pick improvements to move here.

I guess at a certain point I want to start 2 seperate projects: 
1. a faithful recreation of TouchStream on AppleMagicTrackpad (`AppleMagicTouchstream`)
2. a rewrite of glass to key using as much of the touchstream gesture and gating logic as I find useful for my project. `GlassToKey`

===

`mac_gesturepad`: redesign GUI for better visual display of touches. 1. Remove `HID interfaces and report counts` and `Copy Diagnostics` 2. From `Live Values` show left touches on the left of the visualizer and right to the right. Maybe this can all happen under the trackpad visualizer instead of in a pop-out/modal like it is now. 3. lets move the Blackhold target info under the left/right trackpad selectors. 

`mac_keyboard`: 

`mac`(GlassToKey): Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)

===

0. Update GTK Windows Driver instructions they should be dead simple now. 

> Now that we have a much better idea of how Fingerworks did it.. how were gestures implemented in GTK? Can you give me a flowchart and maybe a comparison?

Path	What it could give us
Exclusive HID access	Take ownership of a selected device and interpret its reports ourselves. Apple provides a “seize device” option, but we must test whether it works across your trackpad’s input collections.

Our own DriverKit extension	Process incoming HID reports before dispatching system events. This requires hardware matching, signing and appropriate Apple entitlements.


a. I just dropped in a bunch of FingerWorks Touchstream SDK documentation.. do you think you can use any of it to improve how we differentiate between typing/mousing/gestures?

b. can we sink all 1 finger mouse movements of the Apple trackpad and only mouse when 2 fingers are dragged? This might be the magic bullet.. if we can have a "2 finger mouse mode" like the original.
> Emergency hatch: Can we SINK all mouse traffic and reimplement?

c. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet coule still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys

-------

