import CoreAudio
import CoreMediaIO
import Foundation
import VishramaCore

/// "Am I in a meeting?" proxy: any camera or microphone in active use anywhere.
/// Reading these properties needs no TCC permission.
@MainActor
final class CameraMicSignal: SignalProvider {
    let kind = SignalKind.cameraMic
    private(set) var isActive = false
    private var timer: Timer?

    func start() {
        poll()
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func poll() {
        isActive = Self.anyCameraRunning() || Self.anyMicrophoneRunning()
    }

    // MARK: - CoreMediaIO (cameras)

    private static func anyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize) == 0,
              dataSize > 0 else { return false }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataUsed, &devices) == 0
        else { return false }

        var runningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for device in devices {
            var running: UInt32 = 0
            var used: UInt32 = 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, size, &used, &running) == 0,
               running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: - CoreAudio (microphones)

    private static func anyMicrophoneRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == 0,
            dataSize > 0 else { return false }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == 0
        else { return false }

        for device in devices where hasInputStreams(device) {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &running) == 0,
               running != 0 {
                return true
            }
        }
        return false
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == 0 && dataSize > 0
    }
}
