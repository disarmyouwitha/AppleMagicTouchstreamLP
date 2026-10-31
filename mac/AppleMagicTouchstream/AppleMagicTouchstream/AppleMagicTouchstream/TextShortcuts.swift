import AppKit
import Carbon
import CoreGraphics
import Foundation
import Security
import os

/// Serialized actions contain only an opaque reference. Text never enters settings/captures.
enum TextShortcutReference {
    static let prefix = "TEXT_SHORTCUT:"
    static let maximumUTF8Bytes = 65_536
    static func id(from label:String) -> UUID? {
        guard label.hasPrefix(prefix) else { return nil }
        return UUID(uuidString:String(label.dropFirst(prefix.count)))
    }
    static func action(id:UUID) -> KeyAction {
        KeyAction(label:prefix+id.uuidString,keyCode:0,flags:0,kind:.textPaste)
    }
    static func valid(_ text:String) -> Bool { !text.isEmpty && text.utf8.count <= maximumUTF8Bytes }
    static func savedAction(text:String,name:String?,using store:any TextShortcutStoring) throws -> KeyAction {
        guard valid(text) else { throw TextShortcutStorageError.invalidText }
        var value = action(id:try store.save(text))
        value.customName = NamedShortcutStorage.normalizedName(name)
        return value
    }
}

protocol TextShortcutStoring:Sendable {
    func save(_ text:String) throws -> UUID
    func load(_ id:UUID) throws -> String
}

enum TextShortcutStorageError:Error,LocalizedError {
    case invalidText, unavailable
    var errorDescription:String? {
        switch self {
        case .invalidText: return "Enter text up to 64 KB."
        case .unavailable: return "Saved text is unavailable. Unlock your Keychain or re-enter the text."
        }
    }
}

/// Login Keychain encrypts the secret; the access list trusts only the creating app.
/// Every operation forbids authentication UI. No Keychain operation occurs in replay.
struct KeychainTextShortcutStore:TextShortcutStoring {
    static let shared = KeychainTextShortcutStore()
    private static let operationLock = NSLock()
    // This Developer ID app uses the login Keychain's app ACL, without new
    // access-group/provisioning requirements. Legacy Keychain UI suppression is
    // process-scoped: serialize it and restore the prior setting after each call.
    private static func withoutInteraction<T>(_ operation:() throws -> T) throws -> T {
        operationLock.lock(); defer { operationLock.unlock() }
        var allowed = DarwinBoolean(false)
        guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
            throw TextShortcutStorageError.unavailable
        }
        defer { _ = SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return try operation()
    }
    static let service = "ink.ranna.applemagictouchstream.text-shortcuts"
    static func query(id:UUID) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
         kSecAttrAccount as String:id.uuidString,kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
    }
    func save(_ text:String) throws -> UUID {
        guard TextShortcutReference.valid(text) else { throw TextShortcutStorageError.invalidText }
        let id = UUID()
        var access:SecAccess?
        guard SecAccessCreate("AppleMagicTouchstream saved text" as CFString,nil,&access) == errSecSuccess,
              let access else { throw TextShortcutStorageError.unavailable }
        var attributes = Self.query(id:id)
        attributes[kSecAttrAccess as String] = access
        attributes[kSecAttrLabel as String] = "AppleMagicTouchstream saved text"
        attributes[kSecValueData as String] = Data(text.utf8)
        let status = try Self.withoutInteraction { SecItemAdd(attributes as CFDictionary,nil) }
        guard status == errSecSuccess else { throw TextShortcutStorageError.unavailable }
        return id
    }
    func load(_ id:UUID) throws -> String {
        var attributes = Self.query(id:id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result:CFTypeRef?
        let status = try Self.withoutInteraction { SecItemCopyMatching(attributes as CFDictionary,&result) }
        guard status == errSecSuccess,
              let data = result as? Data, let text = String(data:data,encoding:.utf8),
              TextShortcutReference.valid(text) else { throw TextShortcutStorageError.unavailable }
        return text
    }
}

/// Exactly-once completion lets lifecycle cancellation resume the shared output pump
/// immediately, even if the Keychain worker is still finishing a read.
final class TextShortcutPasteRequest:@unchecked Sendable {
    private let lock:OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>
    init(completion:@escaping @Sendable (Bool) -> Void) { lock = OSAllocatedUnfairLock(initialState:completion) }
    var isActive:Bool { lock.withLock { $0 != nil } }
    func finish(_ pasted:Bool) {
        let callback = lock.withLock { value in let callback = value; value = nil; return callback }
        callback?(pasted)
    }
}

final class TextShortcutPasteOutput:@unchecked Sendable {
    static let shared = TextShortcutPasteOutput()
    private struct State { var generation:UInt64 = 0; var requests:[UUID:TextShortcutPasteRequest] = [:] }
    private let state = OSAllocatedUnfairLock(initialState:State())
    private let worker = DispatchQueue(label:"AppleMagicTouchstream.savedText",qos:.userInitiated)
    var generation:UInt64 { state.withLock { $0.generation } }
    func cancel() {
        let requests = state.withLock { value in
            value.generation &+= 1
            let requests = Array(value.requests.values); value.requests.removeAll(); return requests
        }
        for request in requests { request.finish(false) }
    }
    func isCurrent(_ value:UInt64) -> Bool { generation == value }
    func request(_ label:String,generation:UInt64,completion:@escaping @Sendable (Bool)->Void = { _ in }) {
        guard let id = TextShortcutReference.id(from:label) else { completion(false); return }
        let requestID = UUID()
        let request = TextShortcutPasteRequest { [weak self] pasted in
            self?.state.withLock { _ = $0.requests.removeValue(forKey:requestID) }
            completion(pasted)
        }
        let accepted = state.withLock { value in
            guard value.generation == generation else { return false }
            value.requests[requestID] = request; return true
        }
        guard accepted else { request.finish(false); return }
        Task { @MainActor in
            guard request.isActive, self.isCurrent(generation),
                  let destination = FocusedTextDestination.capture(rejectSecureInput:false) else { request.finish(false); return }
            self.worker.async {
                guard request.isActive, self.isCurrent(generation),
                      let text = try? KeychainTextShortcutStore.shared.load(id) else { request.finish(false); return }
                Task { @MainActor in
                    guard request.isActive, self.isCurrent(generation),
                          let current = FocusedTextDestination.capture(rejectSecureInput:false),
                          destination.matches(current,rejectSecureInput:false) else { request.finish(false); return }
                    let board = NSPasteboard.general
                    let item = NSPasteboardItem()
                    item.setString(text,forType:.string)
                    item.setData(Data(),forType:NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                    board.clearContents()
                    guard board.writeObjects([item]) else { request.finish(false); return }
                    let changeCount = board.changeCount
                    DispatchService.shared.performPreparedTextPaste(pid:destination.pid,generation:generation) { request.finish($0) }
                    DispatchQueue.main.asyncAfter(deadline:.now()+30) {
                        if board.changeCount == changeCount { board.clearContents() }
                    }
                }
            }
        }
    }
}
