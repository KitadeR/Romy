import MapKit
import SwiftUI

/// The apps a route can be opened in (Notion 02 §6-5 「経路ボタンは他の地図アプリへ」; Rhyme's 「View Direction」).
enum RouteApp: String, CaseIterable, Identifiable {
    case apple, google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple マップ"
        case .google: "Google マップ"
        }
    }

    var symbol: String {
        switch self {
        case .apple: "map"
        case .google: "location.circle"
        }
    }
}

/// A route to open: from `origin` (nil = where the person is) to `destination`, by `mode` when one was chosen.
struct RouteRequest: Identifiable {
    let id = UUID()
    let origin: MKMapItem?
    let destination: MKMapItem
    let mode: TravelMode?
    /// How Google Maps is told where the ends are: the place's name and ward, which it can find and write on its
    /// screen (bare coordinates show up as 「指定した地点」).
    var originText: String?
    var destinationText: String?

    /// The route to `destination` from the plan before it (nil = from where the person is); nil when the
    /// destination has no place.
    static func route(to destination: ItineraryItem, from origin: ItineraryItem?, mode: TravelMode?) -> RouteRequest? {
        guard let end = RouteLink.mapItem(destination) else { return nil }
        return RouteRequest(
            origin: origin.flatMap { RouteLink.mapItem($0) }, destination: end, mode: mode,
            originText: origin.map { RouteLink.searchText($0) }, destinationText: RouteLink.searchText(destination)
        )
    }
}

/// 「いつもこのアプリで開く」: the app the person picked to be used without asking again.
enum RoutePreference {
    private static let key = "routeApp"

    static var current: RouteApp? {
        get { UserDefaults.standard.string(forKey: key).flatMap(RouteApp.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }
}

/// One end of a route for Google Maps: written as text when there is a name, as coordinates when not.
struct RoutePoint {
    let coordinate: CLLocationCoordinate2D
    var text: String?

    var query: String {
        if let text, !text.isEmpty { return text }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }
}

extension RouteLink {
    /// 「大阪駅 大阪市北区」: the name and ward of a plan, for Google Maps to find the place by.
    static func searchText(_ item: ItineraryItem) -> String {
        [item.title, item.area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Google Maps' route link. It opens the Google Maps app when it is installed and the web page when not.
    static func googleURL(
        from origin: RoutePoint?, to destination: RoutePoint, mode: TravelMode?
    ) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination.query)
        ]
        if let origin { items.append(URLQueryItem(name: "origin", value: origin.query)) }
        if let mode { items.append(URLQueryItem(name: "travelmode", value: mode.googleMode)) }
        components?.queryItems = items
        return components?.url
    }

    static func open(_ request: RouteRequest, in app: RouteApp) {
        switch app {
        case .apple:
            open(to: request.destination, from: request.origin, mode: request.mode)
        case .google:
            let from = request.origin.map { RoutePoint(coordinate: $0.location.coordinate, text: request.originText) }
            let end = RoutePoint(coordinate: request.destination.location.coordinate, text: request.destinationText)
            guard let url = googleURL(from: from, to: end, mode: request.mode) else { return }
            UIApplication.shared.open(url)
        }
    }

    /// Opens the route in the app the person always uses, or asks which one (`chooser`) when there is none yet
    /// or when `forceChoice` is set.
    static func start(_ request: RouteRequest, chooser: Binding<RouteRequest?>, forceChoice: Bool = false) {
        if !forceChoice, let app = RoutePreference.current {
            open(request, in: app)
        } else {
            chooser.wrappedValue = request
        }
    }
}

/// 「どのアプリで開く？」: Apple マップ or Google マップ, with a switch to use the pick from now on.
private struct RouteAppSheet: View {
    let request: RouteRequest
    @Environment(\.dismiss) private var dismiss
    @State private var remembers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("どのアプリで開く？")
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)
            ForEach(RouteApp.allCases) { app in
                Button {
                    if remembers { RoutePreference.current = app }
                    dismiss()
                    RouteLink.open(request, in: app)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: app.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.fill))
                        Text(app.title).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Toggle("いつもこのアプリで開く", isOn: $remembers)
                .font(Theme.jp(14, .medium))
                .tint(Theme.ink)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Theme.surface.ignoresSafeArea())
    }
}

extension View {
    /// Shows the app chooser for the route in `request` (set by `RouteLink.start`).
    func routeChooser(_ request: Binding<RouteRequest?>) -> some View {
        sheet(item: request) { request in
            RouteAppSheet(request: request)
                .presentationDetents([.height(320)])
        }
    }
}
