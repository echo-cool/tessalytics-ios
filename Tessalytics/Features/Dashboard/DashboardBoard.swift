import SwiftUI
import UniformTypeIdentifiers

//  The dashboard as a board rather than a single column.
//
//  One tall column is right on a phone and wrong on an iPad in landscape, where
//  it leaves two thirds of a 1,376-point window as margin. The board takes the
//  width it is given, splits into two or three columns when there is room, and
//  collapses back to one when there is not — so the same cards serve a phone, an
//  iPad in either orientation, and a Mac window being dragged wider.
//
//  The order is the owner's. What matters on a dashboard is personal — someone
//  who watches charge state wants it first, someone who watches tyres does not —
//  and the arrangement is remembered per install.

/// One card on the dashboard, addressable so its position can be remembered.
///
/// Raw values are persisted, so they are part of the stored format: renaming a
/// case silently discards that card's saved position. Adding one is safe — an id
/// the stored order has never seen falls in at its natural place.
enum DashboardCardID: String, CaseIterable, Identifiable, Sendable {
    case hero
    case historyNotice
    case quickLinks
    case directTesla
    case destinations
    case liveDrive
    case liveCharge
    case batteryCapacity
    case places
    case recentDriving
    case telemetry
    case latestDrive
    case driveStats
    case chargingSummary
    case chargingStatus
    case security
    case tyres
    case activity
    case details
    case statusRefresh

    var id: String { rawValue }

    /// Named for the arrange mode, where a card is a thing being moved rather
    /// than a thing being read.
    var title: String {
        switch self {
        case .hero: "Vehicle"
        case .historyNotice: "Still collecting"
        case .quickLinks: "Quick links"
        case .directTesla: "Direct Tesla"
        case .destinations: "Send to car"
        case .liveDrive: "Live drive"
        case .liveCharge: "Live charge"
        case .batteryCapacity: "Battery capacity"
        case .places: "Places"
        case .recentDriving: "Recent driving"
        case .telemetry: "Telemetry"
        case .latestDrive: "Latest drive"
        case .driveStats: "Driving totals"
        case .chargingSummary: "Charging totals"
        case .chargingStatus: "Charging"
        case .security: "Security"
        case .tyres: "Tyres"
        case .activity: "Activity"
        case .details: "Vehicle details"
        case .statusRefresh: "Status"
        }
    }

    /// Cards that are the point of the screen and stay put.
    ///
    /// The hero card is the answer to "what is my car doing", and a board whose
    /// first tile can be dragged to the bottom is a board someone will get wrong
    /// once and not know how to undo. Live sections are pinned for the same
    /// reason: while the car is moving they are the only thing worth reading.
    var isPinned: Bool {
        switch self {
        case .hero, .historyNotice, .liveDrive, .liveCharge, .statusRefresh: true
        default: false
        }
    }
}

/// A card and the view that draws it.
struct DashboardCard: Identifiable {
    let id: DashboardCardID
    let content: AnyView

    init(_ id: DashboardCardID, @ViewBuilder content: () -> some View) {
        self.id = id
        self.content = AnyView(content())
    }
}

/// The owner's arrangement, remembered across launches.
///
/// Stored as raw values joined by a comma rather than as JSON: it is a list of
/// short strings, and a format that can be read in a defaults dump is easier to
/// support than one that cannot.
struct DashboardArrangement {
    private(set) var order: [DashboardCardID]

    init(stored: String) {
        let parsed = stored
            .split(separator: ",")
            .compactMap { DashboardCardID(rawValue: String($0)) }
        // Anything the stored order has never heard of — a card added by a later
        // release — keeps its natural position rather than being dropped.
        var seen = Set(parsed)
        var complete = parsed
        for card in DashboardCardID.allCases where !seen.contains(card) {
            complete.append(card)
            seen.insert(card)
        }
        order = complete
    }

    var stored: String { order.map(\.rawValue).joined(separator: ",") }

    /// Sorts the visible cards into the owner's order.
    func arrange(_ cards: [DashboardCard]) -> [DashboardCard] {
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return cards.sorted { (position[$0.id] ?? .max) < (position[$1.id] ?? .max) }
    }

    /// Moves `moved` so that it sits where `target` currently is.
    mutating func move(_ moved: DashboardCardID, before target: DashboardCardID) {
        guard moved != target, !moved.isPinned, !target.isPinned,
              let from = order.firstIndex(of: moved) else { return }
        order.remove(at: from)
        guard let to = order.firstIndex(of: target) else {
            order.insert(moved, at: min(from, order.count))
            return
        }
        order.insert(moved, at: to)
    }

    mutating func reset() { order = DashboardCardID.allCases }
}

/// Lays the cards out in as many columns as the width allows.
struct DashboardBoard: View {
    let cards: [DashboardCard]
    @Binding var storedOrder: String
    /// True while the owner is rearranging, which suppresses the cards' own
    /// gestures so a long press moves the card rather than scrubbing a chart.
    let isArranging: Bool

    @State private var available: CGFloat = 0
    @State private var dragging: DashboardCardID?

    private var arrangement: DashboardArrangement { DashboardArrangement(stored: storedOrder) }

    /// Measured against the widths this actually runs at rather than picked as
    /// round numbers: an iPad Pro 13 gives the board about 1,008 points in
    /// portrait and about 1,072 in landscape once the sidebar and the page
    /// padding are taken off. The three-column step sits between the two, so
    /// turning the iPad gains a column instead of just stretching the cards.
    /// A phone is far below both and stays a single list.
    private var columnCount: Int {
        guard available > 0 else { return 1 }
        if available >= 1_050 { return 3 }
        if available >= 780 { return 2 }
        return 1
    }

    private var ordered: [DashboardCard] { arrangement.arrange(cards) }

    /// Round-robin rather than balanced by height: the owner set this order, and
    /// a layout that reshuffles to even the columns out would move a card they
    /// deliberately put second.
    private var columns: [[DashboardCard]] {
        let count = columnCount
        guard count > 1 else { return [ordered] }
        var result = Array(repeating: [DashboardCard](), count: count)
        for (index, card) in ordered.enumerated() {
            result[index % count].append(card)
        }
        return result
    }

    var body: some View {
        Group {
            if columnCount > 1 {
                HStack(alignment: .top, spacing: TessalyticsLayout.stackSpacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                            ForEach(column) { card in tile(card) }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            } else {
                LazyVStack(spacing: TessalyticsLayout.stackSpacing) {
                    ForEach(ordered) { card in tile(card) }
                }
                // One column still reads as a column rather than as the window.
                .tessalyticsReadableWidth()
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { available = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in available = width }
            }
            .accessibilityHidden(true)
        )
    }

    @ViewBuilder private func tile(_ card: DashboardCard) -> some View {
        let movable = isArranging && !card.id.isPinned
        // The content is made inert while arranging so a chart cannot scrub
        // under the finger — but it has to be the *content* that goes inert and
        // the container that stays live. Disabling hit testing on the same view
        // the drag is attached to disables the drag as well, which is exactly
        // what happened: the board scrolled instead of moving the card.
        ZStack { card.content.allowsHitTesting(!isArranging) }
            .contentShape(.rect)
            .opacity(dragging == card.id ? 0.35 : 1)
            .overlay {
                if isArranging {
                    RoundedRectangle(cornerRadius: TessalyticsTheme.cardRadius, style: .continuous)
                        .strokeBorder(
                            movable ? TessalyticsTheme.accent : TessalyticsTheme.steel.opacity(0.35),
                            style: StrokeStyle(lineWidth: 2, dash: movable ? [] : [5, 4])
                        )
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isArranging { badge(for: card.id) }
            }
            .if(movable) { view in
                view
                    .draggable(card.id.rawValue) {
                        // What follows the finger: the card itself would be a
                        // half-screen preview on an iPad.
                        Label(card.id.title, systemImage: "square.grid.2x2")
                            .padding(10)
                            .background(.regularMaterial, in: .capsule)
                    }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let moved = DashboardCardID(rawValue: raw) else { return false }
                var updated = arrangement
                updated.move(moved, before: card.id)
                storedOrder = updated.stored
                dragging = nil
                return true
            } isTargeted: { targeted in
                dragging = targeted ? dragging : dragging
            }
    }

    @ViewBuilder private func badge(for id: DashboardCardID) -> some View {
        Image(systemName: id.isPinned ? "pin.fill" : "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(id.isPinned ? TessalyticsTheme.steel : Color.white)
            .padding(6)
            .background(id.isPinned ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(TessalyticsTheme.accent), in: .circle)
            .padding(8)
            .accessibilityLabel(id.isPinned ? "\(id.title), fixed" : "\(id.title), drag to move")
    }
}

extension View {
    /// Applies a modifier only when a condition holds.
    ///
    /// Used here for `draggable`, which cannot be applied conditionally inside a
    /// modifier chain without changing the view's identity when it is absent.
    @ViewBuilder func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
