import AppKit
import SwiftUI

/// Connect a Spotify account. The Web API needs a Client ID from an app the user creates
/// on Spotify's developer dashboard, so this walks through that, one step per row.
struct AccountView: View {
    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        @Bindable var account = account
        VStack(alignment: .leading, spacing: Metrics.unit * 2.5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spotify account").styledTitle(30)
                Spacer()
                IconButton(systemName: "xmark", label: "Close", size: 13) { dismiss() }
            }
            Rule()

            switch account.status {
            case .signedIn(let name):
                signedIn(name)
            default:
                steps(clientID: $account.clientID)
                statusLine
            }

            Text("Liking songs, playlists and recently played use Spotify’s Web API. Playback stays on the Spotify app. Spotify’s Development Mode needs the app owner to have Premium, and allows up to five listed users.")
                .font(theme.font(\.body, 11))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.unit * 4)
        .frame(width: 520)
        .background(theme.background)
        .foregroundStyle(theme.foreground)
    }

    private func signedIn(_ name: String) -> some View {
        HStack(spacing: Metrics.unit * 2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.accent)
                .symbolEffect(.bounce, value: name)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected").styledLabel()
                Text(name).font(theme.font(\.display, 22))
            }
            Spacer()
            ActionButton(title: "Disconnect", icon: "link.badge.plus") { account.signOut() }
        }
    }

    private func steps(clientID: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 2) {
            Step(number: 1, icon: "globe", text: "Create an app on the Spotify developer dashboard.") {
                Link(destination: URL(string: "https://developer.spotify.com/dashboard")!) {
                    Label("Open", systemImage: "arrow.up.forward").font(theme.font(\.label, 11))
                }
            }
            Step(number: 2, icon: "arrow.uturn.backward", text: "Add this Redirect URI, and tick Web API.") {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SpotifyAccount.redirectURI, forType: .string)
                    withAnimation(.spring(duration: 0.3, bounce: 0.4)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(theme.font(\.label, 11))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            }
            Text(SpotifyAccount.redirectURI)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 40)
            Step(number: 3, icon: "key", text: "Paste the app’s Client ID, then connect.") { EmptyView() }
            HStack(spacing: Metrics.unit) {
                TextField("Client ID", text: clientID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit { account.signIn() }
                ActionButton(title: "Connect", icon: "link") { account.signIn() }
                    .disabled(clientID.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty || account.status == .signingIn)
            }
            .padding(.leading, 40)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch account.status {
        case .signingIn:
            HStack(spacing: Metrics.unit) {
                ProgressView().controlSize(.small)
                Text("Finish in your browser…").font(theme.font(\.body, 13))
                Spacer()
                Button("Cancel") { account.cancelSignIn() }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.secondary)
            }
            .transition(.opacity)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(theme.font(\.body, 13))
                .foregroundStyle(theme.accent)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }
}

private struct Step<Trailing: View>: View {
    let number: Int
    let icon: String
    let text: String
    @ViewBuilder let trailing: Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Metrics.unit * 1.5) {
            ZStack {
                Circle().strokeBorder(theme.accent, lineWidth: 1.5)
                Text("\(number)").font(theme.font(\.label, 12)).foregroundStyle(theme.accent)
            }
            .frame(width: 28, height: 28)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondary)
                .frame(width: 18)
            Text(text).font(theme.font(\.body, 14))
            Spacer(minLength: Metrics.unit)
            trailing
        }
    }
}

/// The account's latest message, floating at the bottom of the window.
struct NoticeToast: View {
    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if let notice = account.notice {
                HStack(spacing: Metrics.unit) {
                    Image(systemName: notice.icon)
                        .foregroundStyle(theme.accent)
                        .symbolEffect(.bounce, value: notice.id)
                    Text(notice.text)
                        .font(theme.font(\.body, 13))
                        .lineLimit(2)
                }
                .padding(.horizontal, 6)
                .styledCard(padding: 12)
                .background(theme.background, in: RoundedRectangle(cornerRadius: theme.style.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .id(notice.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: account.notice)
        .padding(.bottom, Metrics.unit * 3)
    }
}
