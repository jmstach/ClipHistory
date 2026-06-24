import AppKit
import CryptoKit
import Observation
import Security
import SwiftUI

// MARK: - Source app

struct SourceApp: Codable, Equatable {
    let bundleID: String
    let name:     String

    var icon: NSImage? { SourceApp.cachedIcon(for: bundleID) }

    private static let cache = NSCache<NSString, NSImage>()

    private static func cachedIcon(for bundleID: String) -> NSImage? {
        if let hit = cache.object(forKey: bundleID as NSString) { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(img, forKey: bundleID as NSString)
        return img
    }
}

// MARK: - Content kind

enum ClipContent: Equatable {
    case text(String)
    case image(Data)    // PNG thumbnail (≤ 480 px on longest side)
    /// File(s) copied from Finder. `urls` are written back verbatim on paste so the
    /// real files drop into the target; `thumbnail` is an optional PNG preview for
    /// image files (best of both worlds — paste the file, show the picture).
    case files(urls: [URL], thumbnail: Data?)
}

extension ClipContent: Codable {
    private enum CK: String, CodingKey { case type, text, imageData, filePaths }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .text(let t):
            try c.encode("text",  forKey: .type)
            try c.encode(t,       forKey: .text)
        case .image(let d):
            try c.encode("image", forKey: .type)
            try c.encode(d,       forKey: .imageData)
        case .files(let urls, let thumb):
            try c.encode("files", forKey: .type)
            try c.encode(urls.map { $0.path }, forKey: .filePaths)
            try c.encodeIfPresent(thumb, forKey: .imageData)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text":  self = .text(try c.decode(String.self, forKey: .text))
        case "image": self = .image(try c.decode(Data.self, forKey: .imageData))
        case "files":
            let paths = try c.decode([String].self, forKey: .filePaths)
            let thumb = try? c.decode(Data.self, forKey: .imageData)
            self = .files(urls: paths.map { URL(fileURLWithPath: $0) }, thumbnail: thumb)
        default:      throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                          debugDescription: "Unknown ClipContent type")
        }
    }
}

// MARK: - Clip item

struct ClipItem: Identifiable, Equatable {
    let id:        UUID
    let content:   ClipContent
    let date:      Date
    let sourceApp: SourceApp?
    var pinned:    Bool
    /// Original RTF representation for text items, captured at copy time so a
    /// styled paste can reproduce fonts/colour. nil when the source app put no
    /// rich text on the pasteboard. `content` stays the plain-text source of
    /// truth for search, preview, dedup, and the plain-paste path.
    let rtf:       Data?

    init(content: ClipContent, date: Date = .now, sourceApp: SourceApp? = nil, pinned: Bool = false, rtf: Data? = nil) {
        self.id        = UUID()
        self.content   = content
        self.date      = date
        self.sourceApp = sourceApp
        self.pinned    = pinned
        self.rtf       = rtf
    }

    var preview: String {
        switch content {
        case .text(let t):  return t.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:        return "Image"
        case .files(let urls, _):
            if urls.count == 1 { return urls[0].lastPathComponent }
            return "\(urls.count) files"
        }
    }

    var textContent: String? {
        if case .text(let t) = content { return t }
        return nil
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    var fileURLs: [URL]? {
        if case .files(let urls, _) = content { return urls }
        return nil
    }

    var fileThumbnail: Data? {
        if case .files(_, let thumb) = content { return thumb }
        return nil
    }
}

extension ClipItem: Codable {
    private enum CK: String, CodingKey { case id, content, date, sourceApp, text, pinned, rtf }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        try c.encode(id,        forKey: .id)
        try c.encode(content,   forKey: .content)
        try c.encode(date,      forKey: .date)
        try c.encodeIfPresent(sourceApp, forKey: .sourceApp)
        if pinned { try c.encode(true, forKey: .pinned) }
        try c.encodeIfPresent(rtf, forKey: .rtf)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        id        = try  c.decode(UUID.self,      forKey: .id)
        date      = try  c.decode(Date.self,      forKey: .date)
        sourceApp = try? c.decode(SourceApp.self, forKey: .sourceApp)
        pinned    = (try? c.decode(Bool.self,     forKey: .pinned)) ?? false
        rtf       = try? c.decode(Data.self,      forKey: .rtf)

        if let cont = try? c.decode(ClipContent.self, forKey: .content) {
            content = cont
        } else if let text = try? c.decode(String.self, forKey: .text) {
            content = .text(text)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .content, in: c,
                debugDescription: "ClipItem missing both 'content' and legacy 'text' key")
        }
    }
}

// MARK: - Store

@Observable
final class ClipboardStore {
    private(set) var items: [ClipItem] = []
    private var maxCount: Int

    var suppressNextPoll = false

    // Decoded-image cache — avoids re-inflating PNG bytes on every render pass.
    // Keyed by item UUID so entries are automatically orphaned when items are evicted.
    private let imageCache = NSCache<NSUUID, NSImage>()
    // AttributedString is a value type; box it so NSCache (which needs a class) can hold it.
    private final class StyledBox { let value: AttributedString; init(_ v: AttributedString) { value = v } }
    private let styledCache = NSCache<NSUUID, StyledBox>()

    private let saveURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json.enc")
    }()

    // AES-GCM key stored in the Keychain — never written to disk in plaintext.
    private let encryptionKey: SymmetricKey

    // Pending save work item — cancelled and rescheduled on each write so
    // rapid clipboard bursts collapse into a single disk write.
    private var pendingSave: DispatchWorkItem?

    init(maxCount: Int = 50) {
        self.maxCount      = maxCount
        self.encryptionKey = ClipboardStore.loadOrCreateKey()
        imageCache.countLimit = maxCount * 2
        load()
    }

    // MARK: - Image cache

    func cachedImage(for item: ClipItem) -> NSImage? {
        let key = item.id as NSUUID
        if let hit = imageCache.object(forKey: key) { return hit }
        // Serve raw image clips and image-file thumbnails from the same cache.
        let data: Data?
        switch item.content {
        case .image(let d):        data = d
        case .files(_, let thumb): data = thumb
        case .text:                data = nil
        }
        guard let data, let img = NSImage(data: data) else { return nil }
        imageCache.setObject(img, forKey: key)
        return img
    }

    // MARK: - Styled-text preview cache
    //
    // For text items captured with RTF, build a placement-agnostic rich preview:
    // express the source's bold / italic / mono as InlinePresentationIntent and keep
    // foreground colour, but carry NO font — so whatever `.font` the popup (tray card
    // or vertical row) applies still governs the size. Parsed once per item, cached.

    func styledPreview(for item: ClipItem) -> AttributedString? {
        guard let rtf = item.rtf else { return nil }
        let key = item.id as NSUUID
        if let hit = styledCache.object(forKey: key) { return hit.value }
        guard let parsed = try? NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        let built = Self.buildStyledPreview(parsed)
        styledCache.setObject(StyledBox(built), forKey: key)
        return built
    }

    private static func buildStyledPreview(_ input: NSAttributedString) -> AttributedString {
        // Trim leading/trailing whitespace to match the plain-text path. Whitespace
        // characters are single UTF-16 units, so counts map straight to an NSRange.
        let s = input.string
        let lead  = s.prefix(while: { $0.isWhitespace }).count
        let trail = s.reversed().prefix(while: { $0.isWhitespace }).count
        let len   = (s as NSString).length
        guard len - lead - trail > 0 else { return AttributedString() }
        let core  = input.attributedSubstring(
            from: NSRange(location: lead, length: len - lead - trail))

        var result = AttributedString()
        core.enumerateAttributes(in: NSRange(location: 0, length: core.length)) { attrs, range, _ in
            var piece = AttributedString((core.string as NSString).substring(with: range))

            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var intent: InlinePresentationIntent = []
            if traits.contains(.bold)      { intent.insert(.stronglyEmphasized) }
            if traits.contains(.italic)    { intent.insert(.emphasized) }
            if traits.contains(.monoSpace) { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }

            if let ns = attrs[.foregroundColor] as? NSColor {
                piece.foregroundColor = Color(nsColor: ns)
            }
            result.append(piece)
        }
        return result
    }

    // MARK: - Public API

    func pollClipboard(source: SourceApp? = nil) {
        if suppressNextPoll { suppressNextPoll = false; return }

        let pb = NSPasteboard.general

        // Skip items explicitly marked as sensitive by the source app
        // (1Password, Keychain prompts, etc. set this type on the pasteboard).
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if pb.types?.contains(concealedType) == true { return }

        // ── 1. File URLs from Finder ──────────────────────────────────────────
        let imageExts: Set<String> = ["jpg","jpeg","png","gif","tiff","tif",
                                      "webp","heic","bmp","avif"]
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            // The pasteboard's changeCount can tick without the file selection
            // changing (Handoff / Universal Clipboard re-syncs, apps re-asserting
            // the pasteboard), so skip if these exact files are already the most
            // recent clip — mirrors the text path's dedup.
            if items.first?.fileURLs == urls { return }
            // Keep the files so paste drops the real items; if any is an image,
            // thumbnail the first one for the preview.
            let thumb = urls.first(where: { imageExts.contains($0.pathExtension.lowercased()) })
                .flatMap { NSImage(contentsOf: $0)?.pngThumbnail() }
            add(ClipItem(content: .files(urls: urls, thumbnail: thumb), sourceApp: source))
            return
        }

        // ── 2. Direct image data ──────────────────────────────────────────────
        // Skip if the pasteboard also carries text — apps like Excel write both
        // a bitmap preview and structured text/CSV simultaneously. Preferring
        // text means cell content stays editable when pasted into a text editor.
        let pasteboardHasText = pb.string(forType: .string)
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        if !pasteboardHasText,
           let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img  = imgs.first(where: { $0.isValid }),
           let thumb = img.pngThumbnail() {
            add(ClipItem(content: .image(thumb), sourceApp: source))
            return
        }

        // ── 3. Text ───────────────────────────────────────────────────────────
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text != items.first?.textContent
        else { return }
        // Capture the rich representation if the source app provided one, so a
        // styled paste can reproduce it. RTF carries fonts/colour but not the
        // web-tracking metadata that HTML clipboard payloads can.
        let rtf = pb.data(forType: .rtf)
        add(ClipItem(content: .text(text), sourceApp: source, rtf: rtf))
    }

    func clearAll() {
        items = []
        imageCache.removeAllObjects()
        styledCache.removeAllObjects()
        flushSave()
    }

    func updateMaxCount(_ n: Int) {
        maxCount = n
        imageCache.countLimit = n * 2
        trimToLimit()
        scheduleSave()
    }

    func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        reorder()
        scheduleSave()
    }

    func remove(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: idx)
            imageCache.removeObject(forKey: id as NSUUID)
            styledCache.removeObject(forKey: id as NSUUID)
            scheduleSave()
        }
    }

    /// Move an unpinned clip to the top of the unpinned section — used when it's
    /// pasted, so most-recently-used bubbles up. Pinned clips keep their place,
    /// and the clip's timestamp is left as its cut/copy time (only order changes).
    func promoteToTop(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              !items[idx].pinned else { return }
        let boundary = items.firstIndex(where: { !$0.pinned }) ?? 0
        guard idx != boundary else { return }   // already top of the unpinned list
        let item = items.remove(at: idx)
        items.insert(item, at: boundary)
        scheduleSave()
    }

    func filtered(query: String, showImages: Bool = true) -> [ClipItem] {
        var result = items
        if !showImages { result = result.filter { !$0.isImage } }
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.preview.localizedCaseInsensitiveContains(query) ||
            ($0.sourceApp?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Private helpers

    private func add(_ item: ClipItem) {
        items.insert(item, at: 0)
        trimToLimit()
        scheduleSave()
    }

    private func trimToLimit() {
        let pinned   = items.filter { $0.pinned }
        let unpinned = items.filter { !$0.pinned }
        // Both pinned and unpinned capped independently at maxCount
        let trimmedPinned   = Array(pinned.prefix(maxCount))
        let trimmedUnpinned = Array(unpinned.prefix(maxCount))
        // Evict decoded images for removed items
        let kept = Set((trimmedPinned + trimmedUnpinned).map { $0.id })
        for item in items where !kept.contains(item.id) {
            imageCache.removeObject(forKey: item.id as NSUUID)
            styledCache.removeObject(forKey: item.id as NSUUID)
        }
        items = trimmedPinned + trimmedUnpinned
    }

    private func reorder() {
        let pinned   = items.filter { $0.pinned }
        let unpinned = items.filter { !$0.pinned }
        items = pinned + unpinned
    }

    // MARK: - Debounced save

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func flushSave() {
        pendingSave = nil
        // Snapshot on the main thread, then encrypt + write off it so a large
        // history never hitches the popup mid-animation.
        guard let plain = try? JSONEncoder().encode(items) else { return }
        let key = encryptionKey
        let url = saveURL
        ClipboardStore.saveQueue.async {
            guard let sealed = try? AES.GCM.seal(plain, using: key),
                  let combined = sealed.combined else { return }
            try? combined.write(to: url, options: .atomic)
        }
    }

    private static let saveQueue = DispatchQueue(label: "com.weiyuankong.cliphistory.save",
                                                 qos: .utility)

    // MARK: - Load (decrypts + falls back to legacy plaintext)

    private func load() {
        if let enc = try? Data(contentsOf: saveURL),
           let box = try? AES.GCM.SealedBox(combined: enc),
           let plain = try? AES.GCM.open(box, using: encryptionKey),
           let saved = try? JSONDecoder().decode([ClipItem].self, from: plain) {
            items = Array(saved.prefix(maxCount * 2))
            return
        }

        // Migrate legacy unencrypted history.json if present
        let legacyURL = saveURL.deletingLastPathComponent().appendingPathComponent("history.json")
        if let data  = try? Data(contentsOf: legacyURL),
           let saved = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = Array(saved.prefix(maxCount * 2))
            flushSave()                          // re-save encrypted immediately
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    // MARK: - Keychain key management

    // Opaque key for the Keychain item — deliberately NOT the bundle ID. It keeps
    // the original value so the encryption key (and thus existing history) survives
    // the rename to uk.stach.cliphistory; changing it would orphan the key.
    private static let keychainService = "com.weiyuankong.cliphistory"
    private static let keychainAccount = "history-encryption-key"

    private static func loadOrCreateKey() -> SymmetricKey {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData:  true,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }

        // Generate a fresh 256-bit key and store it
        let key     = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let add: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService,
            kSecAttrAccount:      keychainAccount,
            kSecValueData:        keyData,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Delete stale entry (wrong size) before inserting
        SecItemDelete(query as CFDictionary)
        SecItemAdd(add as CFDictionary, nil)
        return key
    }
}

// MARK: - NSImage thumbnail helper

private extension NSImage {
    func pngThumbnail(maxDimension: CGFloat = 480) -> Data? {
        var pixW = representations.map(\.pixelsWide).max() ?? 0
        var pixH = representations.map(\.pixelsHigh).max() ?? 0
        if pixW == 0 { pixW = Int(size.width)  }
        if pixH == 0 { pixH = Int(size.height) }
        guard pixW > 0, pixH > 0 else { return nil }

        let scale = min(maxDimension / CGFloat(pixW), maxDimension / CGFloat(pixH), 1.0)
        let newW  = max(1, Int(floor(CGFloat(pixW) * scale)))
        let newH  = max(1, Int(floor(CGFloat(pixH) * scale)))

        let thumb = NSImage(size: NSSize(width: newW, height: newH), flipped: false) { [self] rect in
            self.draw(in: rect)
            return true
        }

        guard let tiff   = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [.compressionFactor: 0.85])
    }
}
