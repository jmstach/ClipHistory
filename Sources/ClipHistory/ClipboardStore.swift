import AppKit
import CryptoKit
import Observation
import Security

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
}

extension ClipContent: Codable {
    private enum CK: String, CodingKey { case type, text, imageData }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .text(let t):
            try c.encode("text",  forKey: .type)
            try c.encode(t,       forKey: .text)
        case .image(let d):
            try c.encode("image", forKey: .type)
            try c.encode(d,       forKey: .imageData)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text":  self = .text(try c.decode(String.self, forKey: .text))
        case "image": self = .image(try c.decode(Data.self, forKey: .imageData))
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
        case .text(let t): return t.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:       return "Image"
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
        guard case .image(let data) = item.content,
              let img = NSImage(data: data) else { return nil }
        imageCache.setObject(img, forKey: key)
        return img
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
            for url in urls where imageExts.contains(url.pathExtension.lowercased()) {
                if let img = NSImage(contentsOf: url), let thumb = img.pngThumbnail() {
                    add(ClipItem(content: .image(thumb), sourceApp: source))
                    return
                }
            }
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
            scheduleSave()
        }
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
