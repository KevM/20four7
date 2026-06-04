import SwiftUI

/// Size-class–driven layout metrics — the single source of truth for how the UI
/// scales between phone-width and iPad-width layouts.
///
/// `wide` is true when the view has a **regular** horizontal size class (a
/// full-screen iPad) and false in **compact** width (iPhone, or an iPad in a
/// narrow Split View / Slide Over pane). Keying off the size class rather than
/// `UIDevice.current.userInterfaceIdiom` means the layout adapts correctly to
/// multitasking and re-lays-out reactively when the window resizes or rotates —
/// the device idiom never changes and would size a narrow split pane as if it
/// were a full iPad.
///
/// Fonts use semantic text styles (`.body`, `.headline`, …) wherever possible so
/// they continue to honor Dynamic Type; fixed point sizes are reserved for glyphs
/// in fixed-size chrome (e.g. the close button, media controls).
struct LayoutMetrics {
    let wide: Bool

    init(_ sizeClass: UserInterfaceSizeClass?) {
        self.wide = sizeClass == .regular
    }

    // MARK: Guide grid
    var tileMinWidth: CGFloat { wide ? 220 : 150 }
    var gridSpacing: CGFloat { wide ? 12 : 8 }
    var gridHPadding: CGFloat { wide ? 24 : 12 }

    // Featured top tiles — the first `featuredRowCount` rows of the ranked
    // guide render ~1.2× larger on wide layouts. `featuredRowCount` is 0 on
    // compact, which is what disables featuring there (callers treat a count
    // of 0 as "render the normal grid only").
    var featuredTileMinWidth: CGFloat { wide ? 264 : tileMinWidth }
    var featuredTileHeight: CGFloat { wide ? 162 : tileHeight }
    var featuredRowCount: Int { wide ? 2 : 0 }

    /// How many featured-size columns fit in `availableWidth` (the content
    /// width already inside `gridHPadding`). Always at least 1.
    func featuredColumnCount(availableWidth: CGFloat) -> Int {
        let columns = Int((availableWidth + gridSpacing) / (featuredTileMinWidth + gridSpacing))
        return max(1, columns)
    }

    /// Total channels to feature: `featuredRowCount` full rows at the featured
    /// size. Zero on compact (featuring disabled).
    func featuredChannelCount(availableWidth: CGFloat) -> Int {
        featuredRowCount * featuredColumnCount(availableWidth: availableWidth)
    }

    // MARK: Channel tile
    var tileHeight: CGFloat { wide ? 135 : 96 }
    var tileCornerRadius: CGFloat { wide ? 16 : 12 }
    var tilePadding: CGFloat { wide ? 12 : 8 }
    var tileTitleFont: Font { (wide ? Font.body : .caption).weight(.semibold) }
    var tileOfflineFont: Font { (wide ? Font.caption : .caption2).weight(.bold) }
    var tileOfflineHPadding: CGFloat { wide ? 8 : 6 }
    var tileOfflineVPadding: CGFloat { wide ? 4 : 2 }
    var tileFavoriteFont: Font { wide ? .caption : .caption2 }
    var contextMenuPreviewWidth: CGFloat { wide ? 460 : 320 }
    var contextMenuPreviewHeight: CGFloat { wide ? 259 : 180 }
    var contextMenuPreviewTitleFont: Font { (wide ? Font.title2 : .headline).weight(.bold) }
    var contextMenuPreviewOfflineFont: Font { (wide ? Font.body : .caption).weight(.bold) }
    var contextMenuPreviewOfflineHPadding: CGFloat { wide ? 12 : 8 }
    var contextMenuPreviewOfflineVPadding: CGFloat { wide ? 6 : 4 }

    // MARK: Tag chips
    var chipRowSpacing: CGFloat { wide ? 12 : 8 }
    var chipRowHPadding: CGFloat { wide ? 24 : 16 }
    var chipInnerSpacing: CGFloat { wide ? 8 : 6 }
    var chipFont: Font { wide ? .body : .subheadline }   // weight applied per-state at call site
    var chipCountFont: Font { (wide ? Font.caption : .caption2).weight(.bold) }
    var chipCountHPadding: CGFloat { wide ? 7 : 5 }
    var chipCountVPadding: CGFloat { wide ? 2.5 : 1.5 }
    var chipVPadding: CGFloat { wide ? 10 : 6 }
    var chipHPadding: CGFloat { wide ? 16 : 12 }

    // MARK: Player overlay — title card
    var overlayTitleStackSpacing: CGFloat { wide ? 6 : 4 }
    var overlayLiveFont: Font { (wide ? Font.subheadline : .caption).bold() }
    var overlayTitleFont: Font { (wide ? Font.title3 : .headline).weight(.bold) }
    var overlayCardHPadding: CGFloat { wide ? 18 : 14 }
    var overlayCardVPadding: CGFloat { wide ? 14 : 10 }
    var overlayCardCorner: CGFloat { wide ? 20 : 16 }

    // MARK: Player overlay — controls
    var controlsSpacing: CGFloat { wide ? 36 : 22 }
    var controlSize: CGFloat { wide ? 64 : 44 }
    var controlsFont: Font { wide ? .system(size: 32) : .title2 }
    var controlsHPadding: CGFloat { wide ? 24 : 16 }
    var controlsVPadding: CGFloat { wide ? 12 : 8 }
    var controlsBottomPadding: CGFloat { wide ? 40 : 24 }

    // MARK: YouTube Browser
    var browserOverlayPadding: CGFloat { wide ? 24 : 16 }
    var browserOverlayCornerRadius: CGFloat { wide ? 16 : 12 }
    var browserOverlayButtonFont: Font { (wide ? Font.body : .subheadline).weight(.semibold) }
    var browserTitleFont: Font { (wide ? Font.headline : .subheadline).weight(.semibold) }
}
