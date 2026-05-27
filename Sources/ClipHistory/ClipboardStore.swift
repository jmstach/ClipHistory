import AppKit
import Observation

// MARK: - Source app

struct SourceApp: Codable, Equatable {
    let bundleID: String
    let name:     String

    /// App icon, looked up once from NSWorkspace and cached in memory.
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

    init(content: ClipContent, date: Date = .now, sourceApp: SourceApp? = nil, pinned: Bool = false) {
        self.id        = UUID()
        self.content   = content
        self.date      = date
        self.sourceApp = sourceApp
        self.pinned    = pinned
    }

    /// One-line string used for display and search.
    var preview: String {
        switch content {
        case .text(let t): return t.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:       return "Image"
        }
    }

    /// Convenience accessor — nil for image items.
    var textContent: String? {
        if case .text(let t) = content { return t }
        return nil
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }
}

// Codable with v1 migration: old format stored `text: String` at the top level.
extension ClipItem: Codable {
    private enum CK: String, CodingKey { case id, content, date, sourceApp, text, pinned }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        try c.encode(id,        forKey: .id)
        try c.encode(content,   forKey: .content)
        try c.encode(date,      forKey: .date)
        try c.encodeIfPresent(sourceApp, forKey: .sourceApp)
        if pinned { try c.encode(true, forKey: .pinned) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        id        = try  c.decode(UUID.self,    forKey: .id)
        date      = try  c.decode(Date.self,    forKey: .date)
        sourceApp = try? c.decode(SourceApp.self, forKey: .sourceApp)
        pinned    = (try? c.decode(Bool.self,   forKey: .pinned)) ?? false

        // New format first; fall back to v1 plain `text` field.
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

    /// Set to true before writing to the pasteboard yourself so the monitor
    /// skips the next change (prevents re-inserting what we just pasted).
    var suppressNextPoll = false

    private let saveURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init(maxCount: Int = 15) {
        self.maxCount = maxCount
        load()
    }

    // MARK: - Public API

    func pollClipboard(source: SourceApp? = nil) {
        if suppressNextPoll { suppressNextPoll = false; return }

        let pb = NSPasteboard.general

        // ── 1. File URLs from Finder ──────────────────────────────────────────
        // MUST come before the NSImage path. When Finder copies a file,
        // readObjects(NSImage) returns the Finder document icon, NOT the image
        // contents. We intercept file URLs first and load the actual file with
        // NSImage(contentsOf:) so we store real pixels, not an icon.
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
            // File URLs present but none are images → skip; don't store a path/
            // filename string as though the user copied meaningful text.
            return
        }

        // ── 2. Direct image data ──────────────────────────────────────────────
        // Only reached when the pasteboard has NO file URLs. Handles screenshots
        // (TIFF from Cmd+Shift+4), "Copy Image" in browsers, Preview, etc.
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
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
        add(ClipItem(content: .text(text), sourceApp: source))
    }

    func clearAll() {
        items = []
        save()
    }

    func updateMaxCount(_ n: Int) {
        maxCount = n
        let pinned   = items.filter { $0.pinned }
        var unpinned = items.filter { !$0.pinned }
        if unpinned.count > n {
            unpinned = Array(unpinned.prefix(n))
            items = pinned + unpinned
            save()
        }
    }

    func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        // Pinned items always sit above unpinned items in the list.
        let pinned   = items.filter { $0.pinned }
        let unpinned = items.filter { !$0.pinned }
        items = pinned + unpinned
        save()
    }

    /// Shared filter used by PopupView and PopupWindowController so their
    /// item indices are always in sync.
    func filtered(query: String, showImages: Bool = true) -> [ClipItem] {
        var result = items
        if !showImages { result = result.filter { !$0.isImage } }
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.preview.localizedCaseInsensitiveContains(query) ||
            ($0.sourceApp?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Private

    private func add(_ item: ClipItem) {
        items.insert(item, at: 0)
        // Pinned items are never evicted; only unpinned items respect maxCount.
        let pinned   = items.filter { $0.pinned }
        var unpinned = items.filter { !$0.pinned }
        if unpinned.count > maxCount { unpinned = Array(unpinned.prefix(maxCount)) }
        items = pinned + unpinned
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data  = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([ClipItem].self, from: data)
        else { return }
        items = Array(saved.prefix(maxCount))
    }
}

// MARK: - NSImage thumbnail helper

private extension NSImage {
    /// Returns PNG data resized so the longest side is ≤ maxDimension.
    ///
    /// Uses pixel dimensions from representations (not `size`) so clipboard
    /// images that report size=(0,0) until rendered are handled correctly.
    func pngThumbnail(maxDimension: CGFloat = 480) -> Data? {
        // Prefer pixel dimensions from representations over `size`
        // (clipboard NSImages — screenshots, browser images — may report
        //  size=(0,0) until their backing store is actually rendered).
        var pixW = representations.map(\.pixelsWide).max() ?? 0
        var pixH = representations.map(\.pixelsHigh).max() ?? 0

        // Fall back to the logical size expressed in points
        if pixW == 0 { pixW = Int(size.width)  }
        if pixH == 0 { pixH = Int(size.height) }

        guard pixW > 0, pixH > 0 else { return nil }

        let scale = min(maxDimension / CGFloat(pixW), maxDimension / CGFloat(pixH), 1.0)
        let newW  = max(1, Int(floor(CGFloat(pixW) * scale)))
        let newH  = max(1, Int(floor(CGFloat(pixH) * scale)))

        // NSImage(size:flipped:drawingHandler:) sets up a proper offscreen
        // graphics context, which is required to force-render lazy clipboard
        // images (TIFF, synthesised from file-URL copies, etc.).
        let thumb = NSImage(size: NSSize(width: newW, height: newH), flipped: false) { [self] rect in
            self.draw(in: rect)
            return true
        }

        guard let tiff   = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [.compressionFactor: 0.85])
    }
}
