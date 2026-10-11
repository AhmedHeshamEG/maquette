import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// The app's root: Home, with the open project over it. A card grows into the stage (the system zoom transition from
/// the card's picture) and the stage shrinks back into it. Universal gestures, the toast and the theme live here and
/// in the project's cover.
public struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(HmmThemeMode.storageKey) private var themeMode = HmmThemeMode.dark.rawValue
    /// Chrome restraint, a trial (Diagnostics flips it): neutral glass, one accent at a time.
    @AppStorage(HmmChromeRestraint.storageKey) private var restrained = true
    /// This window, among the app's windows (Stage Manager).
    @State private var windowID = UUID()
    @Namespace private var zoom

    public init() {}

    public var body: some View {
        if app.primaryWindow == nil || app.primaryWindow == windowID {
            main
                .onAppear {
                    if app.primaryWindow == nil { app.primaryWindow = windowID }
                    // After this pass draws: the cold launch ends at the first screen.
                    Task { @MainActor in app.noteLaunched() }
                }
                .onDisappear { if app.primaryWindow == windowID { app.primaryWindow = nil } }
        } else {
            SecondaryWindowView { app.primaryWindow = windowID }
                .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
        }
    }

    private var main: some View {
        @Bindable var app = app
        return ZStack {
            BackgroundFill()
            TheaterView(zoom: zoom)
            if app.isRecordingFeel { FeelRecordingDot() }
        }
        .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
        .environment(\.hmmRestrainedChrome, restrained)
        .hmmToast($app.toast)
        .fullScreenCover(item: $app.editor) { editor in
            ZStack {
                BackgroundFill()
                EditorScreen(editor: editor)
                if app.isRecordingFeel { FeelRecordingDot() }
            }
            .environment(app)
            .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
            .environment(\.hmmRestrainedChrome, restrained)
            .hmmToast($app.toast)
            .hmmUniversalGestures(HmmGestureActions(
                // While the board covers the stage, two fingers undo on the board (its own gestures), not under it.
                undo: { if app.editor?.boardShown != true { app.editor?.undo() } },
                redo: { if app.editor?.boardShown != true { app.editor?.redo() } },
                toggleChrome: { if app.editor?.boardShown != true { app.editor?.chromeHidden.toggle() } },
                editMenu: { if app.editor?.boardShown != true { app.editor?.hands.editBar = true } }
            ))
            // Pinching and dragging belong to the stage: the project closes from Home in the corner, never by a swipe.
            .interactiveDismissDisabled()
            .navigationTransition(.zoom(sourceID: editor.document.project.id.raw, in: zoom))
        }
        .sheet(item: $app.pendingConflict) { conflict in
            HmmConflictSheet(documentName: conflict.name, thisVersion: conflict.thisVersion,
                             otherVersion: conflict.versions.first ?? conflict.thisVersion) { choice in
                app.resolveConflict(choice)
            }
        }
        .sheet(isPresented: $app.showsSettings) { SettingsSheet(app: app) }
        .sheet(isPresented: $app.showsLearn) { LearnSheet(app: app) }
        .onChange(of: app.projects.count) { _, _ in openTourIslandIfNeeded() }
        .onChange(of: app.showTour) { _, _ in openTourIslandIfNeeded() }
        .task { await app.start() }
    }
}

extension RootView {
    /// First launch: the tour happens on the welcome island.
    private func openTourIslandIfNeeded() {
        guard app.showTour, app.editor == nil, let island = app.projects.first(where: { $0.info.name == IslandSample.projectName }) else { return }
        app.open(url: island.url)
    }
}

private struct BackgroundFill: View {
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        theme.background.ignoresSafeArea()
    }
}

/// The feel recorder is listening: one small red dot at the top, nothing to touch (it stops by itself).
private struct FeelRecordingDot: View {
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Circle()
            .fill(theme.record)
            .frame(width: 8, height: 8)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityLabel("Recording how the app feels")
            .accessibilityIdentifier("feel-recording")
    }
}
