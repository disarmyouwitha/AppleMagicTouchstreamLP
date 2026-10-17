## Rewrite
0. Sorry you got interrupted because I ran out of credits. Please continue! I did get to look over our research and I think it's worth pointing out that I don't think the AMT does gesture recognition like the touchstream, it is just reporting contact data. I think gestures are interpreted by the operating system. I mostly just want to confirm WHAT data we are getting from the AMT and how it compares to the data the touchstream logic expects. 

1. Lets test this immediately - maybe add a toggle in our Gesture_pad project to see if we can swallow all inputs from the trackpad and blackhole them. 
**Exclusive HID ownership plus our interpreter:** [IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen) supports the [SeizeDevice option](https://developer.apple.com/documentation/iokit/1556660-anonymous/kiohidoptionstypeseizedevice?changes=_2). Apple documents that it prevents other clients/system events from that HID device. This is a concrete API to investigate before replacing the whole driver. Success, report availability, affected HID collections and suppression of all corresponding pointer/scroll/gesture output must be tested on the actual model/OS/transport. Opening one collection is not proof all input routes are controlled. 

2. I made a friend on reddit who made their own PCB with the processor you keep mentioning.. they said they were able to get everything pre-soldered which is dope.. maybe we can check out his kicad for ideas? it is MX spaced which sucks, lol. 
[https://www.reddit.com/r/ErgoMechKeyboards/comments/1x8d8sb/comment/phc8mcc/?context=1&screen_view_count=2](https://www.reddit.com/r/ErgoMechKeyboards/comments/1x8d8sb/comment/phc8mcc/?context=1&screen_view_count=2)

[https://github.com/WillACosta/wlfkbd/](https://github.com/WillACosta/wlfkbd/)

What is next? Do we talk Processor first? Or do you want to infer those copper traces from the texture? It looks like you should be able to. 

`mac_gesturepad`: 

`mac_keyboard`: Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal that 3mm intent classifier.

0. Update GTK Windows Driver instructions they should be dead simple now.

1. The "handedness" of the finger recognizer is interesting.. on the touchstream they knew which hand was which.. Apple seems to recognize which finger orientation is which hand and updates contacts accordingly. 

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

I guess at a certain point I want to start 2 seperate projects: 
1. a faithful recreation of TouchStream on AppleMagicTrackpad (AppleMagicTouchstreamLP)
2. a rewrite of glass to key using as much of the touchstream gesture and gating logic as I find useful for my project.