import SwiftUI

/// A small, low-key "thanks" sheet. Both ways to chip in are offered: an
/// international "buy me a coffee" link and a Vietnamese bank QR. The one that
/// fits the user's region is shown first, the other is one tap away. It's
/// opt-in (only shown when the user taps "Buy me a coffee"), never nagging.
struct CoffeeView: View {
    let coffeeURL: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Method { case intl, vietnam }
    @State private var method: Method

    init(coffeeURL: URL) {
        self.coffeeURL = coffeeURL
        // Default to the method that matches the user's region.
        let vn = Locale.current.language.languageCode?.identifier == "vi"
            || Locale.current.region?.identifier == "VN"
        _method = State(initialValue: vn ? .vietnam : .intl)
    }

    private var qrImage: NSImage? {
        guard let url = Bundle.module.url(forResource: "donate-vietqr", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 30)).foregroundStyle(Color.systemAccent)
            Text("Thanks for using DesktopPet")
                .font(.title3.bold())
            Text("It's free and open source. If it makes your day a little nicer, a coffee is always appreciated, never expected.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $method) {
                Text("International").tag(Method.intl)
                Text("Việt Nam").tag(Method.vietnam)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch method {
            case .intl:
                VStack(spacing: 8) {
                    Button { openURL(coffeeURL) } label: {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.systemAccent).controlSize(.large)
                    Text("Opens buymeacoffee.com in your browser.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(height: 286)

            case .vietnam:
                VStack(spacing: 8) {
                    if let qr = qrImage {
                        Image(nsImage: qr)
                            .resizable().interpolation(.high).scaledToFit()
                            .frame(width: 200, height: 234)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    }
                    Text("Quét bằng app ngân hàng bất kỳ (VPBank · NGUYEN THANH DAT)")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("626333362", forType: .string)
                    } label: {
                        Label("Sao chép số tài khoản", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
                .frame(height: 286)
            }

            Button("Close") { dismiss() }
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 340)
        .preferredColorScheme(.dark)
        .noFocusRing()
    }
}
