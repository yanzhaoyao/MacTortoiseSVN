import AppKit
import FinderSyncBridge
import SwiftUI

struct WorkbenchSidebar: View {
    @ObservedObject var model: WorkbenchModel

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.visibilityPrefs.showSidebarBookmarks {
                bookmarksSection
            }

            if model.visibilityPrefs.showSidebarNavigation {
                navigationSection
            }

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 4)
        .background(.thinMaterial)
        .background(CommitPalette.sidebarBackground)
    }

    // MARK: - Bookmarks

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(localizer.sidebarWorkspacesTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    model.addBookmarkFromPicker()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CommitPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .help(localizer.addWorkingCopyTitle)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            if model.bookmarks.isEmpty {
                Button {
                    model.addBookmarkFromPicker()
                } label: {
                    Label(localizer.addWorkingCopyTitle, systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CommitPalette.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(model.bookmarks) { bookmark in
                            BookmarkRow(
                                bookmark: bookmark,
                                isActive: bookmark.path == model.rootPath,
                                localizer: localizer,
                                onSelect: { model.switchToBookmark(bookmark) },
                                onRename: { model.renameBookmark(id: bookmark.id, newName: $0) },
                                onReveal: { model.revealInFinder(bookmark.path) },
                                onCopyPath: { model.copyPathToClipboard(bookmark.path) },
                                onRemove: { model.removeBookmark(id: bookmark.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 168)
            }

            Divider()
                .padding(.horizontal, 10)
                .padding(.top, 4)
        }
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localizer.sidebarNavigationTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            NavigationRow(
                item: .changes,
                icon: "list.bullet.rectangle",
                title: localizer.sidebarChangesTitle,
                isActive: model.activeNavigation == .changes,
                onSelect: { model.activeNavigation = .changes }
            )

            NavigationRow(
                item: .repoBrowser,
                icon: "folder.badge.gearshape",
                title: localizer.sidebarRepositoryTitle,
                isActive: model.activeNavigation == .repoBrowser,
                onSelect: { model.activeNavigation = .repoBrowser }
            )

            NavigationRow(
                item: .history,
                icon: "clock.arrow.circlepath",
                title: localizer.sidebarHistoryTitle,
                isActive: model.activeNavigation == .history,
                onSelect: { model.showHistory() }
            )
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.horizontal, 10)

            HStack(spacing: 6) {
                if !model.rootPath.isEmpty {
                    Button {
                        model.addCurrentPathAsBookmark()
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(CommitPalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.addWorkingCopyTitle)
                }

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        model.isSidebarVisible = false
                    }
                } label: {
                    SidebarVisibilityGlyph(isSidebarVisible: true)
                        .frame(width: 24, height: 24)
                        .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(localizer.toggleSidebarTitle)

                SettingsLink {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(localizer.displaySettingsTitle)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Bookmark Row

private struct BookmarkRow: View {
    let bookmark: WorkspaceBookmark
    let isActive: Bool
    let localizer: MacSVNLocalizer
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onReveal: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? CommitPalette.sidebarSelection : Color.clear)

                if isActive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(CommitPalette.accent)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }

                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? CommitPalette.accent : CommitPalette.folderTint)
                        .frame(width: 22, height: 22)
                        .background(
                            (isActive ? CommitPalette.accent.opacity(0.12) : CommitPalette.toolbarFill),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(bookmark.label)
                            .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                            .foregroundStyle(isActive ? CommitPalette.textPrimary : CommitPalette.textSecondary)
                            .lineLimit(1)

                        Text(bookmark.path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(CommitPalette.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, isActive ? 9 : 6)
                .padding(.trailing, 7)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label(localizer.sidebarWorkspacesTitle, systemImage: "arrow.right.circle")
            }

            Button {
                let prompt = NSAlert()
                prompt.messageText = localizer.renameBookmarkTitle
                prompt.informativeText = bookmark.label
                let input = NSTextField(string: bookmark.displayName ?? bookmark.label)
                input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
                prompt.accessoryView = input
                prompt.addButton(withTitle: "OK")
                prompt.addButton(withTitle: "Cancel")
                if prompt.runModal() == .alertFirstButtonReturn {
                    onRename(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } label: {
                Label(localizer.renameBookmarkTitle, systemImage: "pencil")
            }

            Divider()

            Button {
                onReveal()
            } label: {
                Label(localizer.contextRevealInFinder, systemImage: "folder")
            }

            Button {
                onCopyPath()
            } label: {
                Label(localizer.contextCopyPath, systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label(localizer.removeBookmarkTitle, systemImage: "trash")
            }
        }
    }
}

// MARK: - Navigation Row

private struct NavigationRow: View {
    let item: WorkbenchModel.NavigationItem
    let icon: String
    let title: String
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? CommitPalette.sidebarSelection : Color.clear)

                if isActive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(CommitPalette.accent)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }

                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? CommitPalette.accent : CommitPalette.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            (isActive ? CommitPalette.accent.opacity(0.12) : CommitPalette.toolbarFill),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    Text(title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? CommitPalette.textPrimary : CommitPalette.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.leading, isActive ? 9 : 6)
                .padding(.trailing, 7)
                .padding(.vertical, 4)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
