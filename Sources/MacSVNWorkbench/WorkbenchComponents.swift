import AppKit
import CoreTypes
import FinderSyncBridge
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

struct HeaderMetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CommitPalette.textMuted)

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [CommitPalette.glassHighlight, CommitPalette.subtleBorder],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ToolbarActionButton: View {
    let title: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? CommitPalette.textPrimary : CommitPalette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [CommitPalette.glassHighlight, CommitPalette.subtleBorder],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct ToolbarIconButton: View {
    let symbol: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? CommitPalette.textPrimary : CommitPalette.textMuted)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [CommitPalette.glassHighlight, CommitPalette.subtleBorder],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }
}

struct SelectionToggleButton: View {
    let state: SelectionIndicatorState
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.systemImageName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? state.tint : CommitPalette.textMuted)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct CommitMessageEditor: View {
    @Binding var text: String
    let placeholder: String
    let isFocused: FocusState<Bool>.Binding?

    init(
        text: Binding<String>,
        placeholder: String,
        isFocused: FocusState<Bool>.Binding? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .fill(CommitPalette.editorBackground)

            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.16), lineWidth: 3)
                .blur(radius: 3)
                .offset(x: 0, y: 1)
                .mask(
                    RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black,
                                    Color.black.opacity(0.78),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            editorField
        }
        .frame(maxWidth: .infinity, minHeight: 92)
    }

    @ViewBuilder
    private var editorField: some View {
        if let isFocused {
            TextEditor(text: $text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(7)
                .focused(isFocused)
        } else {
            TextEditor(text: $text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(7)
        }
    }
}

struct CommitPanel<HeaderTrailing: View, Content: View>: View {
    let title: String
    let headerTrailing: HeaderTrailing
    let content: Content
    let isFirst: Bool
    let isLast: Bool

    init(
        title: String,
        isFirst: Bool = true,
        isLast: Bool = true,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isFirst = isFirst
        self.isLast = isLast
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textPrimary)

                Spacer(minLength: 0)
                headerTrailing
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 9)

            Divider()
                .overlay(CommitPalette.border)

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius, style: .continuous))
        .background(CommitPalette.panelBackground, in: RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.panelBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius - 1, style: .continuous)
                .inset(by: 1)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
        )
        .shadow(
            color: Color.black.opacity(0.14),
            radius: max(10, CommitPalette.panelShadowRadius - 4),
            x: 0,
            y: max(4, CommitPalette.panelShadowYOffset - 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius, style: .continuous))
        .padding(.horizontal, CommitPalette.panelInset)
        .padding(.bottom, max(10, CommitPalette.workspaceGap - 6))
    }
}

extension CommitPanel where HeaderTrailing == EmptyView {
    init(
        title: String,
        isFirst: Bool = true,
        isLast: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, isFirst: isFirst, isLast: isLast, headerTrailing: { EmptyView() }, content: content)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
        )
    }
}

struct SidebarMetricRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CommitPalette.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

struct SidebarInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textMuted)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CommitPalette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InlineCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

struct DiffTextPreview: View {
    let text: String

    var body: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(CommitPalette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
        }
        .background(
            CommitPalette.editorBackground,
            in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
        )
    }
}

struct DiffMetadataCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorder, lineWidth: 0.5)
        )
    }
}

struct FooterActionButtonModifier: ViewModifier {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(kind == .primary ? Color.white : CommitPalette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 86)
            .padding(.vertical, 8)
            .background(backgroundColor, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        kind == .primary
                            ? LinearGradient(colors: [Color.primary.opacity(0.15), Color.clear], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [CommitPalette.subtleBorder, Color.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: shadowColor, radius: kind == .primary ? 5 : 2, x: 0, y: 2)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return CommitPalette.primaryButton
        case .secondary:
            return Color(nsColor: .controlColor).opacity(0.55)
        }
    }

    private var shadowColor: Color {
        kind == .primary
            ? CommitPalette.accent.opacity(0.25)
            : Color.black.opacity(0.04)
    }
}

struct SidebarVisibilityGlyph: View {
    let isSidebarVisible: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(CommitPalette.textSecondary.opacity(0.72), lineWidth: 1.25)
                .frame(width: 15, height: 13)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(CommitPalette.accent.opacity(isSidebarVisible ? 0.9 : 0.42))
                .frame(width: 4, height: 11)
                .offset(x: -5.5)
        }
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: VersionControlStatus
    let localizer: MacSVNLocalizer

    var body: some View {
        Text(localizer.title(for: status))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color, in: Capsule())
    }
}
