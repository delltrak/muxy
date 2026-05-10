import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(\.openWindow) private var openWindow
    @State private var showingWorktreeExplainer = false
    @State private var showCreateWorkspaceSheet = false

    private var isFirstRunLikely: Bool {
        projectStore.projects.isEmpty
            && workspaceStore.workspaces.count == 1
            && (workspaceStore.workspaces.first?.id == Workspace.defaultID)
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowDragRepresentable()
                .frame(height: UIMetrics.scaled(32))
            Spacer()
            if isFirstRunLikely {
                onboardingContent
            } else {
                heroContent
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, UIMetrics.spacing10)
        .sheet(isPresented: $showCreateWorkspaceSheet) {
            WorkspaceEditorSheet(mode: .create) { result in
                createWorkspace(from: result)
            }
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: UIMetrics.spacing9) {
            Image(systemName: "rectangle.stack.badge.plus")
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
                Text("Organize projects by workspace — one per client, team, or context.")
                    .font(.system(size: UIMetrics.fontBody))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: UIMetrics.scaled(460))
            }

            VStack(spacing: UIMetrics.spacing4) {
                Button {
                    showCreateWorkspaceSheet = true
                } label: {
                    HStack(spacing: UIMetrics.spacing3) {
                        Image(systemName: "plus")
                        Text("Create Workspace")
                    }
                    .frame(minWidth: UIMetrics.scaled(220))
                }
                .muxyProminentButtonStyle()
                .controlSize(.large)

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
                    .frame(minWidth: UIMetrics.scaled(220))
                }
                .muxyGlassButtonStyle()
                .controlSize(.large)
            }

            VStack(spacing: UIMetrics.spacing3) {
                Button {
                    openWindow(id: "help")
                } label: {
                    Text("Show Quick Start")
                }
                .buttonStyle(.link)
                .font(.system(size: UIMetrics.fontFootnote))

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

    private func createWorkspace(from result: WorkspaceEditorSheet.Result) {
        let trimmed = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let workspace = Workspace(
            name: trimmed,
            sortOrder: workspaceStore.workspaces.count,
            iconColor: result.iconColor
        )
        workspaceStore.add(workspace)
        appState.selectWorkspace(workspace.id, projects: projectStore.projects)
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
