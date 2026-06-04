import XCTest
import SwiftUI
@testable import TwentyFourSeven

final class LayoutMetricsTests: XCTestCase {

    // MARK: Featured sizing per size class

    func test_featuredSizing_wide() {
        let m = LayoutMetrics(.regular)
        XCTAssertEqual(m.featuredTileMinWidth, 264)
        XCTAssertEqual(m.featuredTileHeight, 162)
        XCTAssertEqual(m.featuredRowCount, 2)
    }

    func test_featuredSizing_compact_disablesFeaturing() {
        let m = LayoutMetrics(.compact)
        // On compact, featuring is off: zero rows, and sizes fall back to normal.
        XCTAssertEqual(m.featuredRowCount, 0)
        XCTAssertEqual(m.featuredTileMinWidth, m.tileMinWidth)
        XCTAssertEqual(m.featuredTileHeight, m.tileHeight)
    }

    // MARK: Column count from available width (wide: minWidth 264, spacing 12)

    func test_featuredColumnCount_portraitWidth() {
        let m = LayoutMetrics(.regular)
        // 762 content width: floor((762+12)/(264+12)) = floor(774/276) = 2
        XCTAssertEqual(m.featuredColumnCount(availableWidth: 762), 2)
    }

    func test_featuredColumnCount_landscapeWidth() {
        let m = LayoutMetrics(.regular)
        // 1032 content width: floor((1032+12)/276) = floor(1044/276) = 3
        XCTAssertEqual(m.featuredColumnCount(availableWidth: 1032), 3)
    }

    func test_featuredColumnCount_clampsToAtLeastOne() {
        let m = LayoutMetrics(.regular)
        // Narrower than one featured tile still yields one column, never zero.
        XCTAssertEqual(m.featuredColumnCount(availableWidth: 100), 1)
        XCTAssertEqual(m.featuredColumnCount(availableWidth: 0), 1)
    }

    // MARK: Featured channel count = rows * columns

    func test_featuredChannelCount_wide_isRowsTimesColumns() {
        let m = LayoutMetrics(.regular)
        // 2 rows * 3 columns at 1032 wide = 6
        XCTAssertEqual(m.featuredChannelCount(availableWidth: 1032), 6)
        // 2 rows * 2 columns at 762 = 4
        XCTAssertEqual(m.featuredChannelCount(availableWidth: 762), 4)
    }

    func test_featuredChannelCount_compact_isZero() {
        let m = LayoutMetrics(.compact)
        // featuredRowCount 0 => no featured channels regardless of width.
        XCTAssertEqual(m.featuredChannelCount(availableWidth: 1032), 0)
    }
}
