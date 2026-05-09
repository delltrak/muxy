import AppKit
import SwiftUI

struct SplitContainer: View {
    let branch: SplitBranch
    let focusedAreaID: UUID?
    let isActiveProject: Bool
    let showVCSButton: Bool
    let projectID: UUID
    let shortcutOffsets: [UUID: Int]
    let onFocusArea: (UUID) -> Void
    let onSelectTab: (UUID, UUID) -> Void
    let onCreateTab: (UUID) -> Void
    let onCreateVCSTab: (UUID) -> Void
    let onCloseTab: (UUID, UUID) -> Void
    let onForceCloseTab: (UUID, UUID) -> Void
    let onSplit: (UUID, SplitDirection) -> Void
    let onCloseArea: (UUID) -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void

    var body: some View {
        if branch.direction == .horizontal {
            horizontalLayout
        } else {
            verticalLayout
        }
    }

    private var horizontalLayout: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let first = max(0, total * branch.ratio - 0.5)
            let second = max(0, total * (1 - branch.ratio) - 0.5)
            HStack(spacing: 0) {
                child(branch.first)
                    .frame(width: first)

                horizontalDivider(total: total)

                child(branch.second)
                    .frame(width: second)
            }
        }
    }

    private var verticalLayout: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let first = max(0, total * branch.ratio - 0.5)
            let second = max(0, total * (1 - branch.ratio) - 0.5)
            VStack(spacing: 0) {
                child(branch.first)
                    .frame(height: first)

                verticalDivider(total: total)

                child(branch.second)
                    .frame(height: second)
            }
        }
    }

    private func horizontalDivider(total: CGFloat) -> some View {
        Color.clear
            .frame(width: 1)
            .overlay(Rectangle().fill(MuxyTheme.border))
            .overlay {
                Color.clear
                    .frame(width: UIMetrics.scaled(5))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                let startPos = total * branch.ratio
                                let newPos = startPos + (v.location.x - v.startLocation.x)
                                branch.ratio = min(max(newPos / total, 0.15), 0.85)
                            }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
            .accessibilityLabel("Horizontal Split Divider")
            .accessibilityValue("Split ratio: \(Int(branch.ratio * 100))%")
            .accessibilityAdjustableAction(adjustRatio)
    }

    private func verticalDivider(total: CGFloat) -> some View {
        Color.clear
            .frame(height: 1)
            .overlay(Rectangle().fill(MuxyTheme.border))
            .overlay {
                Color.clear
                    .frame(height: UIMetrics.scaled(5))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                let startPos = total * branch.ratio
                                let newPos = startPos + (v.location.y - v.startLocation.y)
                                branch.ratio = min(max(newPos / total, 0.15), 0.85)
                            }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
            }
            .accessibilityLabel("Vertical Split Divider")
            .accessibilityValue("Split ratio: \(Int(branch.ratio * 100))%")
            .accessibilityAdjustableAction(adjustRatio)
    }

    private func adjustRatio(_ direction: AccessibilityAdjustmentDirection) {
        let step: CGFloat = 0.05
        switch direction {
        case .increment:
            branch.ratio = min(branch.ratio + step, 0.85)
        case .decrement:
            branch.ratio = max(branch.ratio - step, 0.15)
        @unknown default:
            break
        }
    }

    private func child(_ node: SplitNode) -> some View {
        PaneNode(
            node: node,
            focusedAreaID: focusedAreaID,
            isActiveProject: isActiveProject,
            showVCSButton: showVCSButton,
            projectID: projectID,
            shortcutOffsets: shortcutOffsets,
            onFocusArea: onFocusArea,
            onSelectTab: onSelectTab,
            onCreateTab: onCreateTab,
            onCreateVCSTab: onCreateVCSTab,
            onCloseTab: onCloseTab,
            onForceCloseTab: onForceCloseTab,
            onSplit: onSplit,
            onCloseArea: onCloseArea,
            onDropAction: onDropAction
        )
    }
}
