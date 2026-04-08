import AppKit
import SwiftUI
import WebKit

enum ProviderIconAsset {
    static func image(for provider: ProviderID) -> NSImage? {
        guard let url = Bundle.module.url(forResource: provider.iconResourceName, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.isTemplate = true
        return image
    }
}

struct ProviderIconView: View {
    let provider: ProviderID
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image = ProviderIconAsset.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProviderHeaderView: View {
    let provider: ProviderID
    let title: String
    let subtitle: String?
    var externalLinkURL: URL? = nil

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(provider: provider, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let externalLinkURL {
                Button {
                    NSWorkspace.shared.open(externalLinkURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(externalLinkURL.absoluteString)
                .accessibilityLabel("Open \(title) settings")
                .offset(y: -2)
            }
        }
    }
}

struct RemainingProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))

                Capsule()
                    .fill(LinearGradient(colors: threshold.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * clampedFraction)
                    .opacity(fraction == nil ? 0.25 : 1)
            }
        }
        .frame(height: 10)
    }

    private var clampedFraction: CGFloat {
        guard let fraction else {
            return 0
        }

        return CGFloat(min(max(fraction, 0), 1))
    }

    private var threshold: RemainingUsageBarThreshold {
        RemainingUsageBarThreshold(for: fraction)
    }
}

enum RemainingUsageBarThreshold {
    case healthy
    case warning
    case critical

    init(for fraction: Double?) {
        guard let fraction else {
            self = .healthy
            return
        }

        if fraction < 0.1 {
            self = .critical
        } else if fraction < 0.3 {
            self = .warning
        } else {
            self = .healthy
        }
    }

    var colors: [Color] {
        switch self {
        case .healthy:
            return [Color.green.opacity(0.95), Color.green]
        case .warning:
            return [Color.yellow.opacity(0.95), Color.yellow]
        case .critical:
            return [Color.red.opacity(0.95), Color.red]
        }
    }
}

struct TimeRemainingProgressBar: View {
    let fraction: Double?
    let isEmphasized: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))

                Capsule()
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.95), Color.blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * clampedFraction)
                    .opacity(fraction == nil ? 0.2 : 1)
            }
        }
        .frame(height: 4)
    }

    private var clampedFraction: CGFloat {
        guard let fraction else {
            return 0
        }

        return CGFloat(min(max(fraction, 0), 1))
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
