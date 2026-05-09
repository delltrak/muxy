import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(\.openWindow) private var openWindow
    @State private var showingWorktreeExplainer = false

    var body: some View {
        VStack(spacing: 0) {
            WindowDragRepresentable()
                .frame(height: UIMetrics.scaled(32))
            Spacer()
            heroContent
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, UIMetrics.spacing10)
    }

    private var heroContent: some View {
        VStack(spacing: UIMetrics.spacing9) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: UIMetrics.scaled(72), weight: .light))
                .foregroundStyle(MuxyTheme.accent)
                .symbolRenderingMode(.hierarchical)
                .padding(UIMetrics.scaled(32))
                .muxyGlass(.tinted(MuxyTheme.accent.opacity(0.08)), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: UIMetrics.spacing4) {
                Text("Welcome to Muxy")
                    .font(.system(size: UIMetrics.fontHero, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("Multiplex terminals, editors, and source control across projects and git worktrees — all native.")
                    .font(.system(size: UIMetrics.fontBody))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: UIMetrics.scaled(460))
            }

            HStack(spacing: UIMetrics.spacing6) {
                Button {
                    ProjectOpenService.openProject(
                        appState: appState,
                        projectStore: projectStore,
                        worktreeStore: worktreeStore
                    )
                } label: {
                    HStack(spacing: UIMetrics.spacing3) {
                        Image(systemName: "folder")
                        Text("Open Project…")
                        Text(KeyBindingStore.shared.combo(for: .openProject).displayString)
                            .font(.system(size: UIMetrics.fontFootnote, weight: .medium, design: .rounded))
                            .opacity(0.72)
                    }
                }
                .muxyProminentButtonStyle()
                .controlSize(.large)

                Button {
                    openWindow(id: "help")
                } label: {
                    HStack(spacing: UIMetrics.spacing3) {
                        Image(systemName: "sparkles")
                        Text("Show Quick Start")
                    }
                }
                .muxyGlassButtonStyle()
                .controlSize(.large)
            }

            Button("What is a worktree?") {
                showingWorktreeExplainer = true
            }
            .buttonStyle(.link)
            .font(.system(size: UIMetrics.fontFootnote))
            .popover(isPresented: $showingWorktreeExplainer, arrowEdge: .top) {
                WorktreeExplainerPopover()
                    .frame(width: UIMetrics.scaled(360))
                    .padding(UIMetrics.spacing7)
            }
        }
    }
}

private struct WorktreeExplainerPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UIMetrics.spacing6) {
            Label("Git Worktrees", systemImage: "arrow.triangle.branch")
                .font(.system(size: UIMetrics.fontHeadline, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text(
                """
                A worktree is an additional working directory for the same git repository. \
                Switch branches without stashing or losing your terminal state.
                """
            )
            .font(.system(size: UIMetrics.fontBody))
            .foregroundStyle(MuxyTheme.fg)
            Text("In Muxy, each project can have multiple worktrees side-by-side, each with its own tabs, splits, and shells.")
                .font(.system(size: UIMetrics.fontFootnote))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
    }
}
