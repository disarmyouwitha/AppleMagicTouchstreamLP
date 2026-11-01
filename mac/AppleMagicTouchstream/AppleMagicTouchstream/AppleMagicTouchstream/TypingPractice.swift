import AppKit
import SwiftUI

/// Practice reads only its focused text field; it never observes or posts input.
struct TypingPracticeSession {
    enum Mode:String,CaseIterable,Identifiable {
        case words = "Words", steno = "Steno drills", custom = "Custom"
        var id:String { rawValue }
    }
    static let commonWords = "the be to of and a in that have for it not on with he as you do at this but his by from they we say her she or an will my one all would there their what so up out if about who get which go me when make can like time no just him know take people into year your good some could them see other than then now look only come its over think also back after use two how our work first well way even new want because any these give day most us water home hand place small great again around every word light right left read write world school still long little help sound move turn play learn".split(separator:" ").map(String.init)
    // Short English drills work with the learner's own Plover dictionary/theory.
    static let stenoWords = "cat cats cap caps tap taps pat pats bat bats mat mats sat sad set sit pin pins pit pits tip tips top tops pot pots stop stops star stars start starts art arts part parts cart carts car cars bar bars far farm park parks hard heart hearts red read road rat rats rate rates late light lights night nights net nets ten tent tents test tests best bet bets bed beds bend bent rest rent run runs sun fun fan fans can cans pan pans plan plans plant plants sand hand hands land lands stand stands stone stones tone tones train trains rain rains brain brains".split(separator:" ").map(String.init)

    var prompt:String
    var input = ""
    var startedAt:Date?
    var finishedAt:Date?
    let ignoresCase:Bool

    init(prompt:String,ignoresCase:Bool = false) { self.prompt = prompt; self.ignoresCase = ignoresCase }
    static func words(from text:String) -> [String] {
        Array(text.split(whereSeparator: { $0.isWhitespace }).prefix(500).map { String($0.prefix(40)) })
    }
    static func prompt<R:RandomNumberGenerator>(mode:Mode,count:Int,custom:String,using random:inout R) -> String {
        let source = mode == .custom ? words(from:custom):mode == .steno ? stenoWords:commonWords
        guard !source.isEmpty else { return "" }
        var result:[String] = []
        for _ in 0..<min(100,max(1,count)) {
            let choices = source.count > 1 ? source.filter {$0 != result.last}:source
            result.append(choices.randomElement(using:&random) ?? source[0])
        }
        return result.joined(separator:" ")
    }
    private func compared(_ text:String) -> String {
        let normalized = text.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
        return ignoresCase ? normalized.lowercased():normalized
    }
    var comparisonInput:String { compared(input) }
    var isComplete:Bool { !prompt.isEmpty && compared(input) == compared(prompt) }
    mutating func update(_ text:String,at now:Date) {
        guard finishedAt == nil else { return }
        input = String(text.prefix(6000))
        if startedAt == nil && !input.isEmpty { startedAt = now }
        if startedAt != nil && isComplete { finishedAt = now }
    }
    var correctCharacters:Int {
        zip(compared(input),compared(prompt)).reduce(0) {$0+($1.0 == $1.1 ? 1:0)}
    }
    var accuracy:Double {
        let count = compared(input).count
        return count == 0 ? 100:Double(correctCharacters)/Double(count)*100
    }
    var progress:Double {
        let count = compared(prompt).count
        return count == 0 ? 0:min(1,Double(correctCharacters)/Double(count))
    }
    func elapsed(at now:Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0,(finishedAt ?? now).timeIntervalSince(startedAt))
    }
    func wpm(at now:Date) -> Double {
        let seconds = elapsed(at:now)
        return seconds < 1 ? 0:Double(correctCharacters)/5/(seconds/60)
    }
}

struct TypingPracticePanel: View {
    @Binding var freeText:String
    @State private var practicing = false
    @State private var mode:TypingPracticeSession.Mode = .words
    @State private var count = 25
    @State private var custom = ""
    @State private var session = TypingPracticeSession(prompt:"")
    @State private var focusToken = UUID()

    init(freeText:Binding<String>,initialPractice:Bool = false,initialMode:TypingPracticeSession.Mode = .words) {
        _freeText = freeText
        _practicing = State(initialValue:initialPractice)
        _mode = State(initialValue:initialMode)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker("Typing area",selection:$practicing) {
                    Text("Free type").tag(false)
                    Text("Practice").tag(true)
                }.pickerStyle(.segmented).frame(width:230)
                if practicing {
                    Picker("Practice",selection:$mode) {
                        ForEach(TypingPracticeSession.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width:220)
                    Picker("Words",selection:$count) { ForEach([10,25,50,100],id:\.self) { Text("\($0)").tag($0) } }.frame(width:145)
                }
                Spacer(minLength:8)
                if practicing {
                    Button(action:restart) { Label("New drill",systemImage:"arrow.clockwise") }
                        .disabled(mode == .custom && TypingPracticeSession.words(from:custom).isEmpty)
                }
            }
            if practicing {
                if mode == .custom {
                    TextField("Words to practice, separated by spaces",text:$custom)
                        .textFieldStyle(.roundedBorder).onSubmit(restart)
                    Text("Edit the list, then choose New drill.").font(.caption).foregroundStyle(.secondary)
                }
                if session.prompt.isEmpty {
                    Text("Add some words to create a drill.").foregroundStyle(.secondary)
                } else {
                    Text(highlightedPrompt).font(.system(size:18,design:.monospaced))
                        .lineSpacing(6).frame(maxWidth:.infinity,alignment:.leading)
                        .accessibilityLabel("Practice prompt: \(session.prompt)")
                        .overlay {
                            PracticePromptInput(text:Binding(get:{session.input},set:{session.update($0,at:.now)}),
                                enabled:session.finishedAt == nil,focusToken:focusToken)
                        }
                        .help("Click the prompt to focus, then type. Backspace and Plover corrections work here.")
                    ProgressView(value:session.progress).accessibilityLabel("Practice progress")
                    TimelineView(.periodic(from:.now,by:0.5)) { context in
                        HStack(spacing:20) {
                            metric("WPM",value:session.wpm(at:context.date).formatted(.number.precision(.fractionLength(0))))
                            metric("Accuracy",value:session.accuracy.formatted(.number.precision(.fractionLength(0)))+"%")
                            metric("Time",value:"\(Int(session.elapsed(at:context.date)))s")
                            Spacer()
                            Text(session.finishedAt != nil ? "Complete!":session.startedAt == nil ? "Start typing to begin":"Keep going")
                                .foregroundStyle(session.finishedAt != nil ? Color.green:Color.secondary)
                        }
                    }
                    Text(mode == .steno ? "Use Plover’s translated output here. Capitalization is ignored; corrections and backspaces update the score.":"Click the prompt and type. Corrections are allowed; WPM and accuracy reflect your current text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                TextEditor(text:$freeText).font(.system(.body,design:.monospaced)).frame(height:100)
                    .overlay(RoundedRectangle(cornerRadius:6).stroke(Color.secondary.opacity(0.6)))
                    .accessibilityLabel("Free typing input")
            }
        }
        .onAppear { if practicing && session.prompt.isEmpty { restart() } }
        .onChange(of:practicing) { value in if value && session.prompt.isEmpty { restart() } }
        .onChange(of:mode) { _ in restart() }
        .onChange(of:count) { _ in restart() }
    }
    private func metric(_ label:String,value:String) -> some View {
        VStack(alignment:.leading,spacing:2) { Text(value).font(.headline).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
    private var highlightedPrompt:AttributedString {
        var result = AttributedString()
        let input = Array(session.comparisonInput)
        for (index,character) in session.prompt.enumerated() {
            var part = AttributedString(String(character))
            if index < input.count { part.foregroundColor = input[index] == character ? .green:.red }
            else { part.foregroundColor = .secondary }
            result.append(part)
        }
        return result
    }
    private func restart() {
        var random = SystemRandomNumberGenerator()
        session = TypingPracticeSession(prompt:TypingPracticeSession.prompt(mode:mode,count:count,custom:custom,using:&random),ignoresCase:mode == .steno)
        focusToken = UUID()
    }
}

/// A normal focused NSTextView preserves Unicode, backspace and AX replacement
/// for Plover; only its drawing is hidden behind the highlighted prompt.
struct PracticePromptInput:NSViewRepresentable {
    @Binding var text:String
    let enabled:Bool
    let focusToken:UUID
    func makeCoordinator() -> Coordinator { Coordinator(text:$text) }
    func makeNSView(context:Context) -> PromptTextView {
        let view = PromptTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.drawsBackground = false
        view.textColor = .clear
        view.insertionPointColor = .clear
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.setAccessibilityLabel("Practice input")
        return view
    }
    func updateNSView(_ view:PromptTextView,context:Context) {
        context.coordinator.text = $text
        view.isEditable = enabled
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location:(text as NSString).length,length:0))
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isEditable, let window = view.window, window.isKeyWindow else { return }
                window.makeFirstResponder(view)
            }
        }
    }
    @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
        var text:Binding<String>
        var focusToken:UUID?
        init(text:Binding<String>) { self.text = text }
        func textDidChange(_ notification:Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
    final class PromptTextView:NSTextView {
        override func draw(_ dirtyRect:NSRect) {}
        override func mouseDown(with event:NSEvent) {
            guard isEditable else { return }
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location:(string as NSString).length,length:0))
        }
    }
}
