import XCTest
@testable import TwentyFourSeven

final class ChannelSearchTests: XCTestCase {
    private let tagsByID: [String: Tag] = [
        "nature": Tag(id: "nature", name: "Nature", symbol: "leaf", kind: .editorial),
        "lofi": Tag(id: "lofi", name: "Lofi", symbol: "music.note", kind: .editorial),
        "café": Tag(id: "café", name: "Café Music", symbol: "cup.and.saucer", kind: .user)
    ]
    
    private var channels: [Channel] {
        [
            Channel(id: "c1", title: "Forest Sounds", youTubeVideoID: "v1", source: .curated,
                    isLiveExpected: true, tagIDs: ["nature"]),
            Channel(id: "c2", title: "Study Beats", youTubeVideoID: "v2", source: .curated,
                    isLiveExpected: true, tagIDs: ["lofi"]),
            Channel(id: "c3", title: "Café Ambient", youTubeVideoID: "v3", source: .curated,
                    isLiveExpected: true, tagIDs: ["café"]),
            Channel(id: "c4", title: "Rainy Afternoon", youTubeVideoID: "v4", source: .curated,
                    isLiveExpected: true, tagIDs: ["nature", "lofi"])
        ]
    }
    
    func test_emptyOrWhitespaceQueryReturnsAll() {
        let emptyResult = ChannelSearch.filter(channels, query: "", tagsByID: tagsByID)
        XCTAssertEqual(emptyResult.count, 4)
        
        let whitespaceResult = ChannelSearch.filter(channels, query: "   \n  ", tagsByID: tagsByID)
        XCTAssertEqual(whitespaceResult.count, 4)
    }
    
    func test_titleSubstringMatch() {
        let result = ChannelSearch.filter(channels, query: "Forest", tagsByID: tagsByID)
        XCTAssertEqual(result.map(\.id), ["c1"])
        
        let result2 = ChannelSearch.filter(channels, query: "Rainy", tagsByID: tagsByID)
        XCTAssertEqual(result2.map(\.id), ["c4"])
        
        let result3 = ChannelSearch.filter(channels, query: "Ambient", tagsByID: tagsByID)
        XCTAssertEqual(result3.map(\.id), ["c3"])
    }
    
    func test_tagNameMatch() {
        let result = ChannelSearch.filter(channels, query: "Nature", tagsByID: tagsByID)
        XCTAssertEqual(Set(result.map(\.id)), ["c1", "c4"])
        
        let result2 = ChannelSearch.filter(channels, query: "Lofi", tagsByID: tagsByID)
        XCTAssertEqual(Set(result2.map(\.id)), ["c2", "c4"])
    }
    
    func test_caseAndDiacriticInsensitivity() {
        // Test diacritic matching (search "cafe" matches "Café Ambient" title and "Café Music" tag name)
        let result = ChannelSearch.filter(channels, query: "cafe", tagsByID: tagsByID)
        XCTAssertEqual(result.map(\.id), ["c3"])
        
        // Test diacritic and case matching (search "CAFÉ" matches "Café Ambient" / "Café Music")
        let result2 = ChannelSearch.filter(channels, query: "CAFÉ", tagsByID: tagsByID)
        XCTAssertEqual(result2.map(\.id), ["c3"])
        
        // Test case insensitive title match
        let result3 = ChannelSearch.filter(channels, query: "forest", tagsByID: tagsByID)
        XCTAssertEqual(result3.map(\.id), ["c1"])
    }
}
