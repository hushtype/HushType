import Foundation
import IOKit.ps
import os

/// Monitors system power state (battery, thermal, memory pressure) and provides
/// recommendations for throttling inference workloads.
@Observable
final class PowerManagementService {
    // MARK: - Published State

    /// Whether the device is currently running on battery power.
    private(set) var isOnBattery: Bool = false

    /// Current thermal state of the system.
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Whether the system is under memory pressure (.warning or .critical).
    private(set) var isMemoryConstrained: Bool = false

    /// Whether battery-aware throttling is enabled by the user.
    var batteryAwareModeEnabled: Bool = true

    // MARK: - Callbacks

    /// Called when power state changes and the pipeline should reconfigure.
    var onPowerStateChanged: ((_ isOnBattery: Bool) -> Void)?

    /// Called when thermal state reaches .serious or .critical.
    var onThermalThrottleNeeded: ((_ state: ProcessInfo.ThermalState) -> Void)?

    /// Called when memory pressure requires model unloading.
    /// The parameter indicates the severity: .warning = unload LLM only, .critical = unload all.
    var onMemoryPressure: ((_ level: MemoryPressureLevel) -> Void)?

    // MARK: - Types

    enum MemoryPressureLevel {
        case warning   // Unload LLM model, keep whisper
        case critical  // Unload both LLM and whisper
        case normal    // Pressure subsided, safe to reload
    }

    // MARK: - Internals

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var thermalObserver: (any NSObjectProtocol)?
    private var batteryCheckTimer: Timer?

    // MARK: - Initialization

    init() {
        updateBatteryState()
        thermalState = ProcessInfo.processInfo.thermalState
        Logger.performance.info("PowerManagementService initialized (battery: \(self.isOnBattery), thermal: \(self.thermalState.rawValue))")
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start monitoring power, thermal, and memory pressure events.
    func start() {
        startBatteryMonitoring()
        startThermalMonitoring()
        startMemoryPressureMonitoring()
        Logger.performance.info("PowerManagementService monitoring started")
    }

    /// Stop all monitoring.
    func stop() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalObserver = nil
        }

        batteryCheckTimer?.invalidate()
        batteryCheckTimer = nil
    }

    // MARK: - Battery Monitoring

    private func startBatteryMonitoring() {
        // macOS doesn't have a direct power source change notification in Foundation.
        // Poll every 30 seconds to detect AC/battery transitions.
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateBatteryState()
        }
    }

    private func updateBatteryState() {
        let wasOnBattery = isOnBattery
        isOnBattery = checkBatteryPowerSource()

        if wasOnBattery != isOnBattery {
            Logger.performance.info("Power state changed: \(self.isOnBattery ? "battery" : "AC")")
            if batteryAwareModeEnabled {
                onPowerStateChanged?(isOnBattery)
            }
        }
    }

    /// Check if running on battery via IOKit power source info.
    private func checkBatteryPowerSource() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, firstSource)?.takeUnretainedValue() as? [String: Any],
              let powerSource = description[kIOPSPowerSourceStateKey as String] as? String else {
            return false
        }
        return powerSource == (kIOPSBatteryPowerValue as String)
    }

    // MARK: - Thermal Monitoring

    private func startThermalMonitoring() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
    }

    private func handleThermalStateChange() {
        let newState = ProcessInfo.processInfo.thermalState
        let previousState = thermalState
        thermalState = newState

        Logger.performance.info("Thermal state changed: \(previousState.rawValue) → \(newState.rawValue)")

        switch newState {
        case .serious, .critical:
            onThermalThrottleNeeded?(newState)
        case .nominal, .fair:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Memory Pressure Monitoring

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data

            if event.contains(.critical) {
                Logger.performance.warning("Memory pressure: CRITICAL — unloading all models")
                self.isMemoryConstrained = true
                self.onMemoryPressure?(.critical)
            } else if event.contains(.warning) {
                Logger.performance.warning("Memory pressure: WARNING — unloading LLM model")
                self.isMemoryConstrained = true
                self.onMemoryPressure?(.warning)
            } else {
                Logger.performance.info("Memory pressure: NORMAL — models can be reloaded")
                self.isMemoryConstrained = false
                self.onMemoryPressure?(.normal)
            }
        }

        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Recommendations

    /// Recommended whisper thread count based on power state.
    /// Returns 0 (auto) when on AC, or 2 when on battery to save energy.
    var recommendedWhisperThreadCount: Int {
        guard batteryAwareModeEnabled, isOnBattery else { return 0 }
        return 2
    }

    /// Whether LLM processing should be skipped due to thermal constraints.
    var shouldSkipLLMProcessing: Bool {
        thermalState == .critical
    }

    /// Whether the system is in a state where inference should be throttled.
    var shouldThrottle: Bool {
        (batteryAwareModeEnabled && isOnBattery) || thermalState == .serious || thermalState == .critical
    }
}
