import FinderSyncBridge
import SwiftUI

struct WorkbenchSettingsView: View {
    @ObservedObject var model: WorkbenchModel

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGlassGroup(title: localizer.displaySettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localizer.defaultWindowPresetTitle, selection: $model.defaultWindowPreset) {
                            Text(localizer.compactWindowPresetTitle).tag(WorkbenchWindowPreset.compact)
                            Text(localizer.spaciousWindowPresetTitle).tag(WorkbenchWindowPreset.spacious)
                        }
                        .pickerStyle(.segmented)

                        Toggle(localizer.hideDiffPreviewInCompactTitle, isOn: $model.hideDiffPreviewInCompactWindow)

                        Text(localizer.finderLaunchPreferenceHint)
                            .font(.system(size: 12))
                            .foregroundStyle(CommitPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsGlassGroup(title: localizer.sidebarSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(localizer.showSidebarTitle, isOn: $model.isSidebarVisible)
                        Toggle(localizer.showSidebarBookmarksTitle, isOn: $model.visibilityPrefs.showSidebarBookmarks)
                            .disabled(!model.isSidebarVisible)
                        Toggle(localizer.showSidebarNavigationTitle, isOn: $model.visibilityPrefs.showSidebarNavigation)
                            .disabled(!model.isSidebarVisible)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsGlassGroup(title: localizer.backendSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localizer.backendModeTitle, selection: $model.backendMode) {
                            ForEach(WorkbenchBackendMode.allCases) { mode in
                                Text(localizer.title(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle(localizer.preserveModificationTimesTitle, isOn: $model.preserveModificationTimes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsGlassGroup(title: localizer.integrationSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localizer.defaultExternalDiffToolTitle, selection: $model.selectedExternalDiffToolID) {
                            ForEach(model.externalTools) { profile in
                                Text(profile.displayName).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(model.externalTools.isEmpty)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsGlassGroup(title: localizer.performanceSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(
                            "\(localizer.maxConcurrentOperationsTitle): \(model.maxConcurrentOperations)",
                            value: $model.maxConcurrentOperations,
                            in: 1...8
                        )
                        Stepper(
                            "\(localizer.badgeEntryLimitTitle): \(model.badgeEntryLimit)",
                            value: $model.badgeEntryLimit,
                            in: 256...50000,
                            step: 256
                        )
                        Stepper(
                            "\(localizer.maxIncrementalDirtyPathsTitle): \(model.maxIncrementalDirtyPaths)",
                            value: $model.maxIncrementalDirtyPaths,
                            in: 16...4096,
                            step: 16
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsGlassGroup(title: localizer.workspaceSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(localizer.showActionToolbarTitle, isOn: $model.visibilityPrefs.showActionToolbar)
                        Toggle(localizer.showChangeListTitle, isOn: $model.visibilityPrefs.showChangeList)
                        Toggle(localizer.showCommitMessageTitle, isOn: $model.visibilityPrefs.showCommitMessage)
                        Toggle(localizer.showDiffPreviewTitle, isOn: $model.visibilityPrefs.showDiffPreview)
                        Toggle(localizer.showInspectorTitle, isOn: $model.visibilityPrefs.showInspector)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(width: 460)
    }
}

private struct SettingsGlassGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .background(CommitPalette.glassFill, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [CommitPalette.glassHighlight, CommitPalette.subtleBorderLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}
