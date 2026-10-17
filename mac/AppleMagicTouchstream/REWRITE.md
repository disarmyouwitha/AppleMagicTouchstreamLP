## Rewrite
`mac_gesturepad`: 

`mac_keyboard`: 

> Please continue our `Remaining Work` from FINDINGS.md


a. I just dropped in a bunch of FingerWorks Touchstream SDK documentation.. do you think you can use any of it to improve how we differentiate between typing/mousing/gestures?

b. can we sink all 1 finger mouse movements of the Apple trackpad and only mouse when 2 fingers are dragged? This might be the magic bullet.. if we can have a "2 finger mouse mode" like the original.
> Emergency hatch: Can we SINK all mouse traffic and reimplement?

c. Do you see any inefficiencies of how the dynamic keys work right now? If we could start over from scratch would you make any changes? (Because I am thinking of a ground-up re-write.
> I want to rebuild or at least relook at how the keys and keymap are done.. If I knew I wanted every key to be movable (yet coule still be associated with a column) would I have build it the same way? Can we PLEASE implement click&drag columns and/or keys?