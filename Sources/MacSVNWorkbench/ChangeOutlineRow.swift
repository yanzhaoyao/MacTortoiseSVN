import CoreTypes
import FinderSyncBridge
import SwiftUI

struct ChangeOutlineRow: View {
    let node: ChangeTreeNode
    let localizer: MacSVNLocalizer
    let selectedPaths: Set<String>
    let depth: Int
    let isExpanded: Bool
    let onToggleExpansion: (ChangeTreeNode) -> Void
    let onSetNodeSelection: (ChangeTreeNode, Bool) -> Void
    let onToggleEntry: (String) -> Void

    private var selectionState: SelectionIndicatorState {
        node.selectionState(in: selectedPaths)
    }

    private var isSelectable: Bool {
        if node.isFolder {
            return node.actionableCount > 0
        }

        return node.entry?.isActionable == true
    }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 0) {
                if node.hasChildren {
                    Button {
                        onToggleExpansion(node)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CommitPalette.textMuted)
                            .frame(width: 16, height: 18)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 16, height: 18)
                }
            }
            .padding(.leading, CGFloat(depth) * 16)

            SelectionToggleButton(
                state: selectionState,
                isEnabled: isSelectable
            ) {
                if node.isFolder {
                    onSetNodeSelection(node, selectionState != .all)
                } else if let entry = node.entry {
                    onToggleEntry(entry.id)
                }
            }

            Image(systemName: node.isFolder ? "folder" : (node.entry?.isDirectory == true ? "folder" : "doc.text"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(node.isFolder ? CommitPalette.folderTint : CommitPalette.textSecondary)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.titleText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CommitPalette.textPrimary)
                    .lineLimit(1)

                Text(node.subtitleText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let entry = node.entry, entry.item.propertyModified {
                InlineCapsule(text: localizer.props, tint: .orange)
            }

            if let entry = node.entry {
                StatusBadge(status: entry.status, localizer: localizer)
            } else if node.actionableCount > 0 {
                Text(node.summaryText(localizer: localizer))
                    .font(.system(size: 10))
                    .foregroundStyle(CommitPalette.textMuted)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(minHeight: 26)
        .contentShape(Rectangle())
    }
}
