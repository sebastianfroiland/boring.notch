//
//  BluetoothActivityMonitor.swift
//  boringNotch
//
//  Live activity when AirPods or another Bluetooth device connects, with battery level.
//  Licensed under GPL-3.0 like the rest of the project.
//

import Defaults
import Foundation
import IOBluetooth
import IOKit
import SwiftUI

final class BluetoothActivityMonitor: NSObject {
    static let shared = BluetoothActivityMonitor()

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date.distantPast
    private var recent: [String: Date] = [:]

    override private init() {}

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        // Registering also reports devices that are already connected; those are ignored (see startedAt).
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        guard Defaults[.isleBluetoothActivity] else { return }

        let address = device.addressString ?? device.name ?? UUID().uuidString
        if let last = recent[address], Date().timeIntervalSince(last) < 15 { return }
        recent[address] = Date()

        // Battery values arrive a moment after the link comes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let name = device.name ?? "Bluetooth device"
            let battery = self.batteryLevel(for: device)
            let icon = Self.symbol(for: device)
            Task { @MainActor in
                IsleActivityCenter.shared.post(
                    IsleActivity(
                        kind: .bluetooth,
                        icon: icon,
                        tint: Self.tint(for: battery),
                        title: name,
                        trailingText: battery.map { "\($0) %" } ?? "Connected",
                        progress: battery.map { Double($0) / 100 },
                        duration: 4
                    )
                )
            }
        }
    }

    // MARK: - Battery

    /// AirPods/Beats expose battery through (undocumented) IOBluetoothDevice properties;
    /// Apple keyboards, mice and trackpads through the IORegistry.
    private func batteryLevel(for device: IOBluetoothDevice) -> Int? {
        var values: [Int] = []
        for key in ["batteryPercentLeft", "batteryPercentRight"] {
            if let value = readInt(device, key), value > 0 { values.append(value) }
        }
        if !values.isEmpty { return values.min() }
        for key in ["batteryPercentCombined", "batteryPercentSingle"] {
            if let value = readInt(device, key), value > 0 { return value }
        }
        return registryBatteryLevel(address: device.addressString)
    }

    private func readInt(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)) else { return nil }
        return (device.value(forKey: key) as? NSNumber)?.intValue
    }

    private func registryBatteryLevel(address: String?) -> Int? {
        guard let address else { return nil }
        let wanted = Self.normalize(address)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard
                let deviceAddress = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String,
                Self.normalize(deviceAddress) == wanted,
                let percent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber
            else { continue }
            return percent.intValue
        }
        return nil
    }

    private static func normalize(_ address: String) -> String {
        address.lowercased().filter { $0.isHexDigit }
    }

    // MARK: - Presentation

    private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("mouse") { return "magicmouse" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        // Major device class 0x04 = audio/video.
        if device.deviceClassMajor == 0x04 { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }

    private static func tint(for battery: Int?) -> Color {
        guard let battery else { return .blue }
        if battery <= 10 { return .red }
        if battery <= 20 { return .orange }
        return .green
    }
}
