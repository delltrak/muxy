import MuxyShared
import SwiftUI

struct WorkspaceEditorSheet: View {
    enum Mode {
        case create
        case rename(current: Workspace)
    }

    struct Result {
        var name: String
        var iconColor: String?
    }

    let mode: Mode
    let onSubmit: (Result) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var iconColor: String?
    @FocusState private var nameFocused: Bool

    private var title: String {
        switch mode {
        case .create: "New Workspace"
        case let .rename(workspace): "Rename \(workspace.name)"
        }
    }

    private var submitLabel: String {
        switch mode {
        case .create: "Create"
        case .rename: "Save"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIMetrics.spacing4) {
            Text(title)
                .font(.system(size: UIMetrics.fontTitleLarge, weight: .semibold))

            VStack(alignment: .leading, spacing: UIMetrics.spacing2) {
                Text("Name")
                    .font(.system(size: UIMetrics.fontCaption, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgMuted)
                TextField("Acme Corp", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(submit)
            }

            iconColorRow

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(submitLabel, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(UIMetrics.spacing5)
        .frame(width: 360)
        .onAppear {
            if case let .rename(workspace) = mode {
                name = workspace.name
                iconColor = workspace.iconColor
            }
            nameFocused = true
        }
    }

    private var iconColorRow: some View {
        VStack(alignment: .leading, spacing: UIMetrics.spacing2) {
            Text("Color")
                .font(.system(size: UIMetrics.fontCaption, weight: .medium))
                .foregroundStyle(MuxyTheme.fgMuted)
            HStack(spacing: UIMetrics.spacing2) {
                ForEach(ProjectIconColor.palette) { swatch in
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if iconColor == swatch.id {
                                Circle()
                                    .strokeBorder(MuxyTheme.fg, lineWidth: 2)
                            }
                        }
                        .contentShape(Circle())
                        .onTapGesture {
                            iconColor = (iconColor == swatch.id) ? nil : swatch.id
                        }
                }
            }
        }
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        onSubmit(Result(name: trimmedName, iconColor: iconColor))
        dismiss()
    }
}
