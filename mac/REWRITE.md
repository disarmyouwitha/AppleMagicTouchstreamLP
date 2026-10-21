===
## TELL CODEX:
> `?` Can you use gesturepad or AppleMagicTouchstream for your reverse engineering efforts? What would allow you to do that? The trackpads are a little smaller but I set up a scaled down keymap that matches? ('TouchStream' layout)

===

> Do you think it would be possible to implement "trackpad takeover" without the button (on startup) and to automatically change the FLTR depending on what is selected in the list without locking it?

Absolutely possible. The button isn't part of the mechanism. It's just what currently initiates the transition between normal monitoring and FLTR capture.

You could make takeover a mode of the application:
enum CaptureMode {
    case observe
    case exclusive
}

On launch:
1. Restore the user's selected trackpads and preferred capture mode.
2. Enumerate and validate available devices.
3. Start ordinary monitoring for devices in observation mode.
4. Start FLTR capture for devices in exclusive mode.
5. Keep the same release safeguards for sleep, termination and disconnect.


The catch is that an app can now disable its user's trackpad as soon as it launches. I'd make automatic takeover opt-in, preserve a keyboard-only emergency release shortcut.

===

> Could we possibly reverse the pointer acceleration from my installed drivers?
> I am thinking 1 finger = typing; 2 fingers = mouse movement. (pinch zoom too); 4 fingers scroll instead. Like the touchstream!

YES! We could absolutely investigate Apple's pointer acceleration algorithm, and there's already published research on reconstructing it. 🦑

And your proposed finger mapping is exactly the direction I'd take for GlassToKey.

In fact, I found something delightful: the original FingerWorks TouchStream documentation confirms almost exactly what you're describing!

| Fingers                 | TouchStream behavior | GlassToKey        |
| ----------------------- | -------------------- | ----------------- |
| 1                       | Typing               | Typing and chords |
| 2 adjacent              | Pointer movement     | Pointer movement  |
| 2 moving apart/together | Gesture-dependent    | Pinch-to-zoom     |
| 3                       | Drag / select        | Dragging          |
| 4                       | Scrolling            | Scrolling         |

The original TouchStream documentation specifies two fingers for pointing, three for dragging, and four for scrolling. It even describes how the system distinguishes gestures based on which fingers initially land together.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://device.report\&sz=32)

device.report

+1



This is a much cleaner gesture vocabulary than trying to make one- and two-finger motions serve both typing and mouse functions.

You could reserve single-finger contacts entirely for typing while letting simultaneous two-finger contacts initiate pointer mode. That largely eliminates the conflict we were worrying about.

There are still interesting edge cases, particularly determining when two independent typing contacts become a pointer gesture, but they're solvable with timing, proximity, movement and gesture latching.

## 1. We might not even need to reverse-engineer it!

I found the actual open-source acceleration implementation in Apple's `IOHIDFamily` repository.

[IOHIDPointerScrollFilter.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDEventSystemPlugIns/IOHIDPointerScrollFilter.cpp?utm_source=chatgpt.com)

Decides whether pointer events get accelerated, selects the acceleration algorithm, and reads the relevant device properties.

[IOHIDAcceleration.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDEventSystemPlugIns/IOHIDAcceleration.cpp?utm_source=chatgpt.com)

Calculates movement velocity from X/Y deltas and timing, obtains the acceleration multiplier, and applies it to movement.

[IOHIDAccelerationAlgorithm.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp?utm_source=chatgpt.com)

Implements both table-based and parametric acceleration curves, including interpolation and polynomial calculations.

I inspected the source directly. The modern filter attempts a parametric acceleration curve first, then falls back to a table-based curve. The calculations account for device resolution, report rate, and the selected tracking-speed setting.

And [libpointing](https://github.com/INRIA/libpointing?utm_source=chatgpt.com) has already done much of the academic work to reconstruct and compare Apple's pointing transfer functions.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



There's also practical reverse-engineering work in [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/PointerSpeed/PointerSpeed.m?utm_source=chatgpt.com), including retrieving and modifying acceleration curve parameters.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



The important caveat: we haven't established that these exact source revisions reproduce the full Magic Trackpad pointer behavior on your macOS 15.7.4 installation. Apple's proprietary multitouch processing could add transformations before the general HID acceleration stage.

But this gives Codex an excellent starting point.

## 2. How I'd reproduce the Apple feel

I'd implement a pointer engine with a pluggable acceleration function.

The fundamental calculation would be:

\\[ \Delta\mathbf{cursor}=G(v)\cdot\Delta\mathbf{finger} \\]

Where \\(G(v)\\) is the acceleration multiplier at a given finger speed.

The trick is making sure the units, report timing, rounding, and acceleration curve agree with the native behavior.

I'd start by measuring your actual trackpad:

1. Run in ordinary monitoring mode without FLTR.
2. Record the physical finger displacement and timestamps from `MTTouch`.
3. Record the actual cursor displacement produced by macOS.
4. Repeat at different speeds and tracking-speed preferences.
5. Compare those measurements against Apple's published acceleration algorithm.

That last step tells you how much of the real Magic Trackpad behavior the published implementation explains.

Then use the closest matching algorithm as GlassToKey's Apple Default profile.

Importantly, you can collect the contact data and native cursor movement during the same recording session. You don't have to infer Apple's response from finger movement alone.

## 3. Your new gesture mapping solves a lot

For the two-finger pointer, I'd use the centroid of the contacts.

\\[ C=\frac{P_1+P_2}{2} \\]

Moving both fingers together moves the centroid, while spreading the fingers apart changes their separation.

That gives you two useful signals:

Pointer movement

Centroid changes, separation stays similar

Pinch / zoom

Separation changes, centroid stays similar

Instead of treating two-finger movement and pinch as unrelated recognizers competing for the same contacts, build one two-contact gesture recognizer that understands translation and scaling.

You could even support simultaneous translation and pinch, or latch the dominant gesture once it crosses a threshold.

## 4. One subtle problem I'd tackle early

Two fingers touching doesn't always mean the user intends to move the mouse.

If you're typing quickly, there will be moments when two fingertips contact the same pad at once. This is especially true when you're implementing multi-finger keyboard chords.

I'd distinguish landing from movement.

Two fingers land and immediately release on key locations? Likely typing.

Two adjacent fingers land together and move coherently? Pointer gesture.

Four fingers land together and translate? Scroll gesture.

I'd also allow a short gesture-formation window so that four fingers landing in rapid succession don't accidentally initiate the two-finger pointer first.

Once a gesture is recognized, latch it. That is particularly important for your TouchStream-style behavior.

## What I'd ask Codex to do first

Rather than reverse-engineering another private binary, I'd give Codex the three Apple files above and ask it to implement a standalone test harness for the pointer acceleration algorithm.

The test should accept recorded contact deltas, timestamps, and tracking settings, then output predicted cursor deltas. Compare those predictions against cursor movement recorded with native input enabled.

That gives you a measurable answer to "How close can we get to Apple's default?" before committing the implementation to GlassToKey.

I'm increasingly convinced that this is the right architecture: preserve the TouchStream gesture vocabulary, use Apple-like movement as the default, and expose custom pointer curves for people who want them.

And the best part is that you've already found the hard boundary to cross. You can now treat the two trackpads as raw input surfaces, not devices whose predefined gestures you're obligated to accommodate.

You finally get to design the input language instead of negotiating with macOS over every finger. 💙

===

`GlassToKey`:
0. Fit layout to image
1. Update GTK Windows Driver instructions they should be dead simple now.
2. DecalGirl left and right pads


`AppleMagicTouchstream`: 
0. Copy touchstream Layout from AMT to GTK!


`GesturePad`:
0. implement 2finger synthetic mouse, and force click = click

===

`GlassToKey`: 
0. Can we use the Velocity data to tell when we are typing vs mousing? It seems like a stronger signal than 3mm intent classifier. I would like maybe 3 options to switch between to test feel: 1. Current setup. 2. 3mm intent classifier 3. Velocity/Pressure/Timing based. (Let me know if we need to do a typing test to get data on this)
* We should still work on this independently of Trackpad Takeover (which should be an *Preferred* Option, but an option)
1. a. TOGGLE for gestures? b. remove extra Typing Tuning flags from logic
2. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet could still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?