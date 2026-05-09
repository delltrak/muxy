import Foundation

@MainActor
enum SettingsDefaultsRestorer {
    static func restore(tab: SettingsTab) {
        switch tab {
        case .general:
            restoreGeneral()
        case .appearance:
            restoreAppearance()
        case .editor:
            EditorSettings.shared.resetToDefaults()
            MarkdownPreviewPreferences.allowRemoteImages = true
        case .shortcuts:
            KeyBindingStore.shared.resetToDefaults()
            CommandShortcutStore.shared.deleteAllShortcuts()
            CommandShortcutStore.shared.resetPrefixCombo()
        case .notifications:
            restoreNotifications()
        case .mobile:
            restoreMobile()
        case .aiUsage:
            restoreAIUsage()
        }
    }

    private static func restoreGeneral() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: GeneralSettingsKeys.autoExpandWorktreesOnProjectSwitch)
        defaults.removeObject(forKey: GeneralSettingsKeys.defaultWorktreeParentPath)
        defaults.removeObject(forKey: TabCloseConfirmationPreferences.confirmRunningProcessKey)
        defaults.removeObject(forKey: ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
        defaults.removeObject(forKey: QuitConfirmationPreferences.confirmQuitKey)
        defaults.removeObject(forKey: UpdateChannel.storageKey)
        UpdateService.shared.channel = .stable
    }

    private static func restoreAppearance() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "muxy.vcsDisplayMode")
        defaults.removeObject(forKey: SidebarCollapsedStyle.storageKey)
        defaults.removeObject(forKey: SidebarExpandedStyle.storageKey)
        UIScale.shared.preset = UIScale.defaultPreset
    }

    private static func restoreNotifications() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "muxy.notifications.sound")
        defaults.removeObject(forKey: "muxy.notifications.toastEnabled")
        defaults.removeObject(forKey: "muxy.notifications.toastPosition")
        for provider in AIProviderRegistry.shared.providers {
            defaults.removeObject(forKey: provider.settingsKey)
        }
        AIProviderRegistry.shared.installAll()
    }

    private static func restoreMobile() {
        MobileServerService.shared.setEnabled(false)
        MobileServerService.shared.port = MobileServerService.defaultPort
    }

    private static func restoreAIUsage() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AIUsageSettingsStore.usageEnabledKey)
        defaults.removeObject(forKey: AIUsageSettingsStore.usageDisplayModeKey)
        defaults.removeObject(forKey: AIUsageSettingsStore.autoRefreshIntervalKey)
        defaults.removeObject(forKey: AIUsageSettingsStore.showSecondaryLimitsKey)
        defaults.removeObject(forKey: AIUsageSettingsStore.sidebarPreviewProviderIDKey)
        for provider in AIUsageProviderCatalog.providers {
            defaults.removeObject(forKey: AIUsageProviderTrackingStore.trackingKey(providerID: provider.id))
            defaults.removeObject(forKey: AIUsageProviderEnabledStore.enabledKey(providerID: provider.id))
        }
        AIUsageService.shared.recomposeSnapshots()
    }
}
