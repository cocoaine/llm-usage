import AppKit
import UsageCore

@MainActor
enum StatusBarSummary {
    private static let imageHeight: CGFloat = 18
    private static let iconSize: CGFloat = 15
    private static let iconSpacing: CGFloat = 5
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let separator = "  ·  "

    /// A single template image lets NSStatusBarButton apply the same active,
    /// inactive, and highlighted tint to provider icons and their values.
    static func image(codex: String, claude: String, bundle: Bundle = .main) -> NSImage {
        let codexItem = item(provider: .codex, remaining: codex, bundle: bundle)
        let claudeItem = item(provider: .claude, remaining: claude, bundle: bundle)
        let separatorSize = textSize(separator)
        let size = NSSize(
            width: codexItem.width + separatorSize.width + claudeItem.width,
            height: imageHeight
        )

        let image = NSImage(size: size, flipped: true) { _ in
            var origin = CGFloat.zero
            draw(codexItem, at: &origin)
            drawText(separator, at: &origin)
            draw(claudeItem, at: &origin)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func item(provider: Provider, remaining: String, bundle: Bundle) -> Item {
        let valueWidth = textSize(remaining).width
        if let icon = providerIcon(for: provider, bundle: bundle) {
            return Item(icon: icon, text: remaining, width: iconSize + iconSpacing + valueWidth)
        }

        let fallback = "\(provider.rawValue) \(remaining)"
        return Item(icon: nil, text: fallback, width: textSize(fallback).width)
    }

    private static func draw(_ item: Item, at origin: inout CGFloat) {
        if let icon = item.icon {
            let iconRect = NSRect(
                x: origin,
                y: (imageHeight - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            origin += iconSize + iconSpacing
        }
        drawText(item.text, at: &origin)
    }

    private static func drawText(_ text: String, at origin: inout CGFloat) {
        let size = textSize(text)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: text, attributes: attributes).draw(
            in: NSRect(x: origin, y: (imageHeight - size.height) / 2, width: size.width, height: size.height)
        )
        origin += size.width
    }

    private static func textSize(_ text: String) -> NSSize {
        (text as NSString).size(withAttributes: [.font: valueFont])
    }

    private static func providerIcon(for provider: Provider, bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: provider.rawValue, withExtension: "png", subdirectory: "ProviderIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

private struct Item {
    let icon: NSImage?
    let text: String
    let width: CGFloat
}
