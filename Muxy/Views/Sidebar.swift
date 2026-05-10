import MuxyShared
import SwiftUI

@MainActor
enum SidebarLayout {
    static var collapsedWidth: CGFloat { UIMetrics.sidebarCollapsedWidth }
    static var expandedWidth: CGFloat { UIMetrics.sidebarExpandedWidth }
    static var width: CGFloat { UIMetrics.sidebarCollapsedWidth }

    static func resolvedWidth(
        expanded: Bool,
        collapsedStyle: SidebarCollapsedStyle,
        expandedStyle: SidebarExpandedStyle
    ) -> CGFloat {
        if expanded {
            return expandedStyle == .wide ? expandedWidth : collapsedWidth
        }
        return collapsedStyle == .hidden ? 0 : collapsedWidth
    }

    static func isWide(expanded: Bool, expandedStyle: SidebarExpandedStyle) -> Bool {
        expanded && expandedStyle == .wide
    }

    static func isHidden(expanded: Bool, collapsedStyle: SidebarCollapsedStyle) -> Bool {
        !expanded && collapsedStyle == .hidden
    }
}

struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragState = ProjectDragState()
    @State private var expanded = UserDefaults.standard.bool(forKey: "muxy.sidebarExpanded")
    @State private var sectionCollapsed: [UUID: Bool] = SidebarSectionStore.load()
    @State private var showNewWorkspaceSheet = false
    @State private var renameWorkspaceTarget: Workspace?
    @State private var pendingDeleteWorkspaceID: UUID?
    @AppStorage(SidebarCollapsedStyle.storageKey) private var collapsedStyleRaw = SidebarCollapsedStyle.defaultValue.rawValue
    @AppStorage(SidebarExpandedStyle.storageKey) private var expandedStyleRaw = SidebarExpandedStyle.defaultValue.rawValue
    @ScaledMetric(relativeTo: .body) private var collapsedWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var expandedWidth: CGFloat = 220

    private var collapsedStyle: SidebarCollapsedStyle {
        SidebarCollapsedStyle(rawValue: collapsedStyleRaw) ?? .defaultValue
    }

    private var expandedStyle: SidebarExpandedStyle {
        SidebarExpandedStyle(rawValue: expandedStyleRaw) ?? .defaultValue
    }

    private var isWide: Bool {
        SidebarLayout.isWide(expanded: expanded, expandedStyle: expandedStyle)
    }

    private var isHidden: Bool {
        SidebarLayout.isHidden(expanded: expanded, collapsedStyle: collapsedStyle)
    }

    var body: some View {
        VStack(spacing: 0) {
            projectList
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            if isWide {
                newWorkspaceRow
                    .padding(.horizontal, UIMetrics.spacing3)
                    .padding(.bottom, UIMetrics.spacing2)
            }

            SidebarFooter(expanded: isWide)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .frame(width: isHidden ? 0 : (isWide ? expandedWidth : collapsedWidth))
        .opacity(isHidden ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleExpanded()
        }
        .sheet(isPresented: $showNewWorkspaceSheet) {
            WorkspaceEditorSheet(mode: .create) { result in
                createWorkspace(from: result)
            }
        }
        .sheet(item: $renameWorkspaceTarget) { workspace in
            WorkspaceEditorSheet(mode: .rename(current: workspace)) { result in
                workspaceStore.rename(id: workspace.id, to: result.name)
                workspaceStore.setIconColor(id: workspace.id, to: result.iconColor)
            }
        }
        .alert(
            "Delete this workspace?",
            isPresented: deleteAlertBinding,
            presenting: pendingDeleteWorkspaceID
        ) { id in
            Button("Cancel", role: .cancel) { pendingDeleteWorkspaceID = nil }
            Button("Delete", role: .destructive) { deleteWorkspace(id: id) }
        } message: { _ in
            Text("All projects in this workspace will be removed from Muxy. The folders on disk are not deleted.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteWorkspaceID != nil },
            set: { if !$0 { pendingDeleteWorkspaceID = nil } }
        )
    }

    private var newWorkspaceRow: some View {
        Button {
            showNewWorkspaceSheet = true
        } label: {
            HStack(spacing: UIMetrics.spacing4) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIMetrics.radiusMD)
                        .strokeBorder(MuxyTheme.fgMuted.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: UIMetrics.fontEmphasis, weight: .bold))
                        .foregroundStyle(MuxyTheme.fgMuted)
                }
                .frame(width: UIMetrics.iconXXL, height: UIMetrics.iconXXL)

                Text("New Workspace")
                    .font(.system(size: UIMetrics.fontBody, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .padding(UIMetrics.spacing2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Workspace")
    }

    private func toggleExpanded() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            expanded.toggle()
        }
        UserDefaults.standard.set(expanded, forKey: "muxy.sidebarExpanded")
    }

    private func projects(in workspace: Workspace) -> [Project] {
        projectStore.projects.filter { $0.workspaceID == workspace.id }
    }

    private func isCollapsed(_ workspace: Workspace) -> Bool {
        if let stored = sectionCollapsed[workspace.id] { return stored }
        return workspace.id != appState.activeWorkspaceID
    }

    private func toggleSection(_ workspace: Workspace) {
        let current = isCollapsed(workspace)
        var copy = sectionCollapsed
        copy[workspace.id] = !current
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            sectionCollapsed = copy
        }
        SidebarSectionStore.save(copy)
    }

    private func activeWorkspaceShortcutIndex(_ project: Project) -> Int? {
        guard project.workspaceID == appState.activeWorkspaceID else { return nil }
        let activeProjects = projectStore.projects.filter {
            $0.workspaceID == appState.activeWorkspaceID
        }
        guard let idx = activeProjects.firstIndex(where: { $0.id == project.id }), idx < 9 else { return nil }
        return idx + 1
    }

    private var projectList: some View {
        let notificationStore = NotificationStore.shared
        let progressStore = TerminalProgressStore.shared
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: UIMetrics.spacing2) {
                if isWide {
                    ForEach(workspaceStore.workspaces) { workspace in
                        workspaceSection(
                            workspace,
                            notificationStore: notificationStore,
                            progressStore: progressStore
                        )
                    }
                } else {
                    flatProjectList(
                        notificationStore: notificationStore,
                        progressStore: progressStore
                    )
                }
            }
            .padding(.horizontal, isWide ? UIMetrics.spacing3 : UIMetrics.spacing4)
            .padding(.vertical, UIMetrics.spacing2)
            .onPreferenceChange(UUIDFramePreferenceKey<SidebarFrameTag>.self) { frames in
                guard dragState.draggedID != nil else { return }
                dragState.frames = frames
            }
        }
        .coordinateSpace(name: "sidebar")
    }

    @ViewBuilder
    private func workspaceSection(
        _ workspace: Workspace,
        notificationStore: NotificationStore,
        progressStore: TerminalProgressStore
    ) -> some View {
        let collapsed = isCollapsed(workspace)
        let projectsInWorkspace = projects(in: workspace)
        let isActiveWorkspace = workspace.id == appState.activeWorkspaceID

        WorkspaceSectionHeader(
            workspace: workspace,
            isActive: isActiveWorkspace,
            isCollapsed: collapsed,
            projectCount: projectsInWorkspace.count,
            onToggle: { toggleSection(workspace) },
            onAddProject: { addProject(to: workspace.id) },
            onRename: { renameWorkspaceTarget = workspace },
            onDelete: {
                guard workspaceStore.workspaces.count > 1 else { return }
                pendingDeleteWorkspaceID = workspace.id
            },
            canDelete: workspaceStore.workspaces.count > 1
        )

        if !collapsed {
            ForEach(projectsInWorkspace) { project in
                let metadata = ProjectRowMetadata(
                    unreadCount: notificationStore.unreadCount(for: project.id),
                    hasCompletionPending: progressStore.hasCompletionPending(for: project.id)
                )
                ExpandedProjectRow(
                    project: project,
                    metadata: metadata,
                    worktreeUnreadCounts: worktreeUnreadCounts(
                        for: project.id,
                        notificationStore: notificationStore
                    ),
                    shortcutIndex: activeWorkspaceShortcutIndex(project),
                    isAnyDragging: dragState.draggedID != nil,
                    onSelect: { select(project) },
                    onRemove: { remove(project) },
                    onRename: { projectStore.rename(id: project.id, to: $0) },
                    onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                    onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
                )
                .padding(.leading, UIMetrics.spacing4)
                .background {
                    if dragState.draggedID != nil {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: UUIDFramePreferenceKey<SidebarFrameTag>.self,
                                value: [project.id: geo.frame(in: .named("sidebar"))]
                            )
                        }
                    }
                }
                .gesture(projectDragGesture(for: project))
            }
        }
    }

    @ViewBuilder
    private func flatProjectList(
        notificationStore: NotificationStore,
        progressStore: TerminalProgressStore
    ) -> some View {
        ForEach(projectStore.projects) { project in
            let metadata = ProjectRowMetadata(
                unreadCount: notificationStore.unreadCount(for: project.id),
                hasCompletionPending: progressStore.hasCompletionPending(for: project.id)
            )
            ProjectRow(
                project: project,
                metadata: metadata,
                shortcutIndex: activeWorkspaceShortcutIndex(project),
                isAnyDragging: dragState.draggedID != nil,
                onSelect: { select(project) },
                onRemove: { remove(project) },
                onRename: { projectStore.rename(id: project.id, to: $0) },
                onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
            )
            .background {
                if dragState.draggedID != nil {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: UUIDFramePreferenceKey<SidebarFrameTag>.self,
                            value: [project.id: geo.frame(in: .named("sidebar"))]
                        )
                    }
                }
            }
            .gesture(projectDragGesture(for: project))
        }
        AddProjectButton(expanded: false) {
            ProjectOpenService.openProject(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        }
        .help(shortcutTooltip("Add Project", for: .openProject))
    }

    private func addProject(to workspaceID: UUID) {
        ProjectOpenService.openProject(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            workspaceID: workspaceID
        )
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
        sectionCollapsed[workspace.id] = false
        SidebarSectionStore.save(sectionCollapsed)
    }

    private func deleteWorkspace(id: UUID) {
        defer { pendingDeleteWorkspaceID = nil }
        guard workspaceStore.workspaces.count > 1 else { return }
        let projectsInWorkspace = projectStore.projects.filter { $0.workspaceID == id }
        for project in projectsInWorkspace {
            appState.removeProject(project.id)
            projectStore.remove(id: project.id)
            worktreeStore.removeProject(project.id)
        }
        workspaceStore.remove(id: id)
        sectionCollapsed.removeValue(forKey: id)
        SidebarSectionStore.save(sectionCollapsed)
        if appState.activeWorkspaceID == id, let next = workspaceStore.workspaces.first {
            appState.selectWorkspace(next.id, projects: projectStore.projects)
        }
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private func worktreeUnreadCounts(
        for projectID: UUID,
        notificationStore: NotificationStore
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for worktree in worktreeStore.list(for: projectID) {
            result[worktree.id] = notificationStore.unreadCount(for: projectID, worktreeID: worktree.id)
        }
        return result
    }

    private func projectDragGesture(for project: Project) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("sidebar"))
            .onChanged { value in
                if dragState.draggedID == nil {
                    dragState.draggedID = project.id
                    dragState.lastReorderTargetID = nil
                }
                reorderIfNeeded(at: value.location)
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    dragState.draggedID = nil
                    dragState.frames = [:]
                    dragState.lastReorderTargetID = nil
                }
            }
    }

    private func select(_ project: Project) {
        worktreeStore.ensurePrimary(for: project)
        guard let worktree = worktreeStore.preferred(
            for: project.id,
            matching: appState.activeWorktreeID[project.id]
        )
        else { return }
        if let workspaceID = project.workspaceID,
           appState.activeWorkspaceID != workspaceID
        {
            appState.activeWorkspaceID = workspaceID
        }
        appState.selectProject(project, worktree: worktree)
    }

    private func remove(_ project: Project) {
        let capturedProject = project
        let knownWorktrees = worktreeStore.list(for: project.id)
        Task.detached {
            await WorktreeStore.cleanupOnDisk(for: capturedProject, knownWorktrees: knownWorktrees)
        }
        appState.removeProject(project.id)
        projectStore.remove(id: project.id)
        worktreeStore.removeProject(project.id)
    }

    private func reorderIfNeeded(at location: CGPoint) {
        guard let draggedID = dragState.draggedID else { return }
        var hoveredTargetID: UUID?

        for (id, frame) in dragState.frames where id != draggedID {
            guard frame.contains(location) else { continue }
            hoveredTargetID = id
            guard dragState.lastReorderTargetID != id else { return }

            guard let sourceIndex = projectStore.projects.firstIndex(where: { $0.id == draggedID }),
                  let destIndex = projectStore.projects.firstIndex(where: { $0.id == id })
            else { return }

            let sourceWorkspaceID = projectStore.projects[sourceIndex].workspaceID
            let destWorkspaceID = projectStore.projects[destIndex].workspaceID
            guard sourceWorkspaceID == destWorkspaceID else { return }

            dragState.lastReorderTargetID = id
            let offset = destIndex > sourceIndex ? destIndex + 1 : destIndex
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                projectStore.reorder(
                    fromOffsets: IndexSet(integer: sourceIndex), toOffset: offset
                )
            }
            return
        }

        if hoveredTargetID == nil {
            dragState.lastReorderTargetID = nil
        }
    }
}

private struct ProjectDragState {
    var draggedID: UUID?
    var frames: [UUID: CGRect] = [:]
    var lastReorderTargetID: UUID?
}

private enum SidebarSectionStore {
    private static let key = "muxy.sidebarSectionCollapsed"

    static func load() -> [UUID: Bool] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] else {
            return [:]
        }
        var result: [UUID: Bool] = [:]
        for (idString, collapsed) in raw {
            guard let id = UUID(uuidString: idString) else { continue }
            result[id] = collapsed
        }
        return result
    }

    static func save(_ value: [UUID: Bool]) {
        let encoded = Dictionary(uniqueKeysWithValues: value.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

private struct WorkspaceSectionHeader: View {
    let workspace: Workspace
    let isActive: Bool
    let isCollapsed: Bool
    let projectCount: Int
    let onToggle: () -> Void
    let onAddProject: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool
    @State private var hovered = false

    private var accentColor: Color {
        ProjectIconColor.color(for: workspace.iconColor) ?? MuxyTheme.fgMuted
    }

    private var workspaceMark: some View {
        Circle()
            .fill(accentColor)
            .frame(width: 8, height: 8)
    }

    var body: some View {
        HStack(spacing: UIMetrics.spacing2) {
            Button(action: onToggle) {
                HStack(spacing: UIMetrics.spacing2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: UIMetrics.fontCaption, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    workspaceMark
                    Text(workspace.name.uppercased())
                        .font(.system(size: UIMetrics.fontCaption, weight: .semibold))
                        .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                        .lineLimit(1)
                    if projectCount > 0, isCollapsed {
                        Text("\(projectCount)")
                            .font(.system(size: UIMetrics.fontMicro, weight: .semibold))
                            .foregroundStyle(MuxyTheme.fgMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(MuxyTheme.surface, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button(action: onAddProject) {
                Image(systemName: "plus")
                    .font(.system(size: UIMetrics.fontCaption, weight: .bold))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .frame(width: UIMetrics.controlMedium, height: UIMetrics.controlMedium)
                    .background(MuxyTheme.hover, in: RoundedRectangle(cornerRadius: UIMetrics.radiusSM))
            }
            .buttonStyle(.plain)
            .opacity(hovered || isActive ? 1 : 0)
            .allowsHitTesting(hovered || isActive)
            .help("Add Project to \(workspace.name)")
            .accessibilityLabel("Add Project to \(workspace.name)")
        }
        .padding(.vertical, UIMetrics.spacing1)
        .padding(.horizontal, UIMetrics.spacing2)
        .background(
            RoundedRectangle(cornerRadius: UIMetrics.radiusSM)
                .fill(isActive ? accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button(action: onRename) {
                Label("Rename Workspace…", systemImage: "pencil")
            }
            Button(action: onAddProject) {
                Label("Add Project to \(workspace.name)…", systemImage: "plus")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Workspace…", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
    }
}

private struct SidebarFooterContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: UIMetrics.spacing2) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct AddProjectButton: View {
    var expanded: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            if expanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Add Project")
    }

    private var collapsedLayout: some View {
        ZStack {
            Circle()
                .fill(MuxyTheme.hover)
            Image(systemName: "plus")
                .font(.system(size: UIMetrics.fontEmphasis, weight: .bold))
                .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgMuted)
        }
        .frame(width: UIMetrics.iconXXL, height: UIMetrics.iconXXL)
        .padding(UIMetrics.scaled(3))
    }

    private var expandedLayout: some View {
        HStack(spacing: UIMetrics.spacing4) {
            ZStack {
                Circle()
                    .fill(MuxyTheme.surface)
                Image(systemName: "plus")
                    .font(.system(size: UIMetrics.fontEmphasis, weight: .bold))
                    .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgMuted)
            }
            .frame(width: UIMetrics.iconXXL, height: UIMetrics.iconXXL)

            Text("Add Project")
                .font(.system(size: UIMetrics.fontBody, weight: .medium))
                .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgMuted)
                .lineLimit(1)
            Spacer()
        }
        .padding(UIMetrics.spacing2)
        .background(hovered ? MuxyTheme.hover : Color.clear, in: RoundedRectangle(cornerRadius: UIMetrics.radiusLG))
    }
}

struct SidebarFooter: View {
    var expanded: Bool = false
    @AppStorage(AIUsageSettingsStore.usageEnabledKey) private var usageEnabled = false
    @AppStorage(AIUsageSettingsStore.usageDisplayModeKey) private var usageDisplayModeRaw = AIUsageSettingsStore.defaultUsageDisplayMode
        .rawValue
    @AppStorage(AIUsageSettingsStore.sidebarPreviewProviderIDKey) private var pinnedPreviewProviderID: String = ""
    @State private var showAIUsagePopover = false
    private let usageService = AIUsageService.shared

    private var usageDisplayMode: AIUsageDisplayMode {
        AIUsageDisplayMode(rawValue: usageDisplayModeRaw) ?? AIUsageSettingsStore.defaultUsageDisplayMode
    }

    private let usageRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        if usageEnabled {
            footerBody
        }
    }

    private var footerBody: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedFooter
            } else {
                collapsedFooter
            }
        }
        .task {
            await usageService.refreshIfNeeded()
        }
        .onReceive(usageRefreshTimer) { _ in
            Task {
                await usageService.refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIUsage)) { _ in
            guard usageEnabled else { return }
            showAIUsagePopover.toggle()
        }
        .onChange(of: usageEnabled) { _, enabled in
            if !enabled {
                showAIUsagePopover = false
            }
        }
    }

    private var previewProviderDisplay: (percent: Int, iconName: String)? {
        guard let selection = usageService.previewSelection(pinnedRawValue: pinnedPreviewProviderID),
              case .available = selection.snapshot.state
        else { return nil }

        let snapshot = selection.snapshot
        let rowPercent = selection.row?.percent
        let usedPercent = max(0, min(100, rowPercent ?? snapshot.rows.compactMap(\.percent).max() ?? 0))
        let displayPercent: Double = switch usageDisplayMode {
        case .used:
            usedPercent
        case .remaining:
            max(0, min(100, 100 - usedPercent))
        }

        return (Int(displayPercent.rounded()), snapshot.providerIconName)
    }

    private var previewProviderPercentLabel: String? {
        guard let display = previewProviderDisplay else { return nil }
        return "\(max(0, min(100, display.percent)))%"
    }

    private var aiUsageButton: some View {
        AIUsagePreviewButton(
            display: previewProviderDisplay,
            percentLabel: previewProviderPercentLabel,
            expanded: expanded,
            onTap: { showAIUsagePopover.toggle() }
        )
        .popover(isPresented: $showAIUsagePopover) {
            AIUsagePanel(
                snapshots: usageService.snapshots,
                isRefreshing: usageService.isRefreshing,
                lastRefreshDate: usageService.lastRefreshDate,
                onRefresh: refreshUsage
            )
        }
        .help("AI Usage (\(KeyBindingStore.shared.combo(for: .toggleAIUsage).displayString))")
    }

    private var collapsedFooter: some View {
        SidebarFooterContainer {
            VStack(spacing: UIMetrics.spacing2) {
                if usageEnabled {
                    aiUsageButton
                }
            }
        }
        .padding(.bottom, UIMetrics.spacing4)
    }

    private var expandedFooter: some View {
        SidebarFooterContainer {
            HStack(spacing: UIMetrics.spacing2) {
                if usageEnabled {
                    aiUsageButton
                }
                Spacer()
            }
        }
        .padding(.horizontal, UIMetrics.spacing5)
        .padding(.bottom, UIMetrics.spacing4)
    }

    private func refreshUsage() {
        Task {
            await usageService.refresh(force: true)
        }
    }
}
