import AppKit

/// A stepped slider in the menu bar menu, like the volume slider in the
/// system Sound menu. SwiftUI menus can't hold a slider, so it's an AppKit
/// item put under its SwiftUI heading ("Grammar", "Humanize") each time the
/// menu opens.
///
/// Dragging updates the step name beside it right away but saves only when
/// the menu closes: saving publishes a change, and any change while the
/// menu is open makes SwiftUI rebuild the menu, which closes it.
@MainActor
final class MenuSliderItem: NSObject {
    static let grammar = MenuSliderItem(heading: "Grammar", names: Levels.grammar,
                                        get: { AppState.shared.grammar }, set: { AppState.shared.grammar = $0 })
    static let humanize = MenuSliderItem(heading: "Humanize", names: Levels.humanize,
                                         get: { AppState.shared.humanize }, set: { AppState.shared.humanize = $0 })

    let heading: String
    private let names: [String]
    private let get: () -> Double
    private let set: (Double) -> Void

    private var item = NSMenuItem()
    private var slider = NSSlider()
    private var label = NSTextField(labelWithString: "")
    private var isFresh = false
    private var unsaved: Double?
    private weak var openMenu: NSMenu?

    private init(heading: String, names: [String], get: @escaping () -> Double, set: @escaping (Double) -> Void) {
        self.heading = heading
        self.names = names
        self.get = get
        self.set = set
    }

    func install() {
        MenuOpening.observe { [weak self] menu in self?.opened(menu) }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] note in
            let menu = note.object as? NSMenu
            MainActor.assumeIsolated { self?.closed(menu) }
        }
    }

    private func opened(_ menu: NSMenu) {
        guard menu.items.contains(where: { $0.title == heading && $0 !== item }) else { return }
        guard item.menu !== menu || !isFresh else { return sync() }
        isFresh = true
        item.menu?.removeItem(item)
        // Added a moment after the menu is on screen: a slider already in
        // the menu when it appears draws in its inactive gray.
        openMenu = menu
        perform(#selector(addSlider), with: nil, afterDelay: 0, inModes: [.common, .eventTracking])
    }

    @objc private func addSlider() {
        guard let menu = openMenu, isFresh,
              let index = menu.items.firstIndex(where: { $0.title == heading }) else { return }
        item.menu?.removeItem(item)
        makeItem()
        menu.insertItem(item, at: index + 1)
        sync()
    }

    private func sync() {
        if unsaved == nil { slider.doubleValue = get() }
        label.stringValue = Levels.name(slider.doubleValue, in: names)
    }

    private func makeItem() {
        slider = NSSlider(value: get(), minValue: 0, maxValue: 1, target: self, action: #selector(slid(_:)))
        slider.numberOfTickMarks = names.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel(heading)
        label = NSTextField(labelWithString: "")
        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        // The usual menu inset, so the slider lines up with the item titles.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
        slider.frame = NSRect(x: 18, y: 2, width: 150, height: 24)
        label.frame = NSRect(x: 172, y: 7, width: 64, height: 16)
        view.addSubview(slider)
        view.addSubview(label)
        item = NSMenuItem()
        item.view = view
    }

    @objc private func slid(_ sender: NSSlider) {
        if unsaved != sender.doubleValue {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        unsaved = sender.doubleValue
        label.stringValue = Levels.name(sender.doubleValue, in: names)
        sender.setAccessibilityValueDescription(label.stringValue)
    }

    private func closed(_ menu: NSMenu?) {
        guard let menu, item.menu === menu || menu.items.contains(where: { $0.title == heading }) else { return }
        isFresh = false
        guard let value = unsaved else { return }
        unsaved = nil
        set(value)
    }
}
