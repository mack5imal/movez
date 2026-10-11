import AppKit
import Combine

/// Everything the settings window can do, in one place.
///
/// Every write goes through here rather than straight at the store, because each one has to reach
/// the scheduler as well: settings apply live, and the scheduler re-plans the bout that is already
/// running rather than starting it over.
@MainActor
final class SettingsViewModel: ObservableObject {
    enum Sheet: String, Identifiable, Equatable {
        case workingHours
        case library
        case exceptions

        var id: String { rawValue }
    }

    let settings: SettingsStore
    let library: MovementLibrary
    let launchAtLogin: LaunchAtLoginService
    private let onChange: () -> Void
    private var debugCancellables: Set<AnyCancellable> = []

    @Published var openSheet: Sheet?
    /// The working hours being edited. Nothing is written until Apply passes validation.
    @Published var hoursDraft: WorkingHours
    @Published var hoursError: String?
    @Published var librarySearch = ""
    @Published var libraryBucket: Bucket?
    @Published var launchAtLoginError: String?
    /// The debug tools, once they are attached. Absent in contexts with no coordinator.
    @Published var debug: DebugState?
    var debugActions = DebugActions()

    init(
        settings: SettingsStore,
        library: MovementLibrary,
        launchAtLogin: LaunchAtLoginService? = nil,
        onChange: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.library = library
        self.launchAtLogin = launchAtLogin ?? SystemLaunchAtLogin()
        self.onChange = onChange
        hoursDraft = settings.workingHours
    }

    // MARK: - The option tables

    static let presetOptions: [(value: PresetId, label: String)] = [
        (.twentyFiveFive, "25 / 5"),
        (.fiftyFiveFive, "55 / 5"),
        (.eightyFiveFive, "85 / 5"),
        (.custom, "Custom")
    ]

    static let difficultyOptions: [(value: Int, label: String)] = [
        (1, "Beginner"),
        (2, "Moderate"),
        (3, "Advanced")
    ]

    static var equipmentOptions: [Equipment] { Equipment.allCases }
    static var focusOptions: [(value: Focus, label: String)] {
        Focus.allCases.map { ($0, $0.displayName) }
    }

    static var awayOptions: [(value: Int, label: String)] {
        SettingsStore.awayThresholdRange.map { ($0, "\($0) min") }
    }

    // MARK: - Derived text

    /// "movez 0.5.0 (38) · library v4.1 · 159 movements"
    ///
    /// Every part is read from what is installed rather than written down here: the app version and
    /// build number from the bundle (set in `project.yml` and stamped with the commit count at build
    /// time), the library version and size from the JSON. A bump of either shows up on its own.
    var versionLine: String {
        Self.versionLine(info: Bundle.main.infoDictionary ?? [:], library: library)
    }

    static func versionLine(info: [String: Any], library: MovementLibrary) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = (info["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        return "movez \(version)\(build) · library v\(library.version) · \(library.movements.count) movements"
    }

    var excludedLine: String { "\(settings.excludedMovementIds.count) excluded" }

    var exceptionsLine: String {
        let count = settings.fullscreenExceptions.count
        return "\(count) exception\(count == 1 ? "" : "s")"
    }

    var workingHoursSummary: String { settings.workingHours.summary() }

    /// "Micro-break every 30 min" — the cadence comes from the config, not from a literal.
    var microRowLabel: String {
        let config = settings.schedulerConfig
        return "Micro-break every \(config.microEverySeconds / 60) min"
    }

    var microRowDetail: String { "· 1 min" }

    var customSitLabel: String { "\(settings.customSitMinutes) min" }

    // MARK: - Schedule

    func setPreset(_ preset: PresetId) {
        settings.preset = preset
        changed()
    }

    /// The custom stepper walks 15–120 in fives; anything else is clamped onto that ladder.
    func setCustomMinutes(_ minutes: Int) {
        settings.customSitMinutes = SchedulerConfig.clampCustom(minutes)
        changed()
    }

    func stepCustomMinutes(by steps: Int) {
        setCustomMinutes(settings.customSitMinutes + steps * SchedulerConfig.customSitStepMinutes)
    }

    func setMicroEnabled(_ enabled: Bool) {
        settings.microEnabled = enabled
        changed()
    }

    // MARK: - Working hours

    func beginEditingHours() {
        hoursDraft = settings.workingHours
        hoursError = nil
        openSheet = .workingHours
    }

    func applyHours() {
        guard let message = Self.hoursMessage(hoursDraft.validate()) else {
            settings.workingHours = hoursDraft
            hoursError = nil
            openSheet = nil
            changed()
            return
        }
        hoursError = message
    }

    /// "End must be after start (Fri)" — the rule, and which day broke it.
    static func hoursMessage(_ errors: [WorkingHoursError]) -> String? {
        let days = errors.compactMap { error -> String? in
            guard case .endNotAfterStart(let day) = error else { return nil }
            return day
        }
        guard !days.isEmpty else { return nil }
        return "End must be after start (\(days.joined(separator: ", ")))"
    }

    // MARK: - Movements

    func toggleEquipment(_ item: Equipment) {
        if settings.equipment.contains(item) {
            settings.equipment.remove(item)
        } else {
            settings.equipment.insert(item)
        }
        changed()
    }

    func setDifficultyCap(_ cap: Int) {
        settings.difficultyCap = cap
        changed()
    }

    func setFocus(_ focus: Focus) {
        settings.focus = focus
        changed()
    }

    func setExcluded(_ movementId: String, _ excluded: Bool) {
        if excluded {
            settings.excludedMovementIds.insert(movementId)
        } else {
            settings.excludedMovementIds.remove(movementId)
        }
        changed()
    }

    func isExcluded(_ movementId: String) -> Bool {
        settings.excludedMovementIds.contains(movementId)
    }

    /// Name or id, case-insensitive, inside the chosen bucket.
    func matchingMovements() -> [Movement] {
        let query = librarySearch.trimmingCharacters(in: .whitespaces).lowercased()
        return library.movements.filter { movement in
            guard libraryBucket == nil || movement.bucket == libraryBucket else { return false }
            guard !query.isEmpty else { return true }
            return movement.name.lowercased().contains(query) || movement.id.lowercased().contains(query)
        }
    }

    // MARK: - Staying out of the way

    func setSuppressMic(_ on: Bool) {
        settings.suppressMic = on
        changed()
    }

    func setSuppressCapture(_ on: Bool) {
        settings.suppressCapture = on
        changed()
    }

    func setSuppressFullscreen(_ on: Bool) {
        settings.suppressFullscreen = on
        changed()
    }

    func setAwayMinutes(_ minutes: Int) {
        let range = SettingsStore.awayThresholdRange
        settings.awayThresholdMinutes = min(range.upperBound, max(range.lowerBound, minutes))
        changed()
    }

    func addException(_ bundleId: String) {
        guard !bundleId.isEmpty, !settings.fullscreenExceptions.contains(bundleId) else { return }
        settings.fullscreenExceptions.append(bundleId)
        changed()
    }

    func removeException(_ bundleId: String) {
        settings.fullscreenExceptions.removeAll { $0 == bundleId }
        changed()
    }

    /// Apps with a Dock icon that are not already exceptions.
    func exceptionCandidates() -> [(value: String, label: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (value: String, label: String)? in
                guard let bundleId = app.bundleIdentifier else { return nil }
                guard !settings.fullscreenExceptions.contains(bundleId) else { return nil }
                return (bundleId, app.localizedName ?? bundleId)
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// The app's own name, or its bundle id when it is not installed any more.
    static func applicationName(for bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func applicationIcon(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - General

    func setSounds(_ on: Bool) {
        settings.soundsEnabled = on
        changed()
    }

    /// A refusal is shown under the row rather than swallowed: an ad-hoc-signed build genuinely
    /// cannot register a login item, and a toggle that silently springs back is worse than a
    /// sentence saying why.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            try launchAtLogin.setEnabled(on)
            settings.launchAtLogin = on
            launchAtLoginError = nil
        } catch {
            settings.launchAtLogin = launchAtLogin.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    /// Reconciles the toggle with what the system actually thinks, which can change outside movez.
    func syncLaunchAtLogin() {
        settings.launchAtLogin = launchAtLogin.isEnabled
    }

    func setDebugExpanded(_ expanded: Bool) {
        settings.debugExpanded = expanded
        objectWillChange.send()
    }

    /// Connects the debug tools to the window. Everything the section draws flows through
    /// `debug`, so the section itself never reaches for a coordinator.
    func attach(debug viewModel: DebugViewModel) {
        debugActions = viewModel.actions
        debug = viewModel.state
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.debug = state }
            .store(in: &debugCancellables)
    }

    private func changed() {
        objectWillChange.send()
        onChange()
    }
}
