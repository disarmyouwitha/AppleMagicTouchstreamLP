# Mac architecture and adaptive hitmap review

Reviewed 2026-10-03. Scope: the macOS app, input bridge, and replay package.

## Recommendation

Keep the bridge, menu-bar application, layout editor, rendering, and capture format. Refactor the recognition core incrementally rather than rewrite the product. The valuable architectural change is to make production recognition independently testable and introduce a spatial decoder behind an explicit boundary.

The existing pipeline is OMSManager → InputRuntimeService → serial RuntimeCore queue → TouchProcessorEngine → DispatchService → KeyEventDispatcher. Autocorrect consumes dispatched key semantics afterward. A serial owner is a sensible latency-sensitive design; replacing it with actors everywhere is not inherently an improvement.

## Findings

2. **Time is only partially virtualized.** TouchProcessorEngine uses frame timestamps through currentTime(), while repeat scheduling uses DispatchTime.now() and asyncAfter. Fast replay and seek can therefore differ from real-time playback for timed behavior. Inject one logical clock and advance scheduled deadlines explicitly in offline tests.
3. **Domain types depend on the UI model.** TouchProcessorEngine aliases ContentViewModel.KeyBinding, Layout, and IntentDisplay. Move layout geometry, actions, configuration, and recognition events into a UI-independent core shared by the app and tests. The engine (~6,700 lines), view model (~4,400), and view (~5,800) contain distinct responsibilities worth separating, without changing them all at once.
4. **Autocorrect queue has a publication race.** AutocorrectEngine.enqueue increments writeIndex before assigning storage[slot]. A concurrently draining consumer may observe that index before its event exists. The atomics do not protect the following slot write, and overflow can overwrite a slot being consumed. Replace with a bounded synchronized queue; copy/drain events under the lock and perform spelling work outside it. This is a code-level finding, not a reproduced crash.
5. **Backpressure diagnostics are incomplete.** RuntimeCore.ingestLive enqueues a block per frame on its serial DispatchQueue. InputRuntimeService reports liveQueueDepth as zero. The upstream OMS buffer is bounded, but that does not bound the downstream queue. Measure age and depth, then design overflow recovery that releases held keys and resets contact state; arbitrarily dropping a release frame is unsafe.
6. **Spatial ambiguity is mostly discarded early.** Fixed geometry chooses a single binding; off-key release snapping uses Euclidean center distance. One alternate ASCII character may reach autocorrect, but there is no learned per-key distribution or general candidate score stream.
7. **Documentation has drifted.** AGENTS describes an actor, while production TouchProcessorEngine is a queue-confined class. README describes a 40 ms key buffer; IntentConfig currently defaults to 20 ms. Use executable configuration and production tests as the source of truth.

## What the hitmap means

The supplied screenshots visualize tap clusters and adjusted key regions. A useful recognition model assigns each key a learned center and spread. The visible key can remain stationary while the likely touch region changes.

Example: if intended F taps consistently land to the right, a touch near the F/G boundary may be more likely F for this user even when G's geometric center is closer. A language model adds another source of evidence: which sequence of letters is plausible in context.

Conceptually: score(key) = log P(touch | key, personal profile) + language weight × log P(key | context). Spatial-only recognition can start with equal key priors and needs no neural network or remote service. A two-dimensional Gaussian can represent both mean offset and an elongated, tilted tap cluster; regularization prevents sparse samples from producing overconfident distributions.

Google's published Gboard research evaluates personalized Gaussian offsets and optional covariance, including sample weighting and grouping to limit overfitting: https://research.google/pubs/spatial-model-personalization-in-gboard/ . Microsoft's earlier work combines spatial and language probabilities: https://www.microsoft.com/en-us/research/publication/language-modeling-for-soft-keyboards/ . Neither establishes the proprietary implementation behind the screenshots or the benefit achievable on these trackpads.

## Proposed implementation

### Production core and evaluation

Extract shared value types first. Give production recognition an injected clock and an event sink that records output without posting OS events. Run the same core in app and replay tests. Cover tap, release, hold, drag, overlapping typing, gesture suppression, modifier release, layer change, disconnect, and overflow recovery.

Record decision reasons and candidate scores so evaluation distinguishes wrong target, no target, intent rejection, pressure rejection, and dispatch loss. A spatial model cannot recover a tap that the intent state machine already discarded.

### Guided calibration and spatial decoding

Start with prompted intended keys, not inferred labels from emitted output. Collect a consistent contact feature (evaluate initial point, stable centroid, and release point on held-out samples). Use normalized coordinates with explicit orientation and physical aspect ratio. Exclude multi-contact gestures, holds, excessive motion, and invalid samples.

Fit bounded center offsets first with a prior toward original geometry. Add learned covariance only when enough data supports it. Keep independent profiles per device/side and geometry revision. Include model version and calibration snapshot in replay data. Changing the layout must invalidate or explicitly migrate its calibration.

Apply the decoder consistently at acquisition and release; merely replacing nearestSnapIndices leaves fixed-rectangle rejection paths in control. Keep modifiers, shortcuts, custom buttons, layers, and gesture regions on their explicit rules in the first release. Recalibration, disable, and reset should be visible controls.

Start in shadow mode: compute adaptive candidates and compare with current decisions without changing dispatched keys. Enable adaptive text targeting after held-out evidence supports it. Store compact sufficient statistics locally, with no raw typed text required for spatial calibration.

### Language feedback later

Preserve touch-to-character association and a small ranked candidate set through word completion. Use explicit correction evidence conservatively. Do not learn from every emitted key or silently treat every autocorrect result as ground truth: that creates a feedback loop reinforcing the model's own errors. Cursor movement, focus changes, shortcuts, and secure input must invalidate text-learning context.

Keep spelling and language work off the frame-processing queue. Codes, identifiers, and unusual names need an easy way to retain literal input.

## Acceptance measurements

Use separate calibration and evaluation sessions, split by session rather than adjacent frames. Compare current targeting, calibrated spatial targeting, and spatial-plus-language decoding on the same labeled taps. Report wrong-key rate, rejected intended taps, gesture false positives, corrections per character, and input-to-dispatch p50/p95/p99 latency. Add actual typing speed only after correctness measurement; synthetic improvement does not establish real-world speed gains.

## Baseline validation

- `swift test`: 10 tests passed.
- Debug macOS app `xcodebuild`: succeeded; bridge umbrella-header warnings remain.
- No physical typing study or latency profiling performed in this review.
- Existing user edits to the two keymap JSON files were left intact.
