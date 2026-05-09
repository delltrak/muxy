import SwiftUI

struct MobileSettingsView: View {
    @Bindable private var service = MobileServerService.shared
    @Bindable private var devices = ApprovedDevicesStore.shared
    @State private var deviceToRevoke: ApprovedDevice?
    @State private var portText: String = ""
    @State private var portValidationError: String?
    @State private var showFreePortConfirmation = false

    @Environment(\.settingsSearchQuery) private var searchQuery

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { service.isEnabled },
            set: { newValue in
                if newValue, !commitPort() { return }
                service.setEnabled(newValue)
            }
        )
    }

    var body: some View {
        Form {
            mobileSection
            approvedDevicesSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { portText = String(service.port) }
        .onChange(of: service.port) { _, newValue in
            let text = String(newValue)
            if portText != text { portText = text }
        }
        .alert(
            "Free port \(String(service.port))?",
            isPresented: $showFreePortConfirmation
        ) {
            Button("Free Port", role: .destructive) {
                service.freePort()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will terminate any process currently listening on port \(String(service.port)).")
        }
        .alert(
            "Revoke \(deviceToRevoke?.name ?? "device")?",
            isPresented: Binding(
                get: { deviceToRevoke != nil },
                set: { if !$0 { deviceToRevoke = nil } }
            ),
            presenting: deviceToRevoke
        ) { device in
            Button("Revoke", role: .destructive) {
                devices.revoke(deviceID: device.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The device will be disconnected immediately and must request approval again to reconnect.")
        }
    }

    @ViewBuilder
    private var mobileSection: some View {
        if isSectionVisible(["Allow mobile device connections", "Port"], extra: ["mobile", "iphone"]) {
            Section {
                SettingsSearchableRow(
                    "Allow mobile device connections",
                    keywords: ["mobile", "ios", "iphone"]
                ) {
                    Toggle("", isOn: enabledBinding).labelsHidden()
                }

                SettingsSearchableRow("Port") {
                    TextField("\(MobileServerService.defaultPort)", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140)
                        .onChange(of: portText) { _, _ in
                            guard portText != String(service.port) else { return }
                            portValidationError = nil
                            if service.isEnabled {
                                service.setEnabled(false)
                            }
                        }
                        .onSubmit { _ = commitPort() }
                }

                if let error = portValidationError ?? service.lastError {
                    HStack(spacing: 6) {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if service.isPortInUse {
                            Button("Free Port") {
                                showFreePortConfirmation = true
                            }
                        }
                    }
                }
            } header: {
                Text("Mobile")
            } footer: {
                Text(
                    "Muxy listens on the configured port for the iOS app over your local "
                        + "network or a private VPN such as Tailscale."
                )
            }
        }
    }

    @ViewBuilder
    private var approvedDevicesSection: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let visibleDevices: [ApprovedDevice] = {
            guard !trimmed.isEmpty else { return devices.devices }
            return devices.devices.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }()

        let sectionMatches = trimmed.isEmpty
            || "Approved Devices".localizedCaseInsensitiveContains(trimmed)
            || !visibleDevices.isEmpty

        if sectionMatches {
            Section {
                if devices.devices.isEmpty {
                    Text("No devices approved yet.")
                        .foregroundStyle(.secondary)
                } else if visibleDevices.isEmpty {
                    Text("No devices match your search.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleDevices) { device in
                        deviceRow(device)
                    }
                }
            } header: {
                Text("Approved Devices")
            } footer: {
                Text("Revoking removes the device's access. It will need to request approval again to reconnect.")
            }
        }
    }

    private func commitPort() -> Bool {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = UInt16(trimmed), MobileServerService.isValid(port: value) else {
            portValidationError = "Enter a port between \(MobileServerService.minPort) and \(MobileServerService.maxPort)."
            return false
        }
        portValidationError = nil
        service.port = value
        portText = String(value)
        return true
    }

    private func deviceRow(_ device: ApprovedDevice) -> some View {
        LabeledContent {
            Button("Revoke", role: .destructive) {
                deviceToRevoke = device
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(lastSeenText(device))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lastSeenText(_ device: ApprovedDevice) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        if let seen = device.lastSeenAt {
            return "Last seen \(formatter.localizedString(for: seen, relativeTo: Date()))"
        }
        return "Approved \(formatter.localizedString(for: device.approvedAt, relativeTo: Date()))"
    }

    private func isSectionVisible(_ labels: [String], extra: [String] = []) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let haystack = labels + extra
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
