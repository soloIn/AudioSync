import Combine
import CoreAudio

class AudioFormatManager: ObservableObject {
    static let shared: AudioFormatManager = AudioFormatManager()
    @Published var sampleRate: Int?
    @Published var bitDepth: Int?

    var currentFormat: (sampleRate: Int, bitDepth: Int) = (0, 0) {
        didSet {
            // 避免不必要的更新，如果值没有实际变化
            if oldValue.sampleRate != currentFormat.sampleRate
                || oldValue.bitDepth != currentFormat.bitDepth
            {
                print(
                    "currentFormat changed from (\(oldValue.sampleRate), \(oldValue.bitDepth)) to (\(currentFormat.sampleRate), \(currentFormat.bitDepth))"
                )
                sampleRate = currentFormat.sampleRate
                bitDepth = currentFormat.bitDepth
                onFormatUpdate?(
                    currentFormat.sampleRate, currentFormat.bitDepth)
            }
        }
    }
    var onFormatUpdate: ((Int, Int) -> Void)?

    // 保持原有日志监控和格式设置逻辑...
    // [原有代码的私有属性和方法保持不变]
    private var logProcess: Process?
    private var isMonitoring = false
    private let processingQueue = DispatchQueue(
        label: "com.audio.format.monitor", qos: .userInitiated)

    private var lastLogEntry: String = ""
    private var lastLogTime: TimeInterval = 0

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        setupLogProcess()
    }

    private func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: isRunning))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &isRunning)

        return status == noErr && isRunning != 0
    }

    private func setupLogProcess() {
        logProcess = Process()
        logProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        logProcess?.arguments = [
            "stream",
            "--predicate",
            "process == 'Music' AND message CONTAINS 'Input format'",
            "--info",
        ]

        let pipe = Pipe()
        logProcess?.standardOutput = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            self?.processingQueue.async {
                if let output = String(data: data, encoding: .utf8) {
                    self?.parseLog(output)
                }
            }
        }

        logProcess?.terminationHandler = { [weak self] process in
            // 确保在主线程或特定队列上更新状态
            DispatchQueue.main.async {
                print(
                    "AudioFormatManager: Log process terminated. Exit code: \(process.terminationStatus)"
                )
                self?.isMonitoring = false
            }
        }

        do {
            try logProcess?.run()
        } catch {
            print("AudioFormatManager: Process start error: \(error)")
            DispatchQueue.main.async {
                self.isMonitoring = false  // 启动失败，重置状态
            }
        }
    }

    private func parseLog(_ log: String) {
        let now = Date().timeIntervalSince1970
        guard log != lastLogEntry || now - lastLogTime > 0.2 else {
            return  // 忽略短时间内重复日志
        }

        lastLogEntry = log
        lastLogTime = now

        let pattern = #"(\d+) Hz.*?from (\d+)-bit source"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let nsLog = log as NSString
        regex.enumerateMatches(
            in: log, range: NSRange(location: 0, length: nsLog.length)
        ) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }

            let sampleRate = nsLog.substring(with: match.range(at: 1))
            let bitDepth = nsLog.substring(with: match.range(at: 2))

            if let sr = Int(sampleRate), let bd = Int(bitDepth) {
                DispatchQueue.main.async {
                    if self.currentFormat.sampleRate != sr
                        || self.currentFormat.bitDepth != bd
                    {
                        self.currentFormat = (sr, bd)
                    }
                }
            }
        }
    }

    func updateOutputFormat() {
        guard let deviceID = getDefaultOutputDevice(),
            deviceID != kAudioObjectUnknown
        else {
            return
        }

        setNominalSampleRate(currentFormat.sampleRate, for: deviceID)
        setStreamBitDepth(currentFormat.bitDepth, for: deviceID)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        logProcess?.terminate()
        logProcess = nil
        DispatchQueue.main.async { self.isMonitoring = false }
    }

    private func setNominalSampleRate(_ rate: Int, for device: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate = Float64(rate)
        let status = AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: sampleRate)),
            &sampleRate
        )

        if status != noErr {
            print("Sample rate set failed: \(status)")
        }
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            ) == noErr
        else {
            return nil
        }
        return deviceID
    }
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &name)
        if status == noErr {
            return name as String
        } else {
            return nil
        }
    }
    private func setStreamBitDepth(_ depth: Int, for device: AudioDeviceID) {
        // 先获取设备的所有输出流
        guard let streams = getOutputStreams(for: device) else {
            print("无法获取输出流")
            return
        }

        for stream in streams {
            // 1. 获取该流支持的物理格式
            guard let supportedFormats = getSupportedFormats(for: stream) else {
                continue
            }

            // 2. 寻找匹配的格式
            let targetFormat = findMatchingFormat(
                supportedFormats, depth: depth, rate: currentFormat.sampleRate)

            // 3. 设置物理格式
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: 0
            )

            var format = targetFormat.mFormat
            let status = AudioObjectSetPropertyData(
                stream,  // 关键修改：在stream上设置而不是device
                &address,
                0,
                nil,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                &format
            )

            if status == noErr {
                print(
                    "成功设置流 \(stream) 格式：\(format.mBitsPerChannel)bit/\(format.mSampleRate)Hz"
                )
            } else {
                print("设置失败，错误码: \(status)")
            }
        }
    }

    // 新增方法：获取设备的所有输出流
    private func getOutputStreams(for device: AudioDeviceID) -> [AudioStreamID]?
    {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )

        var dataSize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize)
                == noErr
        else {
            return nil
        }

        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        var streams = [AudioStreamID](repeating: 0, count: streamCount)
        guard
            AudioObjectGetPropertyData(
                device, &address, 0, nil, &dataSize, &streams) == noErr
        else {
            return nil
        }

        return streams
    }

    // 新增方法：获取流支持的物理格式
    private func getSupportedFormats(for stream: AudioStreamID)
        -> [AudioStreamRangedDescription]?
    {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var dataSize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(stream, &address, 0, nil, &dataSize)
                == noErr
        else {
            return nil
        }

        let formatCount =
            Int(dataSize) / MemoryLayout<AudioStreamRangedDescription>.size
        var formats = [AudioStreamRangedDescription](
            repeating: AudioStreamRangedDescription(), count: formatCount)
        guard
            AudioObjectGetPropertyData(
                stream, &address, 0, nil, &dataSize, &formats) == noErr
        else {
            return nil
        }

        return formats
    }

    // 新增方法：寻找匹配的格式
    private func findMatchingFormat(
        _ formats: [AudioStreamRangedDescription], depth: Int, rate: Int
    ) -> AudioStreamRangedDescription {
        // 优先寻找完全匹配
        if let exactMatch = formats.first(where: {
            Int($0.mFormat.mSampleRate) == rate
                && $0.mFormat.mBitsPerChannel == UInt32(depth)
        }) {
            return exactMatch
        }

        // 次选：匹配采样率，使用更高位深
        if let rateMatch = formats.filter({
            Int($0.mFormat.mSampleRate) == rate
        }).sorted(by: {
            $0.mFormat.mBitsPerChannel > $1.mFormat.mBitsPerChannel
        }).first {
            return rateMatch
        }

        // 最后返回默认格式
        return formats.first!
    }
}
