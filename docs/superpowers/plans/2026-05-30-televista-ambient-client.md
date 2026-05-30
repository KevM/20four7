# Televista Ambient Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the iOS/iPadOS Televista app — a lean-back front-end for ambient YouTube livestreams with a hybrid Guide + channel-surf experience, a remotely-updatable curated catalog, user-added channels, and tag-based navigation.

**Architecture:** SwiftUI app with a one-way data flow. All playback goes through a `PlayerService` protocol (iOS impl wraps YouTube's IFrame Player API in a `WKWebView`; a `MockPlayerService` drives tests). Pure-function cores (`ChannelMerger`, `TagFilter`, `Surfer`, `YouTubeURLParser`, `CatalogValidator`, `CatalogVersioning`) hold the logic and are unit-tested without YouTube. `RemoteConfig` fetches/caches the versioned catalog with a resilience ladder. SwiftData persists user channels, per-channel state, and settings (CloudKit-ready, `userID` field present but nil).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, WKWebView + YouTube IFrame Player API, XcodeGen, XCTest, `xcodebuild` against the iPhone 16 Pro simulator.

**Conventions used throughout this plan:**
- Repo root: `/Users/kevm/github/televista`. All paths are relative to it.
- Bundle id: `fm.rodeo.televista`. Deployment target: iOS 17.0.
- Test command (run from repo root):
  `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
- Build-only command:
  `xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
- After editing `project.yml`, always regenerate: `xcodegen generate`.
- Multi-tag filtering semantics: **union (OR)** — a channel matches if it carries *any* selected tag.
- In-memory `Channel` stores `tagIDs: [String]`; `Tag` objects are resolved via the catalog's tag dictionary (rename-safe, matches the catalog format in the spec).

---

## File Structure

**Project / config**
- `project.yml` — XcodeGen project definition (app + test targets, schemes).
- `.gitignore` — add Xcode/`*.xcodeproj` generated artifacts.
- `Sources/App/Config.swift` — build-time constants (catalog base URL, supported schema version).

**Models** (`Sources/Models/`)
- `Tag.swift` — `Tag`, `TagKind`.
- `Channel.swift` — `Channel`, `ChannelSource`.

**Catalog** (`Sources/Catalog/`)
- `CatalogModels.swift` — `CatalogManifest`, `Catalog`, `CatalogChannel`, `TagDefinition`.
- `CatalogValidator.swift` — validates a decoded catalog.
- `CatalogVersioning.swift` — pure version-compare + app-version gate.
- `RemoteConfig.swift` — fetch ladder (manifest → catalog → cache → bundled), ETag/304.
- `CatalogCache.swift` — protocol + file-backed cache.
- `Resources/catalog-fallback.json` — bundled catalog so the app is never empty.

**Core logic** (`Sources/Core/`)
- `YouTubeURLParser.swift` — parse URLs/handles into a `YouTubeReference`.
- `ChannelMerger.swift` — merge curated + user channels (dedupe).
- `TagFilter.swift` — union filtering + tag resolution helpers.
- `Surfer.swift` — next/previous channel with wrap-around.

**Player** (`Sources/Player/`)
- `PlayerService.swift` — protocol, `PlayerState`, `PlayerEvent`.
- `MockPlayerService.swift` — test/preview double.
- `WebViewPlayerService.swift` — `WKWebView` + IFrame API impl.
- `Resources/player.html` — IFrame Player host page.

**Playback** (`Sources/Playback/`)
- `Clock.swift` — `Clock` protocol + `SystemClock` + `ManualClock` (test).
- `PlaybackController.swift` — now-playing state, surf, sleep timer, audio-only, auto-resume.

**Persistence** (`Sources/Persistence/`)
- `PersistenceModels.swift` — SwiftData `@Model`s: `UserChannel`, `ChannelUserState`, `AppSettingsRecord`.
- `Persistence.swift` — `ModelContainer` factory (in-memory variant for tests).
- `LocalStore.swift` — CRUD facade over SwiftData used by the app.

**Stores** (`Sources/Stores/`)
- `ChannelStore.swift` — `@MainActor ObservableObject` combining `RemoteConfig` + `LocalStore`.

**UI** (`Sources/UI/`)
- `TelevistaApp.swift` — `@main` entry, root navigation, auto-resume boot.
- `GuideView.swift` — home grid + tag chips.
- `TagChipBar.swift` — reusable chip row.
- `ChannelTile.swift` — grid cell.
- `PlayerView.swift` — fullscreen player + overlay container.
- `PlayerOverlay.swift` — clock, dim, controls, surf affordances.
- `AddChannelView.swift` — paste → validate → tag → save.
- `SettingsView.swift` — ambient prefs + stubbed account row.

**Tests** (`Tests/`)
- `CatalogModelsTests.swift`, `CatalogValidatorTests.swift`, `CatalogVersioningTests.swift`, `RemoteConfigTests.swift`, `YouTubeURLParserTests.swift`, `ChannelMergerTests.swift`, `TagFilterTests.swift`, `SurferTests.swift`, `PlaybackControllerTests.swift`, `LocalStoreTests.swift`.

---

## Task 0: Project skeleton with XcodeGen

**Files:**
- Create: `project.yml`
- Create: `Sources/App/Config.swift`
- Create: `Sources/UI/TelevistaApp.swift` (placeholder, replaced in Task 14)
- Create: `Sources/Resources/catalog-fallback.json` (minimal, expanded in Task 4)
- Create: `Tests/SmokeTests.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Install XcodeGen**

Run: `brew install xcodegen`
Expected: `xcodegen` resolves on `which xcodegen`. (If Homebrew is unavailable, `mint install yonaskolb/XcodeGen`.)

- [ ] **Step 2: Write `project.yml`**

```yaml
name: Televista
options:
  bundleIdPrefix: fm.rodeo
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: YES
targets:
  Televista:
    type: application
    platform: iOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fm.rodeo.televista
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_NSAppTransportSecurity: ""
    info:
      path: Sources/Info.plist
      properties:
        UIBackgroundModes: [audio]
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: false
  TelevistaTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: Televista
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fm.rodeo.televista.tests
schemes:
  Televista:
    build:
      targets:
        Televista: all
    test:
      targets:
        - TelevistaTests
```

- [ ] **Step 3: Write `Sources/App/Config.swift`**

```swift
import Foundation

/// Build-time constants. Replace `catalogBaseURL` per environment.
enum Config {
    /// Stable entry point host for the curated catalog. The manifest lives at
    /// `<catalogBaseURL>/channels-manifest.json`.
    static let catalogBaseURL = URL(string: "https://cdn.example.com/televista")!

    /// Highest catalog `schemaVersion` this build understands.
    static let supportedSchemaVersion = 1
}
```

- [ ] **Step 4: Write placeholder `Sources/UI/TelevistaApp.swift`**

```swift
import SwiftUI

@main
struct TelevistaApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Televista")
        }
    }
}
```

- [ ] **Step 5: Write minimal `Sources/Resources/catalog-fallback.json`**

```json
{
  "schemaVersion": 1,
  "tags": {
    "fireplace": { "name": "Fireplace", "symbol": "flame", "sortOrder": 10 }
  },
  "channels": [
    {
      "id": "fallback-fireplace",
      "title": "Cozy Fireplace 4K",
      "youTubeVideoID": "L_LUpnjgPso",
      "thumbnailURL": null,
      "isLiveExpected": true,
      "tagIds": ["fireplace"]
    }
  ]
}
```

- [ ] **Step 6: Write `Tests/SmokeTests.swift`**

```swift
import XCTest
@testable import Televista

final class SmokeTests: XCTestCase {
    func test_configHasManifestBase() {
        XCTAssertEqual(Config.supportedSchemaVersion, 1)
        XCTAssertFalse(Config.catalogBaseURL.absoluteString.isEmpty)
    }
}
```

- [ ] **Step 7: Update `.gitignore`**

Append to `.gitignore`:
```
# Xcode / build
*.xcodeproj
DerivedData/
build/
*.xcuserstate
.DS_Store
```

- [ ] **Step 8: Generate the project**

Run: `xcodegen generate`
Expected: `Created project at Televista.xcodeproj`.

- [ ] **Step 9: Build and run the smoke test**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold Televista app with XcodeGen"
```

---

## Task 1: Tag and Channel models

**Files:**
- Create: `Sources/Models/Tag.swift`
- Create: `Sources/Models/Channel.swift`

- [ ] **Step 1: Write `Sources/Models/Tag.swift`**

```swift
import Foundation

enum TagKind: String, Codable, Sendable {
    case editorial   // defined in the curated catalog
    case user        // created by the user, private (synced later)
    case derived     // computed (e.g. "Popular") — not present in sub-project #1
}

struct Tag: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var symbol: String?     // SF Symbol name
    var kind: TagKind
    var sortOrder: Int

    init(id: String, name: String, symbol: String? = nil, kind: TagKind, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 2: Write `Sources/Models/Channel.swift`**

```swift
import Foundation

enum ChannelSource: String, Codable, Sendable {
    case curated
    case user
}

/// In-memory channel used throughout the app. Tags are referenced by id and
/// resolved against the catalog's tag dictionary (rename-safe).
struct Channel: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var youTubeVideoID: String
    var thumbnailURL: URL?
    var source: ChannelSource
    var isLiveExpected: Bool
    var dateAdded: Date
    var tagIDs: [String]

    init(
        id: String,
        title: String,
        youTubeVideoID: String,
        thumbnailURL: URL? = nil,
        source: ChannelSource,
        isLiveExpected: Bool,
        dateAdded: Date = .init(timeIntervalSince1970: 0),
        tagIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.youTubeVideoID = youTubeVideoID
        self.thumbnailURL = thumbnailURL
        self.source = source
        self.isLiveExpected = isLiveExpected
        self.dateAdded = dateAdded
        self.tagIDs = tagIDs
    }

    /// YouTube's default thumbnail when none is provided.
    var resolvedThumbnailURL: URL {
        thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(youTubeVideoID)/hqdefault.jpg")!
    }
}
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Tag and Channel models"
```

---

## Task 2: Catalog models + decoding

**Files:**
- Create: `Sources/Catalog/CatalogModels.swift`
- Create: `Tests/CatalogModelsTests.swift`

- [ ] **Step 1: Write the failing test `Tests/CatalogModelsTests.swift`**

```swift
import XCTest
@testable import Televista

final class CatalogModelsTests: XCTestCase {
    func test_decodesManifest() throws {
        let json = """
        {
          "schemaVersion": 1,
          "catalogVersion": 7,
          "catalogUrl": "https://cdn.example.com/televista/catalog-v7.json",
          "minAppVersion": "1.0.0",
          "publishedAt": "2026-05-30T00:00:00Z"
        }
        """.data(using: .utf8)!
        let manifest = try CatalogManifest.decode(from: json)
        XCTAssertEqual(manifest.catalogVersion, 7)
        XCTAssertEqual(manifest.catalogUrl.lastPathComponent, "catalog-v7.json")
        XCTAssertEqual(manifest.minAppVersion, "1.0.0")
    }

    func test_decodesCatalogAndMapsToChannels() throws {
        let json = """
        {
          "schemaVersion": 1,
          "tags": { "rain": { "name": "Rain", "symbol": "cloud.rain", "sortOrder": 20 } },
          "channels": [
            { "id": "c1", "title": "Rain on Window", "youTubeVideoID": "abc",
              "thumbnailURL": null, "isLiveExpected": true, "tagIds": ["rain"] }
          ]
        }
        """.data(using: .utf8)!
        let catalog = try Catalog.decode(from: json)
        XCTAssertEqual(catalog.tags["rain"]?.name, "Rain")
        let channels = catalog.asChannels()
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].source, .curated)
        XCTAssertEqual(channels[0].tagIDs, ["rain"])
    }

    func test_resolvedTagsSortedBySortOrder() throws {
        let json = """
        {
          "schemaVersion": 1,
          "tags": {
            "b": { "name": "B", "symbol": null, "sortOrder": 20 },
            "a": { "name": "A", "symbol": null, "sortOrder": 10 }
          },
          "channels": []
        }
        """.data(using: .utf8)!
        let catalog = try Catalog.decode(from: json)
        XCTAssertEqual(catalog.editorialTags().map(\.id), ["a", "b"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: FAIL — `CatalogManifest` / `Catalog` unresolved.

- [ ] **Step 3: Write `Sources/Catalog/CatalogModels.swift`**

```swift
import Foundation

private enum JSON {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

struct CatalogManifest: Codable, Sendable {
    let schemaVersion: Int
    let catalogVersion: Int
    let catalogUrl: URL
    let minAppVersion: String?
    let publishedAt: Date?

    static func decode(from data: Data) throws -> CatalogManifest {
        try JSON.decoder().decode(CatalogManifest.self, from: data)
    }
}

struct TagDefinition: Codable, Sendable {
    let name: String
    let symbol: String?
    let sortOrder: Int
}

struct CatalogChannel: Codable, Sendable {
    let id: String
    let title: String
    let youTubeVideoID: String
    let thumbnailURL: URL?
    let isLiveExpected: Bool
    let tagIds: [String]
}

struct Catalog: Codable, Sendable {
    let schemaVersion: Int
    let tags: [String: TagDefinition]
    let channels: [CatalogChannel]

    static func decode(from data: Data) throws -> Catalog {
        try JSON.decoder().decode(Catalog.self, from: data)
    }

    /// Editorial tags as `Tag` values, sorted by `sortOrder` then name.
    func editorialTags() -> [Tag] {
        tags.map { id, def in
            Tag(id: id, name: def.name, symbol: def.symbol, kind: .editorial, sortOrder: def.sortOrder)
        }
        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Catalog channels as in-memory `Channel`s tagged `.curated`.
    func asChannels() -> [Channel] {
        channels.map { c in
            Channel(
                id: c.id,
                title: c.title,
                youTubeVideoID: c.youTubeVideoID,
                thumbnailURL: c.thumbnailURL,
                source: .curated,
                isLiveExpected: c.isLiveExpected,
                tagIDs: c.tagIds
            )
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add catalog Codable models and mapping"
```

---

## Task 3: YouTube URL parser

**Files:**
- Create: `Sources/Core/YouTubeURLParser.swift`
- Create: `Tests/YouTubeURLParserTests.swift`

- [ ] **Step 1: Write the failing test `Tests/YouTubeURLParserTests.swift`**

```swift
import XCTest
@testable import Televista

final class YouTubeURLParserTests: XCTestCase {
    func test_parsesWatchURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                       .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesShortURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://youtu.be/dQw4w9WgXcQ?t=10"),
                       .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesLiveURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/live/dQw4w9WgXcQ"),
                       .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesBareID() {
        XCTAssertEqual(YouTubeURLParser.parse("dQw4w9WgXcQ"), .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesHandle() {
        XCTAssertEqual(YouTubeURLParser.parse("@LofiGirl"), .handle("LofiGirl"))
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/@LofiGirl"),
                       .handle("LofiGirl"))
    }
    func test_rejectsGarbage() {
        XCTAssertNil(YouTubeURLParser.parse("not a youtube link"))
        XCTAssertNil(YouTubeURLParser.parse(""))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: FAIL — `YouTubeURLParser` unresolved.

- [ ] **Step 3: Write `Sources/Core/YouTubeURLParser.swift`**

```swift
import Foundation

enum YouTubeReference: Equatable, Sendable {
    case video(id: String)
    case handle(String)
}

enum YouTubeURLParser {
    private static let idCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    static func parse(_ raw: String) -> YouTubeReference? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Bare handle: "@name"
        if input.hasPrefix("@") {
            let name = String(input.dropFirst())
            return name.isEmpty ? nil : .handle(name)
        }

        // Bare 11-char video id (no scheme, no slashes).
        if !input.contains("/"), isValidVideoID(input) {
            return .video(id: input)
        }

        guard let components = URLComponents(string: normalizedURLString(input)) else { return nil }
        let path = components.path

        // /watch?v=ID
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidVideoID(v) {
            return .video(id: v)
        }
        // youtu.be/ID  or  /live/ID  or  /embed/ID
        let segments = path.split(separator: "/").map(String.init)
        if let host = components.host, host.contains("youtu.be"),
           let id = segments.first, isValidVideoID(id) {
            return .video(id: id)
        }
        if let idx = segments.firstIndex(where: { $0 == "live" || $0 == "embed" }),
           idx + 1 < segments.count, isValidVideoID(segments[idx + 1]) {
            return .video(id: segments[idx + 1])
        }
        // /@handle
        if let handleSeg = segments.first(where: { $0.hasPrefix("@") }) {
            return .handle(String(handleSeg.dropFirst()))
        }
        return nil
    }

    private static func normalizedURLString(_ s: String) -> String {
        s.contains("://") ? s : "https://\(s)"
    }

    private static func isValidVideoID(_ s: String) -> Bool {
        s.count == 11 && s.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add YouTube URL/handle parser"
```

---

## Task 4: Catalog validation, versioning, and RemoteConfig

**Files:**
- Create: `Sources/Catalog/CatalogValidator.swift`
- Create: `Sources/Catalog/CatalogVersioning.swift`
- Create: `Sources/Catalog/CatalogCache.swift`
- Create: `Sources/Catalog/RemoteConfig.swift`
- Modify: `Sources/Resources/catalog-fallback.json` (expand to a real default lineup)
- Create: `Tests/CatalogValidatorTests.swift`
- Create: `Tests/CatalogVersioningTests.swift`
- Create: `Tests/RemoteConfigTests.swift`

- [ ] **Step 1: Write the failing test `Tests/CatalogValidatorTests.swift`**

```swift
import XCTest
@testable import Televista

final class CatalogValidatorTests: XCTestCase {
    private func makeCatalog(schema: Int, channels: [CatalogChannel], tags: [String: TagDefinition]) -> Catalog {
        Catalog(schemaVersion: schema, tags: tags, channels: channels)
    }

    func test_rejectsNewerSchema() {
        let c = makeCatalog(schema: 99, channels: [], tags: [:])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .unsupportedSchema(99))
        }
    }

    func test_rejectsEmptyChannels() {
        let c = makeCatalog(schema: 1, channels: [], tags: [:])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .noChannels)
        }
    }

    func test_rejectsUnknownTagReference() {
        let ch = CatalogChannel(id: "c1", title: "T", youTubeVideoID: "abcdefghijk",
                                thumbnailURL: nil, isLiveExpected: true, tagIds: ["ghost"])
        let c = makeCatalog(schema: 1, channels: [ch], tags: [:])
        XCTAssertThrowsError(try CatalogValidator.validate(c, supportedSchema: 1)) { error in
            XCTAssertEqual(error as? CatalogValidationError, .unknownTag(channelID: "c1", tagID: "ghost"))
        }
    }

    func test_acceptsValidCatalog() throws {
        let ch = CatalogChannel(id: "c1", title: "T", youTubeVideoID: "abcdefghijk",
                                thumbnailURL: nil, isLiveExpected: true, tagIds: ["rain"])
        let c = makeCatalog(schema: 1, channels: [ch],
                            tags: ["rain": TagDefinition(name: "Rain", symbol: nil, sortOrder: 1)])
        XCTAssertNoThrow(try CatalogValidator.validate(c, supportedSchema: 1))
    }
}
```

- [ ] **Step 2: Write the failing test `Tests/CatalogVersioningTests.swift`**

```swift
import XCTest
@testable import Televista

final class CatalogVersioningTests: XCTestCase {
    func test_updatesWhenRemoteNewer() {
        XCTAssertTrue(CatalogVersioning.shouldUpdate(cached: 6, remote: 7))
    }
    func test_doesNotUpdateWhenSameOrOlder() {
        XCTAssertFalse(CatalogVersioning.shouldUpdate(cached: 7, remote: 7))
        XCTAssertFalse(CatalogVersioning.shouldUpdate(cached: 8, remote: 7))
    }
    func test_updatesWhenNothingCached() {
        XCTAssertTrue(CatalogVersioning.shouldUpdate(cached: nil, remote: 1))
    }
    func test_appVersionGate() {
        XCTAssertTrue(CatalogVersioning.appSatisfies(minVersion: "1.0.0", appVersion: "1.2.0"))
        XCTAssertTrue(CatalogVersioning.appSatisfies(minVersion: nil, appVersion: "1.0.0"))
        XCTAssertFalse(CatalogVersioning.appSatisfies(minVersion: "2.0.0", appVersion: "1.9.9"))
    }
}
```

- [ ] **Step 3: Write the failing test `Tests/RemoteConfigTests.swift`**

```swift
import XCTest
@testable import Televista

/// In-memory cache double.
final class MemoryCatalogCache: CatalogCache {
    var catalog: Catalog?
    var version: Int?
    var etag: String?
    func loadCachedCatalog() -> (catalog: Catalog, version: Int)? {
        guard let catalog, let version else { return nil }
        return (catalog, version)
    }
    func save(catalog: Catalog, version: Int, etag: String?) {
        self.catalog = catalog; self.version = version; self.etag = etag
    }
    func cachedVersion() -> Int? { version }
    func cachedETag() -> String? { etag }
}

/// URLProtocol stub that returns canned responses keyed by path suffix.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var routes: [String: (status: Int, body: Data, headers: [String: String])] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.lastPathComponent ?? ""
        let route = StubURLProtocol.routes[path] ?? (404, Data(), [:])
        let resp = HTTPURLResponse(url: request.url!, statusCode: route.status,
                                   httpVersion: nil, headerFields: route.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RemoteConfigTests: XCTestCase {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private let manifestJSON = """
    {"schemaVersion":1,"catalogVersion":7,
     "catalogUrl":"https://cdn.example.com/televista/catalog-v7.json","minAppVersion":"1.0.0"}
    """.data(using: .utf8)!

    private let catalogJSON = """
    {"schemaVersion":1,
     "tags":{"rain":{"name":"Rain","symbol":"cloud.rain","sortOrder":1}},
     "channels":[{"id":"c1","title":"Rain","youTubeVideoID":"abcdefghijk",
       "thumbnailURL":null,"isLiveExpected":true,"tagIds":["rain"]}]}
    """.data(using: .utf8)!

    override func tearDown() { StubURLProtocol.routes = [:]; super.tearDown() }

    func test_fetchesAndCachesNewerCatalog() async throws {
        StubURLProtocol.routes = [
            "channels-manifest.json": (200, manifestJSON, ["ETag": "v7etag"]),
            "catalog-v7.json": (200, catalogJSON, [:]),
        ]
        let cache = MemoryCatalogCache()
        let rc = RemoteConfig(baseURL: Config.catalogBaseURL, session: session(),
                              cache: cache, supportedSchema: 1, appVersion: "1.0.0",
                              bundledLoader: { fatalError("not used") })
        let catalog = try await rc.currentCatalog()
        XCTAssertEqual(catalog.channels.first?.id, "c1")
        XCTAssertEqual(cache.cachedVersion(), 7)
    }

    func test_fallsBackToCacheOnNetworkFailure() async throws {
        // No routes => 404 for everything. Cache already has v6.
        let cache = MemoryCatalogCache()
        let cached = try Catalog.decode(from: catalogJSON)
        cache.save(catalog: cached, version: 6, etag: nil)
        let rc = RemoteConfig(baseURL: Config.catalogBaseURL, session: session(),
                              cache: cache, supportedSchema: 1, appVersion: "1.0.0",
                              bundledLoader: { fatalError("not used") })
        let catalog = try await rc.currentCatalog()
        XCTAssertEqual(catalog.channels.first?.id, "c1")
    }

    func test_fallsBackToBundledWhenNoCache() async throws {
        let bundled = try Catalog.decode(from: catalogJSON)
        let rc = RemoteConfig(baseURL: Config.catalogBaseURL, session: session(),
                              cache: MemoryCatalogCache(), supportedSchema: 1, appVersion: "1.0.0",
                              bundledLoader: { bundled })
        let catalog = try await rc.currentCatalog()
        XCTAssertEqual(catalog.channels.first?.id, "c1")
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: FAIL — `CatalogValidator`, `CatalogVersioning`, `CatalogCache`, `RemoteConfig` unresolved.

- [ ] **Step 5: Write `Sources/Catalog/CatalogValidator.swift`**

```swift
import Foundation

enum CatalogValidationError: Error, Equatable {
    case unsupportedSchema(Int)
    case noChannels
    case unknownTag(channelID: String, tagID: String)
}

enum CatalogValidator {
    static func validate(_ catalog: Catalog, supportedSchema: Int) throws {
        guard catalog.schemaVersion <= supportedSchema else {
            throw CatalogValidationError.unsupportedSchema(catalog.schemaVersion)
        }
        guard !catalog.channels.isEmpty else {
            throw CatalogValidationError.noChannels
        }
        for channel in catalog.channels {
            for tagID in channel.tagIds where catalog.tags[tagID] == nil {
                throw CatalogValidationError.unknownTag(channelID: channel.id, tagID: tagID)
            }
        }
    }
}
```

- [ ] **Step 6: Write `Sources/Catalog/CatalogVersioning.swift`**

```swift
import Foundation

enum CatalogVersioning {
    static func shouldUpdate(cached: Int?, remote: Int) -> Bool {
        guard let cached else { return true }
        return remote > cached
    }

    /// Semantic-ish comparison: dotted integer components.
    static func appSatisfies(minVersion: String?, appVersion: String) -> Bool {
        guard let minVersion else { return true }
        return compare(appVersion, minVersion) >= 0
    }

    private static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
```

- [ ] **Step 7: Write `Sources/Catalog/CatalogCache.swift`**

```swift
import Foundation

protocol CatalogCache {
    func loadCachedCatalog() -> (catalog: Catalog, version: Int)?
    func save(catalog: Catalog, version: Int, etag: String?)
    func cachedVersion() -> Int?
    func cachedETag() -> String?
}

/// File-backed cache in Application Support.
final class FileCatalogCache: CatalogCache {
    private let directory: URL
    private let fm = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Televista", isDirectory: true)
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    private var metaURL: URL { directory.appendingPathComponent("catalog-meta.json") }

    private struct Meta: Codable { let version: Int; let etag: String? }

    func loadCachedCatalog() -> (catalog: Catalog, version: Int)? {
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? Catalog.decode(from: data),
              let version = cachedVersion() else { return nil }
        return (catalog, version)
    }

    func save(catalog: Catalog, version: Int, etag: String?) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: catalogURL, options: .atomic)
        let meta = try? JSONEncoder().encode(Meta(version: version, etag: etag))
        try? meta?.write(to: metaURL, options: .atomic)
    }

    private func meta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }
    func cachedVersion() -> Int? { meta()?.version }
    func cachedETag() -> String? { meta()?.etag }
}
```

Note: `Catalog`/`TagDefinition`/`CatalogChannel` already conform to `Codable`, so encoding for the cache works.

- [ ] **Step 8: Write `Sources/Catalog/RemoteConfig.swift`**

```swift
import Foundation

/// Fetches the curated catalog with a resilience ladder:
/// live (manifest → catalog) → last good cache → bundled fallback.
final class RemoteConfig {
    private let baseURL: URL
    private let session: URLSession
    private let cache: CatalogCache
    private let supportedSchema: Int
    private let appVersion: String
    private let bundledLoader: () -> Catalog

    init(baseURL: URL, session: URLSession, cache: CatalogCache,
         supportedSchema: Int, appVersion: String, bundledLoader: @escaping () -> Catalog) {
        self.baseURL = baseURL
        self.session = session
        self.cache = cache
        self.supportedSchema = supportedSchema
        self.appVersion = appVersion
        self.bundledLoader = bundledLoader
    }

    func currentCatalog() async -> Catalog {
        if let fresh = try? await fetchFromNetwork() { return fresh }
        if let cached = cache.loadCachedCatalog() { return cached.catalog }
        return bundledLoader()
    }

    private func fetchFromNetwork() async throws -> Catalog {
        let manifest = try await fetchManifest()
        guard CatalogVersioning.appSatisfies(minVersion: manifest.minAppVersion, appVersion: appVersion) else {
            throw RemoteConfigError.appTooOld
        }
        guard CatalogVersioning.shouldUpdate(cached: cache.cachedVersion(), remote: manifest.catalogVersion) else {
            if let cached = cache.loadCachedCatalog() { return cached.catalog }
            throw RemoteConfigError.noUpdateNoCache
        }
        var request = URLRequest(url: manifest.catalogUrl)
        if let etag = cache.cachedETag() { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteConfigError.badResponse }
        if http.statusCode == 304, let cached = cache.loadCachedCatalog() { return cached.catalog }
        guard http.statusCode == 200 else { throw RemoteConfigError.badResponse }
        let catalog = try Catalog.decode(from: data)
        try CatalogValidator.validate(catalog, supportedSchema: supportedSchema)
        let etag = http.value(forHTTPHeaderField: "ETag")
        cache.save(catalog: catalog, version: manifest.catalogVersion, etag: etag)
        return catalog
    }

    private func fetchManifest() async throws -> CatalogManifest {
        let url = baseURL.appendingPathComponent("channels-manifest.json")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RemoteConfigError.badResponse
        }
        return try CatalogManifest.decode(from: data)
    }
}

enum RemoteConfigError: Error { case badResponse, appTooOld, noUpdateNoCache }
```

Note: in `test_fallsBackToCacheOnNetworkFailure`, the 404 manifest makes `fetchFromNetwork` throw, so the ladder returns the cached catalog. ✅

- [ ] **Step 9: Expand `Sources/Resources/catalog-fallback.json`** to a real default lineup (used when offline on first launch):

```json
{
  "schemaVersion": 1,
  "tags": {
    "fireplace": { "name": "Fireplace", "symbol": "flame", "sortOrder": 10 },
    "rain": { "name": "Rain", "symbol": "cloud.rain", "sortOrder": 20 },
    "lofi": { "name": "Lofi", "symbol": "music.note", "sortOrder": 30 },
    "ocean": { "name": "Ocean", "symbol": "water.waves", "sortOrder": 40 }
  },
  "channels": [
    { "id": "fb-fireplace", "title": "Cozy Fireplace 4K", "youTubeVideoID": "L_LUpnjgPso",
      "thumbnailURL": null, "isLiveExpected": true, "tagIds": ["fireplace"] },
    { "id": "fb-rain", "title": "Rain on Window", "youTubeVideoID": "mPZkdNFkNps",
      "thumbnailURL": null, "isLiveExpected": true, "tagIds": ["rain"] },
    { "id": "fb-lofi", "title": "Lofi Hip Hop Radio", "youTubeVideoID": "jfKfPfyJRdk",
      "thumbnailURL": null, "isLiveExpected": true, "tagIds": ["lofi"] },
    { "id": "fb-ocean", "title": "Ocean Waves", "youTubeVideoID": "WHPEKLQID4U",
      "thumbnailURL": null, "isLiveExpected": true, "tagIds": ["ocean"] }
  ]
}
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: add catalog validation, versioning, and RemoteConfig fetch ladder"
```

---

## Task 5: Channel merge and tag filtering

**Files:**
- Create: `Sources/Core/ChannelMerger.swift`
- Create: `Sources/Core/TagFilter.swift`
- Create: `Tests/ChannelMergerTests.swift`
- Create: `Tests/TagFilterTests.swift`

- [ ] **Step 1: Write the failing test `Tests/ChannelMergerTests.swift`**

```swift
import XCTest
@testable import Televista

final class ChannelMergerTests: XCTestCase {
    private func chan(_ id: String, video: String, source: ChannelSource) -> Channel {
        Channel(id: id, title: id, youTubeVideoID: video, source: source, isLiveExpected: true)
    }

    func test_mergesBothSources() {
        let merged = ChannelMerger.merge(
            curated: [chan("a", video: "v1", source: .curated)],
            user: [chan("b", video: "v2", source: .user)])
        XCTAssertEqual(Set(merged.map(\.id)), ["a", "b"])
    }

    func test_userWinsOnDuplicateVideoID() {
        let merged = ChannelMerger.merge(
            curated: [chan("a", video: "dup", source: .curated)],
            user: [chan("b", video: "dup", source: .user)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .user)
    }
}
```

- [ ] **Step 2: Write the failing test `Tests/TagFilterTests.swift`**

```swift
import XCTest
@testable import Televista

final class TagFilterTests: XCTestCase {
    private let channels = [
        Channel(id: "fire", title: "Fire", youTubeVideoID: "v1", source: .curated,
                isLiveExpected: true, tagIDs: ["fireplace"]),
        Channel(id: "rain", title: "Rain", youTubeVideoID: "v2", source: .curated,
                isLiveExpected: true, tagIDs: ["rain"]),
        Channel(id: "both", title: "Both", youTubeVideoID: "v3", source: .curated,
                isLiveExpected: true, tagIDs: ["fireplace", "lofi"]),
    ]

    func test_emptySelectionReturnsAll() {
        XCTAssertEqual(TagFilter.filter(channels, anyOf: []).count, 3)
    }

    func test_unionSemantics() {
        let result = TagFilter.filter(channels, anyOf: ["fireplace"])
        XCTAssertEqual(Set(result.map(\.id)), ["fire", "both"])
    }

    func test_multipleTagsUnion() {
        let result = TagFilter.filter(channels, anyOf: ["rain", "lofi"])
        XCTAssertEqual(Set(result.map(\.id)), ["rain", "both"])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: FAIL — `ChannelMerger`, `TagFilter` unresolved.

- [ ] **Step 4: Write `Sources/Core/ChannelMerger.swift`**

```swift
import Foundation

enum ChannelMerger {
    /// Curated + user channels into one list. On duplicate `youTubeVideoID`, the
    /// user-added channel wins (their tags/title override the curated entry).
    static func merge(curated: [Channel], user: [Channel]) -> [Channel] {
        var byVideo: [String: Channel] = [:]
        for c in curated { byVideo[c.youTubeVideoID] = c }
        for u in user { byVideo[u.youTubeVideoID] = u }  // user overrides
        return Array(byVideo.values)
    }
}
```

- [ ] **Step 5: Write `Sources/Core/TagFilter.swift`**

```swift
import Foundation

enum TagFilter {
    /// Union (OR) filtering: a channel matches if it carries ANY selected tag.
    /// Empty selection returns all channels.
    static func filter(_ channels: [Channel], anyOf selected: Set<String>) -> [Channel] {
        guard !selected.isEmpty else { return channels }
        return channels.filter { !Set($0.tagIDs).isDisjoint(with: selected) }
    }

    /// Resolve a channel's tag ids into `Tag`s using the supplied dictionary,
    /// dropping unknown ids.
    static func resolve(_ tagIDs: [String], in dictionary: [String: Tag]) -> [Tag] {
        tagIDs.compactMap { dictionary[$0] }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add channel merge and union tag filtering"
```

---

## Task 6: PlayerService protocol and mock

**Files:**
- Create: `Sources/Player/PlayerService.swift`
- Create: `Sources/Player/MockPlayerService.swift`

- [ ] **Step 1: Write `Sources/Player/PlayerService.swift`**

```swift
import Foundation
import Combine

enum PlayerState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case error(reason: PlayerErrorReason)
}

enum PlayerErrorReason: Equatable, Sendable {
    case embeddingDisallowed   // YouTube error 101 / 150
    case streamOffline
    case generic(String)
}

enum PlayerEvent: Equatable, Sendable {
    case playbackStarted
    case ended
    case embeddingDisallowed
    case streamOffline
}

/// Platform-agnostic playback boundary. The iOS implementation wraps the YouTube
/// IFrame Player; tests use `MockPlayerService`; a future tvOS impl conforms here.
@MainActor
protocol PlayerService: AnyObject {
    var statePublisher: AnyPublisher<PlayerState, Never> { get }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { get }

    func load(channel: Channel)
    func play()
    func pause()
    func setVolume(_ volume: Int)   // 0...100
    func setMuted(_ muted: Bool)
}
```

- [ ] **Step 2: Write `Sources/Player/MockPlayerService.swift`**

```swift
import Foundation
import Combine

@MainActor
final class MockPlayerService: PlayerService {
    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.idle)
    private let eventSubject = PassthroughSubject<PlayerEvent, Never>()

    var statePublisher: AnyPublisher<PlayerState, Never> { stateSubject.eraseToAnyPublisher() }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private(set) var loadedChannel: Channel?
    private(set) var volume = 100
    private(set) var muted = false

    func load(channel: Channel) {
        loadedChannel = channel
        stateSubject.send(.loading)
    }
    func play() { stateSubject.send(.playing); eventSubject.send(.playbackStarted) }
    func pause() { stateSubject.send(.paused) }
    func setVolume(_ volume: Int) { self.volume = volume }
    func setMuted(_ muted: Bool) { self.muted = muted }

    // Test helpers to simulate player callbacks.
    func simulate(state: PlayerState) { stateSubject.send(state) }
    func simulate(event: PlayerEvent) { eventSubject.send(event) }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add PlayerService protocol and MockPlayerService"
```

---

## Task 7: PlaybackController (surf, sleep timer, auto-resume)

**Files:**
- Create: `Sources/Playback/Clock.swift`
- Create: `Sources/Core/Surfer.swift`
- Create: `Sources/Playback/PlaybackController.swift`
- Create: `Tests/SurferTests.swift`
- Create: `Tests/PlaybackControllerTests.swift`

- [ ] **Step 1: Write the failing test `Tests/SurferTests.swift`**

```swift
import XCTest
@testable import Televista

final class SurferTests: XCTestCase {
    private let list = ["a", "b", "c"].map {
        Channel(id: $0, title: $0, youTubeVideoID: "v\($0)", source: .curated, isLiveExpected: true)
    }

    func test_next() {
        XCTAssertEqual(Surfer.channel(after: "a", in: list, direction: .next)?.id, "b")
    }
    func test_nextWrapsAround() {
        XCTAssertEqual(Surfer.channel(after: "c", in: list, direction: .next)?.id, "a")
    }
    func test_previousWrapsAround() {
        XCTAssertEqual(Surfer.channel(after: "a", in: list, direction: .previous)?.id, "c")
    }
    func test_unknownCurrentReturnsFirst() {
        XCTAssertEqual(Surfer.channel(after: "zzz", in: list, direction: .next)?.id, "a")
    }
    func test_emptyListReturnsNil() {
        XCTAssertNil(Surfer.channel(after: "a", in: [], direction: .next))
    }
}
```

- [ ] **Step 2: Write the failing test `Tests/PlaybackControllerTests.swift`**

```swift
import XCTest
import Combine
@testable import Televista

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private func makeChannels() -> [Channel] {
        ["a", "b", "c"].map {
            Channel(id: $0, title: $0, youTubeVideoID: "v\($0)", source: .curated, isLiveExpected: true)
        }
    }

    func test_playLoadsChannel() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "b")
        XCTAssertEqual(c.currentChannel?.id, "b")
        XCTAssertEqual(player.loadedChannel?.id, "b")
    }

    func test_surfMovesToNextAndLoads() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.surf(.next)
        XCTAssertEqual(c.currentChannel?.id, "b")
        XCTAssertEqual(player.loadedChannel?.id, "b")
    }

    func test_sleepTimerPausesAfterInterval() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.startSleepTimer(seconds: 60)
        clock.advance(by: 59)
        XCTAssertNotEqual(player.lastCommand, .pause)
        clock.advance(by: 1)
        XCTAssertEqual(player.lastCommand, .pause)
    }

    func test_offlineEventOffersSurf() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(event: .streamOffline)
        XCTAssertTrue(c.showsOfflineState)
    }
}
```

This test references `player.lastCommand`. Add it to `MockPlayerService` in Step 4.

- [ ] **Step 3: Write `Sources/Playback/Clock.swift`**

```swift
import Foundation

protocol Clock: AnyObject {
    func now() -> Date
    /// Schedule `work` after `seconds`. Returns a token; calling `cancel()` stops it.
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> ClockToken
}

protocol ClockToken: AnyObject { func cancel() }

final class SystemClock: Clock {
    func now() -> Date { Date() }
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> ClockToken {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in work() }
        return TimerToken(timer: timer)
    }
    private final class TimerToken: ClockToken {
        let timer: Timer
        init(timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}

/// Deterministic clock for tests. `advance(by:)` fires due work.
final class ManualClock: Clock {
    private var current = Date(timeIntervalSince1970: 0)
    private final class Scheduled: ClockToken {
        let fireAt: TimeInterval
        let work: () -> Void
        var cancelled = false
        init(fireAt: TimeInterval, work: @escaping () -> Void) { self.fireAt = fireAt; self.work = work }
        func cancel() { cancelled = true }
    }
    private var scheduled: [Scheduled] = []

    func now() -> Date { current }
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> ClockToken {
        let item = Scheduled(fireAt: current.timeIntervalSince1970 + seconds, work: work)
        scheduled.append(item)
        return item
    }
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let due = scheduled.filter { !$0.cancelled && $0.fireAt <= current.timeIntervalSince1970 }
        scheduled.removeAll { item in due.contains { $0 === item } }
        due.forEach { $0.work() }
    }
}
```

- [ ] **Step 4: Add `lastCommand` to `Sources/Player/MockPlayerService.swift`**

Add this enum and property to `MockPlayerService` (insert after the `muted` property):

```swift
    enum Command: Equatable { case load, play, pause, volume, mute }
    private(set) var lastCommand: Command?
```

Then set it at the start of each command method body, so the methods become:

```swift
    func load(channel: Channel) {
        lastCommand = .load
        loadedChannel = channel
        stateSubject.send(.loading)
    }
    func play() { lastCommand = .play; stateSubject.send(.playing); eventSubject.send(.playbackStarted) }
    func pause() { lastCommand = .pause; stateSubject.send(.paused) }
    func setVolume(_ volume: Int) { lastCommand = .volume; self.volume = volume }
    func setMuted(_ muted: Bool) { lastCommand = .mute; self.muted = muted }
```

- [ ] **Step 5: Write `Sources/Core/Surfer.swift`**

```swift
import Foundation

enum SurfDirection { case next, previous }

enum Surfer {
    /// Channel before/after `currentID` with wrap-around. If `currentID` isn't in
    /// the list, returns the first channel. Returns nil for an empty list.
    static func channel(after currentID: String, in list: [Channel], direction: SurfDirection) -> Channel? {
        guard !list.isEmpty else { return nil }
        guard let idx = list.firstIndex(where: { $0.id == currentID }) else { return list.first }
        let count = list.count
        let target = direction == .next ? (idx + 1) % count : (idx - 1 + count) % count
        return list[target]
    }
}
```

- [ ] **Step 6: Write `Sources/Playback/PlaybackController.swift`**

```swift
import Foundation
import Combine

/// App-level "what's playing now" state. Owns surf, sleep timer, audio-only,
/// and auto-resume bookkeeping. Drives a `PlayerService`.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentChannel: Channel?
    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var showsOfflineState = false
    @Published private(set) var sleepTimerActive = false
    @Published var audioOnly = false

    private let player: PlayerService
    private let clock: Clock
    private var lineup: [Channel] = []
    private var sleepToken: ClockToken?
    private var cancellables = Set<AnyCancellable>()

    /// Called when a channel starts playing, so callers can persist last-watched.
    var onChannelChanged: ((Channel) -> Void)?

    init(player: PlayerService, clock: Clock) {
        self.player = player
        self.clock = clock
        bind()
    }

    private func bind() {
        player.statePublisher
            .sink { [weak self] in self?.state = $0 }
            .store(in: &cancellables)
        player.eventPublisher
            .sink { [weak self] event in
                switch event {
                case .streamOffline, .embeddingDisallowed:
                    self?.showsOfflineState = true
                case .playbackStarted:
                    self?.showsOfflineState = false
                case .ended:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func setLineup(_ channels: [Channel]) { lineup = channels }

    func play(channelID: String) {
        guard let channel = lineup.first(where: { $0.id == channelID }) else { return }
        start(channel)
    }

    func surf(_ direction: SurfDirection) {
        guard let current = currentChannel,
              let next = Surfer.channel(after: current.id, in: lineup, direction: direction) else { return }
        start(next)
    }

    private func start(_ channel: Channel) {
        currentChannel = channel
        showsOfflineState = false
        player.load(channel: channel)
        player.play()
        onChannelChanged?(channel)
    }

    // MARK: Sleep timer
    func startSleepTimer(seconds: TimeInterval) {
        sleepToken?.cancel()
        sleepTimerActive = true
        sleepToken = clock.schedule(after: seconds) { [weak self] in
            self?.player.pause()
            self?.sleepTimerActive = false
            self?.sleepToken = nil
        }
    }
    func cancelSleepTimer() {
        sleepToken?.cancel()
        sleepToken = nil
        sleepTimerActive = false
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add PlaybackController with surf and sleep timer"
```

---

## Task 8: SwiftData persistence

**Files:**
- Create: `Sources/Persistence/PersistenceModels.swift`
- Create: `Sources/Persistence/Persistence.swift`
- Create: `Sources/Persistence/LocalStore.swift`
- Create: `Tests/LocalStoreTests.swift`

- [ ] **Step 1: Write the failing test `Tests/LocalStoreTests.swift`**

```swift
import XCTest
import SwiftData
@testable import Televista

@MainActor
final class LocalStoreTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let container = try Persistence.makeContainer(inMemory: true)
        return LocalStore(context: container.mainContext)
    }

    func test_addAndFetchUserChannel() throws {
        let store = try makeStore()
        let channel = Channel(id: "u1", title: "My Rain", youTubeVideoID: "abcdefghijk",
                              source: .user, isLiveExpected: true, tagIDs: ["mine"])
        store.addUserChannel(channel)
        let fetched = store.userChannels()
        XCTAssertEqual(fetched.map(\.id), ["u1"])
        XCTAssertEqual(fetched.first?.source, .user)
    }

    func test_toggleFavoritePersists() throws {
        let store = try makeStore()
        store.setFavorite(channelID: "c1", isFavorite: true)
        XCTAssertTrue(store.isFavorite(channelID: "c1"))
        store.setFavorite(channelID: "c1", isFavorite: false)
        XCTAssertFalse(store.isFavorite(channelID: "c1"))
    }

    func test_lastWatchedRoundTrips() throws {
        let store = try makeStore()
        store.setLastWatched(channelID: "c9")
        XCTAssertEqual(store.lastWatchedChannelID(), "c9")
    }

    func test_settingsRoundTrip() throws {
        let store = try makeStore()
        var s = store.settings()
        s.autoResume = true
        s.defaultSleepMinutes = 45
        store.saveSettings(s)
        XCTAssertTrue(store.settings().autoResume)
        XCTAssertEqual(store.settings().defaultSleepMinutes, 45)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: FAIL — `Persistence`, `LocalStore` unresolved.

- [ ] **Step 3: Write `Sources/Persistence/PersistenceModels.swift`**

```swift
import Foundation
import SwiftData

@Model
final class UserChannel {
    @Attribute(.unique) var id: String
    var title: String
    var youTubeVideoID: String
    var thumbnailURLString: String?
    var isLiveExpected: Bool
    var dateAdded: Date
    var tagIDs: [String]
    /// Nil in sub-project #1; Sign in with Apple populates it for CloudKit sync.
    var userID: String?

    init(id: String, title: String, youTubeVideoID: String, thumbnailURLString: String?,
         isLiveExpected: Bool, dateAdded: Date, tagIDs: [String], userID: String?) {
        self.id = id
        self.title = title
        self.youTubeVideoID = youTubeVideoID
        self.thumbnailURLString = thumbnailURLString
        self.isLiveExpected = isLiveExpected
        self.dateAdded = dateAdded
        self.tagIDs = tagIDs
        self.userID = userID
    }
}

@Model
final class ChannelUserState {
    @Attribute(.unique) var channelID: String
    var isFavorite: Bool
    var customOrder: Int
    var userTagIDs: [String]
    var userID: String?

    init(channelID: String, isFavorite: Bool = false, customOrder: Int = 0,
         userTagIDs: [String] = [], userID: String? = nil) {
        self.channelID = channelID
        self.isFavorite = isFavorite
        self.customOrder = customOrder
        self.userTagIDs = userTagIDs
        self.userID = userID
    }
}

@Model
final class AppSettingsRecord {
    // Single-row record keyed by a constant id.
    @Attribute(.unique) var id: String
    var autoResume: Bool
    var audioOnly: Bool
    var defaultSleepMinutes: Int
    var showClockOverlay: Bool
    var dimLevelRaw: Int   // 0 none, 1 low, 2 medium, 3 high
    var lastWatchedChannelID: String?

    init(id: String = "default", autoResume: Bool = false, audioOnly: Bool = false,
         defaultSleepMinutes: Int = 30, showClockOverlay: Bool = false,
         dimLevelRaw: Int = 0, lastWatchedChannelID: String? = nil) {
        self.id = id
        self.autoResume = autoResume
        self.audioOnly = audioOnly
        self.defaultSleepMinutes = defaultSleepMinutes
        self.showClockOverlay = showClockOverlay
        self.dimLevelRaw = dimLevelRaw
        self.lastWatchedChannelID = lastWatchedChannelID
    }
}
```

- [ ] **Step 4: Write `Sources/Persistence/Persistence.swift`**

```swift
import Foundation
import SwiftData

enum Persistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([UserChannel.self, ChannelUserState.self, AppSettingsRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
```

- [ ] **Step 5: Write `Sources/Persistence/LocalStore.swift`**

```swift
import Foundation
import SwiftData

/// A plain value mirror of `AppSettingsRecord` used by the UI.
struct AppSettings: Equatable {
    var autoResume: Bool
    var audioOnly: Bool
    var defaultSleepMinutes: Int
    var showClockOverlay: Bool
    var dimLevelRaw: Int
}

/// CRUD facade over SwiftData. The single owner of the `ModelContext`.
@MainActor
final class LocalStore {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    // MARK: User channels
    func addUserChannel(_ channel: Channel) {
        let record = UserChannel(
            id: channel.id, title: channel.title, youTubeVideoID: channel.youTubeVideoID,
            thumbnailURLString: channel.thumbnailURL?.absoluteString,
            isLiveExpected: channel.isLiveExpected, dateAdded: channel.dateAdded,
            tagIDs: channel.tagIDs, userID: nil)
        context.insert(record)
        try? context.save()
    }

    func removeUserChannel(id: String) {
        let descriptor = FetchDescriptor<UserChannel>(predicate: #Predicate { $0.id == id })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try? context.save()
    }

    func userChannels() -> [Channel] {
        let descriptor = FetchDescriptor<UserChannel>(sortBy: [SortDescriptor(\.dateAdded)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { r in
            Channel(id: r.id, title: r.title, youTubeVideoID: r.youTubeVideoID,
                    thumbnailURL: r.thumbnailURLString.flatMap(URL.init(string:)),
                    source: .user, isLiveExpected: r.isLiveExpected,
                    dateAdded: r.dateAdded, tagIDs: r.tagIDs)
        }
    }

    // MARK: Favorites / per-channel state
    private func userState(for channelID: String) -> ChannelUserState? {
        let descriptor = FetchDescriptor<ChannelUserState>(predicate: #Predicate { $0.channelID == channelID })
        return try? context.fetch(descriptor).first
    }

    func setFavorite(channelID: String, isFavorite: Bool) {
        if let existing = userState(for: channelID) {
            existing.isFavorite = isFavorite
        } else {
            context.insert(ChannelUserState(channelID: channelID, isFavorite: isFavorite))
        }
        try? context.save()
    }

    func isFavorite(channelID: String) -> Bool { userState(for: channelID)?.isFavorite ?? false }

    func favoriteChannelIDs() -> Set<String> {
        let descriptor = FetchDescriptor<ChannelUserState>(predicate: #Predicate { $0.isFavorite == true })
        let records = (try? context.fetch(descriptor)) ?? []
        return Set(records.map(\.channelID))
    }

    // MARK: Settings (single row)
    private func settingsRecord() -> AppSettingsRecord {
        let descriptor = FetchDescriptor<AppSettingsRecord>(predicate: #Predicate { $0.id == "default" })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let record = AppSettingsRecord()
        context.insert(record)
        try? context.save()
        return record
    }

    func settings() -> AppSettings {
        let r = settingsRecord()
        return AppSettings(autoResume: r.autoResume, audioOnly: r.audioOnly,
                           defaultSleepMinutes: r.defaultSleepMinutes,
                           showClockOverlay: r.showClockOverlay, dimLevelRaw: r.dimLevelRaw)
    }

    func saveSettings(_ s: AppSettings) {
        let r = settingsRecord()
        r.autoResume = s.autoResume
        r.audioOnly = s.audioOnly
        r.defaultSleepMinutes = s.defaultSleepMinutes
        r.showClockOverlay = s.showClockOverlay
        r.dimLevelRaw = s.dimLevelRaw
        try? context.save()
    }

    func setLastWatched(channelID: String) {
        settingsRecord().lastWatchedChannelID = channelID
        try? context.save()
    }
    func lastWatchedChannelID() -> String? { settingsRecord().lastWatchedChannelID }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add SwiftData persistence (user channels, favorites, settings)"
```

---

## Task 9: WebViewPlayerService (real iframe player)

**Files:**
- Create: `Sources/Player/Resources/player.html`
- Create: `Sources/Player/WebViewPlayerService.swift`

No unit test — the web view is verified by build + manual smoke (the spec's testing plan calls for manual/integration smoke here). Logic remains covered via `MockPlayerService`.

- [ ] **Step 1: Write `Sources/Player/Resources/player.html`**

```html
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
    #player { width: 100vw; height: 100vh; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script src="https://www.youtube.com/iframe_api"></script>
  <script>
    let player;
    function post(type, payload) {
      window.webkit.messageHandlers.player.postMessage(
        Object.assign({ type: type }, payload || {}));
    }
    function onYouTubeIframeAPIReady() { post('apiReady'); }

    function loadVideo(videoId) {
      if (player) { player.loadVideoById(videoId); return; }
      player = new YT.Player('player', {
        width: '100%', height: '100%', videoId: videoId,
        playerVars: {
          autoplay: 1, controls: 0, playsinline: 1, rel: 0,
          modestbranding: 1, fs: 0, iv_load_policy: 3, disablekb: 1
        },
        events: {
          onReady: function () { post('ready'); },
          onStateChange: function (e) { post('state', { state: e.data }); },
          onError: function (e) { post('error', { code: e.data }); }
        }
      });
    }
    function play()  { player && player.playVideo(); }
    function pause() { player && player.pauseVideo(); }
    function setVolume(v) { player && player.setVolume(v); }
    function setMuted(m) { if (!player) return; m ? player.mute() : player.unMute(); }
  </script>
</body>
</html>
```

- [ ] **Step 2: Write `Sources/Player/WebViewPlayerService.swift`**

```swift
import Foundation
import Combine
import WebKit

/// iOS playback via YouTube's IFrame Player API hosted in a WKWebView.
/// Exposes the shared `view` for SwiftUI to embed; all control goes through the
/// `PlayerService` API so the rest of the app never touches WebKit.
@MainActor
final class WebViewPlayerService: NSObject, PlayerService, WKScriptMessageHandler {
    let webView: WKWebView

    private let stateSubject = CurrentValueSubject<PlayerState, Never>(.idle)
    private let eventSubject = PassthroughSubject<PlayerEvent, Never>()
    var statePublisher: AnyPublisher<PlayerState, Never> { stateSubject.eraseToAnyPublisher() }
    var eventPublisher: AnyPublisher<PlayerEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private var apiReady = false
    private var pendingVideoID: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "player")
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        loadHostPage()
    }

    private func loadHostPage() {
        guard let url = Bundle.main.url(forResource: "player", withExtension: "html") else {
            stateSubject.send(.error(reason: .generic("player.html missing")))
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: PlayerService
    func load(channel: Channel) {
        stateSubject.send(.loading)
        if apiReady {
            evaluate("loadVideo('\(channel.youTubeVideoID)')")
        } else {
            pendingVideoID = channel.youTubeVideoID
        }
    }
    func play()  { evaluate("play()") }
    func pause() { evaluate("pause()") }
    func setVolume(_ volume: Int) { evaluate("setVolume(\(max(0, min(100, volume))))") }
    func setMuted(_ muted: Bool)  { evaluate("setMuted(\(muted))") }

    private func evaluate(_ js: String) { webView.evaluateJavaScript(js, completionHandler: nil) }

    // MARK: WKScriptMessageHandler
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "apiReady":
            apiReady = true
            if let pending = pendingVideoID { evaluate("loadVideo('\(pending)')"); pendingVideoID = nil }
        case "state":
            handlePlayerState(body["state"] as? Int ?? -1)
        case "error":
            handleError(code: body["code"] as? Int ?? -1)
        default:
            break
        }
    }

    /// YouTube player states: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued.
    private func handlePlayerState(_ raw: Int) {
        switch raw {
        case 1: stateSubject.send(.playing); eventSubject.send(.playbackStarted)
        case 2: stateSubject.send(.paused)
        case 3: stateSubject.send(.loading)
        case 0: stateSubject.send(.ended); eventSubject.send(.ended)
        default: break
        }
    }

    /// YouTube error codes: 101/150 embedding disallowed; 2 invalid; 100 not found; 5 html5.
    private func handleError(code: Int) {
        switch code {
        case 101, 150:
            stateSubject.send(.error(reason: .embeddingDisallowed))
            eventSubject.send(.embeddingDisallowed)
        case 100:
            stateSubject.send(.error(reason: .streamOffline))
            eventSubject.send(.streamOffline)
        default:
            stateSubject.send(.error(reason: .generic("YT error \(code)")))
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke (deferred until UI exists)**

Note for the implementer: full playback can only be verified once `PlayerView` (Task 11) embeds `webView`. After Task 11, run the app and confirm a known-good livestream (e.g. `jfKfPfyJRdk`) plays. Record the result there.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add WebViewPlayerService and IFrame host page"
```

---

## Task 10: Guide UI (grid + tag chips)

**Files:**
- Create: `Sources/UI/TagChipBar.swift`
- Create: `Sources/UI/ChannelTile.swift`
- Create: `Sources/UI/GuideView.swift`
- Create: `Sources/Stores/ChannelStore.swift`

- [ ] **Step 1: Write `Sources/Stores/ChannelStore.swift`**

```swift
import Foundation
import Combine

/// Combines the remote curated catalog with local user channels and exposes the
/// merged, filterable lineup plus the tag dictionary for resolution/chips.
@MainActor
final class ChannelStore: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var tagsByID: [String: Tag] = [:]
    @Published private(set) var editorialTags: [Tag] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published var selectedTagIDs: Set<String> = []

    private let remoteConfig: RemoteConfig
    private let localStore: LocalStore

    init(remoteConfig: RemoteConfig, localStore: LocalStore) {
        self.remoteConfig = remoteConfig
        self.localStore = localStore
    }

    var filteredChannels: [Channel] {
        TagFilter.filter(channels, anyOf: selectedTagIDs)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// All chips shown in the Guide: editorial tags + the user's tags, de-duped.
    var chipTags: [Tag] { editorialTags }

    func refresh() async {
        let catalog = await remoteConfig.currentCatalog()
        let curated = catalog.asChannels()
        let user = localStore.userChannels()
        var dict: [String: Tag] = [:]
        for tag in catalog.editorialTags() { dict[tag.id] = tag }
        self.tagsByID = dict
        self.editorialTags = catalog.editorialTags()
        self.channels = ChannelMerger.merge(curated: curated, user: user)
        self.favoriteIDs = localStore.favoriteChannelIDs()
    }

    func resolveTags(_ channel: Channel) -> [Tag] {
        TagFilter.resolve(channel.tagIDs, in: tagsByID)
    }

    func toggleTag(_ id: String) {
        if selectedTagIDs.contains(id) { selectedTagIDs.remove(id) } else { selectedTagIDs.insert(id) }
    }

    func toggleFavorite(_ channel: Channel) {
        let now = !favoriteIDs.contains(channel.id)
        localStore.setFavorite(channelID: channel.id, isFavorite: now)
        favoriteIDs = localStore.favoriteChannelIDs()
    }

    func isFavorite(_ channel: Channel) -> Bool { favoriteIDs.contains(channel.id) }
}
```

- [ ] **Step 2: Write `Sources/UI/TagChipBar.swift`**

```swift
import SwiftUI

struct TagChipBar: View {
    let tags: [Tag]
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isOn: selected.isEmpty) { onToggle("__all__") }
                ForEach(tags) { tag in
                    chip(title: tag.name, isOn: selected.contains(tag.id)) { onToggle(tag.id) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .bold : .regular))
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(isOn ? Color.white : Color.white.opacity(0.12))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Write `Sources/UI/ChannelTile.swift`**

```swift
import SwiftUI

struct ChannelTile: View {
    let channel: Channel
    let isFavorite: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: channel.resolvedThumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(height: 96)
                .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .center, endPoint: .bottom)

                HStack {
                    Text(channel.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if channel.isLiveExpected {
                        Text("● LIVE").font(.caption2.weight(.bold)).foregroundStyle(.red)
                    }
                }
                .padding(8)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2).foregroundStyle(.yellow)
                        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Write `Sources/UI/GuideView.swift`**

```swift
import SwiftUI

struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TagChipBar(tags: store.chipTags, selected: store.selectedTagIDs) { id in
                    if id == "__all__" { store.selectedTagIDs.removeAll() } else { store.toggleTag(id) }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.filteredChannels) { channel in
                        ChannelTile(channel: channel, isFavorite: store.isFavorite(channel)) {
                            onSelect(channel)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Guide")
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }
}
```

- [ ] **Step 5: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add ChannelStore and Guide UI"
```

---

## Task 11: Player UI + ambient overlay

**Files:**
- Create: `Sources/UI/PlayerWebView.swift`
- Create: `Sources/UI/PlayerOverlay.swift`
- Create: `Sources/UI/PlayerView.swift`

- [ ] **Step 1: Write `Sources/UI/PlayerWebView.swift`** (bridges the WKWebView into SwiftUI)

```swift
import SwiftUI
import WebKit

struct PlayerWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
```

- [ ] **Step 2: Write `Sources/UI/PlayerOverlay.swift`**

```swift
import SwiftUI

struct PlayerOverlay: View {
    @ObservedObject var controller: PlaybackController
    let showClock: Bool
    let dimOpacity: Double
    let onSurf: (SurfDirection) -> Void
    let onToggleFavorite: () -> Void
    let isFavorite: Bool
    let onStartSleep: () -> Void
    let onClose: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        if let c = controller.currentChannel {
                            if c.isLiveExpected { Text("● LIVE").font(.caption.bold()).foregroundStyle(.red) }
                            Text(c.title).font(.headline)
                        }
                    }
                    Spacer()
                    Button(action: onClose) { Image(systemName: "chevron.down") }
                }
                .padding()

                Spacer()

                // Surf affordance
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button { onSurf(.previous) } label: { Image(systemName: "chevron.up") }
                        Text("SURF").font(.caption2)
                        Button { onSurf(.next) } label: { Image(systemName: "chevron.down") }
                    }
                    .padding(.trailing)
                }

                Spacer()

                if showClock {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 56, weight: .thin))
                        .onReceive(timer) { now = $0 }
                }

                HStack(spacing: 22) {
                    Button { controller.state == .playing ? controller.pauseFromUI() : controller.playFromUI() } label: {
                        Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                    }
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                    }
                    Button(action: onStartSleep) {
                        Image(systemName: controller.sleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                    }
                }
                .font(.title2)
                .padding(.bottom, 24)
            }
            .foregroundStyle(.white)

            if controller.showsOfflineState {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.largeTitle)
                    Text("This stream is offline").font(.headline)
                    Button("Next channel") { onSurf(.next) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
            }
        }
    }
}
```

This references `controller.playFromUI()` / `controller.pauseFromUI()` — add them in Step 3.

- [ ] **Step 3: Add UI-facing play/pause passthroughs to `Sources/Playback/PlaybackController.swift`**

Insert these methods into `PlaybackController` (after `surf`):

```swift
    func playFromUI() { player.play() }
    func pauseFromUI() { player.pause() }
```

- [ ] **Step 4: Write `Sources/UI/PlayerView.swift`**

```swift
import SwiftUI

struct PlayerView: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var store: ChannelStore
    let webView: WebViewPlayerService
    var settings: AppSettings
    let onClose: () -> Void

    @State private var overlayVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerWebView(webView: webView.webView).ignoresSafeArea()

            if overlayVisible {
                PlayerOverlay(
                    controller: controller,
                    showClock: settings.showClockOverlay,
                    dimOpacity: Double(settings.dimLevelRaw) * 0.2,
                    onSurf: { controller.surf($0) },
                    onToggleFavorite: { if let c = controller.currentChannel { store.toggleFavorite(c) } },
                    isFavorite: controller.currentChannel.map { store.isFavorite($0) } ?? false,
                    onStartSleep: { controller.startSleepTimer(seconds: Double(settings.defaultSleepMinutes) * 60) },
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { overlayVisible.toggle() } }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.height < -30 { controller.surf(.next) }
                else if value.translation.height > 30 { controller.surf(.previous) }
            }
        )
        .statusBarHidden(true)
    }
}
```

- [ ] **Step 5: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add fullscreen Player UI with ambient overlay and surf"
```

---

## Task 12: Add Channel UI (validate at add-time)

**Files:**
- Create: `Sources/Player/ChannelValidator.swift`
- Create: `Sources/UI/AddChannelView.swift`
- Create: `Tests/ChannelValidatorTests.swift`

- [ ] **Step 1: Write the failing test `Tests/ChannelValidatorTests.swift`**

```swift
import XCTest
@testable import Televista

final class ChannelValidatorTests: XCTestCase {
    func test_rejectsUnparseableInput() {
        let result = ChannelValidator.parseReference("just some text")
        XCTAssertNil(result)
    }
    func test_acceptsVideoURL() {
        let result = ChannelValidator.parseReference("https://youtu.be/jfKfPfyJRdk")
        XCTAssertEqual(result, .video(id: "jfKfPfyJRdk"))
    }
    func test_buildsChannelFromVideoReference() {
        let channel = ChannelValidator.makeUserChannel(
            from: .video(id: "jfKfPfyJRdk"), title: "Lofi", tagIDs: ["lofi"], now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(channel?.youTubeVideoID, "jfKfPfyJRdk")
        XCTAssertEqual(channel?.source, .user)
        XCTAssertEqual(channel?.tagIDs, ["lofi"])
    }
    func test_handleReferenceCannotBecomeChannelDirectly() {
        // Handles need resolution to a video id; not supported offline in #1.
        let channel = ChannelValidator.makeUserChannel(
            from: .handle("LofiGirl"), title: "Lofi", tagIDs: [], now: Date())
        XCTAssertNil(channel)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: FAIL — `ChannelValidator` unresolved.

- [ ] **Step 3: Write `Sources/Player/ChannelValidator.swift`**

```swift
import Foundation

/// Add-time validation for user channels. Parsing + channel construction are pure
/// and unit-tested; embeddability is verified live by attempting to load in the
/// player (the UI surfaces `embeddingDisallowed` if YouTube rejects it).
enum ChannelValidator {
    static func parseReference(_ input: String) -> YouTubeReference? {
        YouTubeURLParser.parse(input)
    }

    /// Builds a `.user` channel from a video reference. Handles are not directly
    /// playable in sub-project #1 (they require API resolution to a video id).
    static func makeUserChannel(from reference: YouTubeReference, title: String,
                                tagIDs: [String], now: Date) -> Channel? {
        guard case let .video(id) = reference else { return nil }
        let resolvedTitle = title.trimmingCharacters(in: .whitespaces)
        return Channel(
            id: "user-\(id)",
            title: resolvedTitle.isEmpty ? "Untitled" : resolvedTitle,
            youTubeVideoID: id,
            source: .user,
            isLiveExpected: true,
            dateAdded: now,
            tagIDs: tagIDs
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Write `Sources/UI/AddChannelView.swift`**

```swift
import SwiftUI

struct AddChannelView: View {
    @ObservedObject var store: ChannelStore
    let localStore: LocalStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var title = ""
    @State private var selectedTagIDs: Set<String> = []
    @State private var error: String?

    private var reference: YouTubeReference? { ChannelValidator.parseReference(urlText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("YouTube link") {
                    TextField("https://youtube.com/watch?v=… or youtu.be/…", text: $urlText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !urlText.isEmpty {
                        switch reference {
                        case .video:  Label("Valid video link", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .handle: Label("Handles aren't supported yet — paste a video/live link", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        case nil:     Label("Not a recognizable YouTube link", systemImage: "xmark.circle").foregroundStyle(.red)
                        }
                    }
                }
                Section("Title") { TextField("Channel name", text: $title) }
                Section("Tags") {
                    ForEach(store.editorialTags) { tag in
                        Button {
                            if selectedTagIDs.contains(tag.id) { selectedTagIDs.remove(tag.id) }
                            else { selectedTagIDs.insert(tag.id) }
                        } label: {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if selectedTagIDs.contains(tag.id) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add Channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { save() }.disabled(!canSave) }
            }
        }
    }

    private var canSave: Bool {
        if case .video = reference { return true }
        return false
    }

    private func save() {
        guard let reference,
              let channel = ChannelValidator.makeUserChannel(
                from: reference, title: title, tagIDs: Array(selectedTagIDs), now: Date()) else {
            error = "Couldn't build a channel from that link."
            return
        }
        localStore.addUserChannel(channel)
        onSaved()
        dismiss()
    }
}
```

- [ ] **Step 6: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Add Channel flow with add-time validation"
```

---

## Task 13: Settings UI

**Files:**
- Create: `Sources/UI/SettingsView.swift`

- [ ] **Step 1: Write `Sources/UI/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    let localStore: LocalStore
    @State private var settings: AppSettings

    init(localStore: LocalStore) {
        self.localStore = localStore
        _settings = State(initialValue: localStore.settings())
    }

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Auto-resume last channel", isOn: $settings.autoResume)
                Toggle("Audio-only (best-effort)", isOn: $settings.audioOnly)
                Stepper("Default sleep timer: \(settings.defaultSleepMinutes) min",
                        value: $settings.defaultSleepMinutes, in: 5...120, step: 5)
            }
            Section("Display") {
                Toggle("Show clock overlay", isOn: $settings.showClockOverlay)
                Picker("Dim level", selection: $settings.dimLevelRaw) {
                    Text("None").tag(0); Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3)
                }
            }
            Section("Account") {
                HStack { Text("Sign in with Apple"); Spacer(); Text("Later").foregroundStyle(.secondary) }
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings) { _, newValue in localStore.saveSettings(newValue) }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Settings UI"
```

---

## Task 14: App assembly, navigation, and auto-resume

**Files:**
- Modify: `Sources/UI/TelevistaApp.swift` (replace placeholder)
- Create: `Sources/UI/RootView.swift`
- Create: `Sources/App/AppEnvironment.swift`

- [ ] **Step 1: Write `Sources/App/AppEnvironment.swift`** (composition root)

```swift
import Foundation
import SwiftData

/// Wires concrete dependencies together once, at launch.
@MainActor
final class AppEnvironment: ObservableObject {
    let localStore: LocalStore
    let channelStore: ChannelStore
    let player: WebViewPlayerService
    let controller: PlaybackController

    init(container: ModelContainer) {
        let local = LocalStore(context: container.mainContext)
        let cache = FileCatalogCache()
        let bundled = AppEnvironment.loadBundledCatalog()
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let remote = RemoteConfig(
            baseURL: Config.catalogBaseURL, session: .shared, cache: cache,
            supportedSchema: Config.supportedSchemaVersion, appVersion: appVersion,
            bundledLoader: { bundled })
        let store = ChannelStore(remoteConfig: remote, localStore: local)
        let webPlayer = WebViewPlayerService()
        let playback = PlaybackController(player: webPlayer, clock: SystemClock())

        self.localStore = local
        self.channelStore = store
        self.player = webPlayer
        self.controller = playback

        playback.onChannelChanged = { [weak local] channel in
            local?.setLastWatched(channelID: channel.id)
        }
    }

    private static func loadBundledCatalog() -> Catalog {
        guard let url = Bundle.main.url(forResource: "catalog-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? Catalog.decode(from: data) else {
            return Catalog(schemaVersion: 1, tags: [:], channels: [])
        }
        return catalog
    }
}
```

- [ ] **Step 2: Write `Sources/UI/RootView.swift`**

```swift
import SwiftUI

struct RootView: View {
    @ObservedObject var env: AppEnvironment
    @State private var playing: Channel?
    @State private var showAddChannel = false

    var body: some View {
        NavigationStack {
            GuideView(store: env.channelStore) { channel in
                startPlaying(channel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView(localStore: env.localStore) } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddChannel = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .fullScreenCover(item: $playing) { _ in
            PlayerView(
                controller: env.controller, store: env.channelStore, webView: env.player,
                settings: env.localStore.settings(),
                onClose: { playing = nil }
            )
        }
        .sheet(isPresented: $showAddChannel) {
            AddChannelView(store: env.channelStore, localStore: env.localStore) {
                Task { await env.channelStore.refresh() }
            }
        }
        .task { await maybeAutoResume() }
    }

    private func startPlaying(_ channel: Channel) {
        env.controller.setLineup(env.channelStore.filteredChannels)
        env.controller.play(channelID: channel.id)
        playing = channel
    }

    private func maybeAutoResume() async {
        await env.channelStore.refresh()
        guard env.localStore.settings().autoResume,
              let lastID = env.localStore.lastWatchedChannelID(),
              let channel = env.channelStore.channels.first(where: { $0.id == lastID }) else { return }
        startPlaying(channel)
    }
}
```

- [ ] **Step 3: Replace `Sources/UI/TelevistaApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct TelevistaApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        let container = (try? Persistence.makeContainer()) ?? {
            // Fall back to in-memory if the on-disk store can't be opened.
            try! Persistence.makeContainer(inMemory: true)
        }()
        _env = StateObject(wrappedValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
                .preferredColorScheme(.dark)
        }
    }
}
```

- [ ] **Step 4: Regenerate and run the full test suite**

Run: `xcodegen generate && xcodebuild test -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Manual smoke (the spec's integration check)**

Run the app in the simulator:
`xcodebuild build -project Televista.xcodeproj -scheme Televista -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet` then launch via Xcode or `xcrun simctl`.
Confirm: Guide shows the bundled lineup; tapping a tile opens fullscreen and a known-good livestream (e.g. Lofi `jfKfPfyJRdk`) plays; tag chips filter; swipe up/down surfs; Add Channel validates a pasted `youtu.be` link; Settings toggles persist across relaunch; with auto-resume on, relaunch reopens the last channel.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: assemble app with navigation and auto-resume"
```

---

## Self-Review Notes (addressed)

- **Spec coverage:** PlayerService boundary (T6/T9), iframe player (T9), Guide+surf (T10/T11), ambient features — sleep timer (T7), clock/dim (T11/T13), audio-only flag (T8/T13, best-effort), auto-resume (T14); versioned catalog manifest/URL + resilience ladder + ETag (T4); user-added + add-time validation (T12); editorial+user tags & union filtering (T1/T2/T5/T10); SwiftData with `userID` field present but nil (T8); AirPlay comes via the system route picker on the embedded `AVPlayer` (no extra code; documented). Derived tags/leaderboard, Sign in with Apple/CloudKit sync, and tvOS are correctly deferred (stubbed account row in T13).
- **Audio-only / background:** `UIBackgroundModes: [audio]` is declared in `project.yml` (T0); the toggle persists (T8/T13). Actual backgrounded web audio remains best-effort per the spec's ToS caveat — no behavior is promised beyond the flag.
- **Type consistency:** `PlayerService` API (`load/play/pause/setVolume/setMuted`, `PlayerState`, `PlayerEvent`) is identical across `MockPlayerService`, `WebViewPlayerService`, and `PlaybackController`. `Channel.tagIDs`, `Tag`, `Catalog.asChannels()/editorialTags()`, `CatalogCache` signatures, and `LocalStore`/`AppSettings` fields match every consumer.
- **Note for implementers:** Real playback (T9) can only be smoke-tested after the Player UI exists (T11/T14); that's called out in T9 Step 4 and verified in T14 Step 5.
