import Foundation
import DiskArbitration
import IOKit
import IOKit.storage

struct DroneDetector {
    private let fm = FileManager.default

    func mountedDroneVolumes() -> [URL] {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsReadOnlyKey]
        let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal == true,
                  values.volumeIsRemovable == true,
                  values.volumeIsReadOnly != true else { return false }
            return isDJIUSBVolume(url) && looksLikeDJIMediaVolume(url)
        }
    }

    /// Resolves the mount to its BSD disk and walks that disk's I/O Registry
    /// parents. This ties each accepted volume to the physical DJI USB device;
    /// merely naming a drive "DJI" or creating a DJI-like DCIM folder is not enough.
    private func isDJIUSBVolume(_ volume: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let bsdNamePointer = DADiskGetBSDName(disk) else { return false }
        let bsdName = String(cString: bsdNamePointer)
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return false }
        var current = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        while current != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let values = properties?.takeRetainedValue() as? [String: Any] {
                let vendorID = (values["idVendor"] as? NSNumber)?.intValue
                    ?? (values["USB Vendor ID"] as? NSNumber)?.intValue
                let vendorName = (values["USB Vendor Name"] as? String)
                    ?? (values["kUSBVendorString"] as? String)
                    ?? (values["Manufacturer"] as? String)
                if vendorID == 0x2CA3 || vendorName?.localizedCaseInsensitiveContains("DJI") == true {
                    IOObjectRelease(current)
                    return true
                }
            }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard result == KERN_SUCCESS else { return false }
            current = parent
        }
        return false
    }

    private func looksLikeDJIMediaVolume(_ volume: URL) -> Bool {
        let dcim = volume.appendingPathComponent("DCIM", isDirectory: true)
        guard fm.fileExists(atPath: dcim.path),
              let children = try? fm.contentsOfDirectory(at: dcim, includingPropertiesForKeys: nil) else { return false }
        let djiFolder = children.contains { $0.lastPathComponent.uppercased().hasPrefix("DJI_") }
        let knownName = ["DJIEXTERNAL", "DJI INTERNAL"].contains(volume.lastPathComponent.uppercased())
        return djiFolder || knownName
    }
}

@MainActor
final class VolumeMonitor {
    private var timer: Timer?
    private var lastSet = Set<String>()
    var onChange: (([URL]) -> Void)?

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func check() {
        let volumes = DroneDetector().mountedDroneVolumes()
        let current = Set(volumes.map(\.path))
        if current != lastSet {
            lastSet = current
            onChange?(volumes)
        }
    }
}
