import SwiftUI

/// A custom SwiftUI Layout that wraps views horizontally to fit the container width.
/// `alignment` controls how each wrapped row is justified within the container
/// (`.leading` by default; `.center` and `.trailing` are also supported).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = computeRows(width: width, subviews: subviews)
        let height = rows.reduce(into: CGFloat(0)) { $0 += $1.height }
            + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(width: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            let leadingInset: CGFloat
            switch alignment {
            case .center: leadingInset = (bounds.width - row.width) / 2
            case .trailing: leadingInset = bounds.width - row.width
            default: leadingInset = 0
            }
            var currentX = bounds.minX + max(0, leadingInset)

            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
                currentX += item.size.width + spacing
            }
            currentY += row.height + spacing
        }
    }

    // MARK: - Row computation

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0   // total content width, excluding trailing spacing
        var height: CGFloat = 0
    }

    private func computeRows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var currentX: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, !current.items.isEmpty {
                current.width = currentX - spacing
                rows.append(current)
                current = Row()
                currentX = 0
            }
            current.items.append(Item(index: index, size: size))
            current.height = max(current.height, size.height)
            currentX += size.width + spacing
        }
        if !current.items.isEmpty {
            current.width = currentX - spacing
            rows.append(current)
        }
        return rows
    }
}
