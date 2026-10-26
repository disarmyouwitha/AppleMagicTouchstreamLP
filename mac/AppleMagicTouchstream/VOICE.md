# Voice dictation

Voice is a configurable action under Shortcuts in Keymap Tuning Primary/Hold and
gesture Action menus, alongside Emoji and saved shortcuts such as Screenshot.
Screenshot, Voice and Emoji are built-in menu entries; they do not modify or
duplicate saved library entries. Modifiers appear in Shortcuts only when saved
by the user. Voice retains its original action identity and behavior.
Invoke it once to start listening, then again to finish and insert the
transcript into the original focused text field. A Hold assignment starts the
toggle after its recognition threshold; lifting does not stop dictation. Mode
Toggles shows status and a Cancel Voice button while active. Defaults do not change.

The source port is based on the retired macOS implementation at
[347d182](https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/blob/347d182/mac/GlassToKey/GlassToKey/GlassToKey/VoiceDictationManager.swift).
It uses AVAudioEngine, SFSpeechRecognizer and chunked partial/final transcripts.
Authorization is asynchronous instead of waiting on semaphores. State tokens
discard cancelled permission results, old chunk callbacks and delayed finalization.
Stopping ends audio immediately and allows up to 600 ms for the final transcript.
Finished recognition chunks restart while listening, with bounded error retries.

The first explicit Voice action requests Speech Recognition and Microphone access
as needed. Both purpose strings are present in Debug/Release Info.plist and the
signed app has the standard audio-input entitlement. These require user consent,
not Apple DriverKit approval. No microphone or recognizer is created at startup,
during settings editing, offline tests, or replay. Recognition uses the current
locale with en_US fallback. On-device recognition is preferred when supported;
Apple's speech service may process audio remotely otherwise. See Apple's
[Speech authorization guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).

The transcript is inserted as Unicode keyboard text only if the same non-secure
AX element remains focused. Changed focus discards the transcript, and secure
input is rejected. The recovered clipboard fallback is not restored, avoiding
clipboard replacement and delayed paste restoration. Text insertion uses the
existing Unicode dispatcher, with no ASCII normalization or character loss.
Self-editor Accessibility queries run on the main actor. No transcript is logged.

Release/suspend/ownership loss, processing resets and replay transitions cancel
the session without inserting text. A publication generation gate invalidates
already-scheduled Voice toggles during cancellation. Closing Config preserves the
running app and does not itself stop Voice. Existing gesture latches and output
eligibility gates apply; continuous Movement does not gain a Voice assignment.
Directional Voice assignments should have Repeat off, to avoid repeated toggling.

The legacy `Voice` and `VOICE` key labels are live again. Gesture assignments use
the `voice` action identity, exported with per-hand/Both settings. Key primary/hold
bindings use the existing `.voice` key action kind. The dispatch recorder represents
the command as `systemKey("voiceToggle")`; recording/replay sinks never instantiate
the speech manager, request permission or emit text.

Offline tests cover main-thread editor access, Voice key primary/hold dispatch,
settings/capture round-trips, transcript chunk assembly, completion exactly once,
permission cancellation and stale result rejection. Microphone quality and target
application text insertion require hardware testing: assign Voice, focus a test
document, trigger, speak, trigger again. Verify Cancel Voice, focus-change discard,
takeover release and a fresh session after cancellation.
