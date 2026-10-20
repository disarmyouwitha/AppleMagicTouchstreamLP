# Native filter experiment in GesturePad

Implementation and discovery details: [TRACKPAD_TAKEOVER.md](TRACKPAD_TAKEOVER.md).

This is an explicit 15-second Bluetooth test. The previous custom DriverKit
implementation has been removed from GesturePad and AppleMagicTouchstream. It uses the private MultitouchSupport FLTR mode already exercised by the
standalone probe. It is not a production default or a compatibility guarantee.
No restricted entitlement, provisioning profile, helper or elevation is added for
this experiment.

1. Quit other trackpad apps. Keep another mouse
   available. Open the newly built GesturePad and select your Bluetooth pad(s).
2. Under Left Trackpad, find **Native filter experiment**. Press the **Test
   [serial] · 15s** button for one pad. Only that selected native device is filtered.
3. Move one finger continuously. Its native cursor should stop while its contacts
   and contact paths continue updating. Do not move another mouse while assessing
   the sampled cursor span. The other pad should retain normal input.
4. After 15 seconds, native input should resume and contacts should keep updating.
   **Release test**, the menu's **Release Trackpads**, or **Ctrl–Option–R** ends early.
5. Copy the selectable status text if anything fails. Note whether contacts, native
   cursor, scrolling, and click recover, and whether the other pad was unaffected.
   Repeat once to check reuse. Start with movement only before testing clicks.

The status shows native callback counts, contact-bearing frames, sampled cursor
span, time remaining, recovery status and remaining owned filter-client count.
Cursor samples are periodic observations, not proof that no intermediate motion
occurred. Human observation remains part of the test.

The bridge rejects built-in/USB devices, unsupported product/vendor/driver types,
inactive selections, and devices already owned by a filter client. It verifies its
own FilterEnabled client after starting. The 15-second deadline runs on the native
state queue, independently of the UI timer. Release restores ordinary callback
mode; sleep, replay, configuration close and exit follow existing cleanup paths.
Refresh and selection are locked during the experiment. Legacy experiments cannot
start concurrently. No synthetic pointer/click output is added.

Hardware update, 2026-10-19: after testing the integrated GesturePad build, the
user reported that it works “phenomenally well.” The GUI test path contains no sudo
or elevation step. No new integrated-run diagnostic log was supplied; repeated
lifecycle tests and other machines remain follow-up validation. A failed start is
reported and rolled back.
