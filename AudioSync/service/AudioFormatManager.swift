import Combine
import CoreAudio

class AudioFormatManager: ObservableObject {
    @MainActor static let shared: AudioFormatManager = AudioFormatManager()
    @Published var sampleRate: Int?
    @Published var bitDepth: Int?

    private static let logRegex: NSRegularExpression? = {
        let pattern = #"(\d+) Hz.*?from (\d+)-bit source"#
        return try? NSRegularExpression(pattern: pattern)
    }()
    var needChange: Bool = true
    var currentFormat: (sampleRate: Int, bitDepth: Int) = (0, 0) {
        didSet {
            Log.backend.info("Format change from \(oldValue) to \(currentFormat)")
            // 避免不必要的更新，如果值没有实际变化
            if oldValue.sampleRate != currentFormat.sampleRate
                || oldValue.bitDepth != currentFormat.bitDepth
            {
                sampleRate = currentFormat.sampleRate
                bitDepth = currentFormat.bitDepth
                needChange = true
                onFormatUpdate?(
                    currentFormat.sampleRate,
                    currentFormat.bitDepth
                )
            } else {
                needChange = false
            }
        }
    }
    var onFormatUpdate: ((Int, Int) -> Void)?

    // 保持原有日志监控和格式设置逻辑...
    // [原有代码的私有属性和方法保持不变]
    private var logProcess: Process?
    private var logPipe: Pipe?
    private var isMonitoring = false
    private let processingQueue = DispatchQueue(
        label: "com.audio.format.monitor",
        qos: .userInitiated
    )

    private var lastLogEntry: String = ""
    private var lastLogTime: TimeInterval = 0

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        Log.backend.info("start log monitoring")
        // 先抓过去 1 秒的历史日志，避免漏掉启动前的 Input format
        fetchRecentLogs()

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
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )

        return status == noErr && isRunning != 0
    }
    private func fetchRecentLogs() {
        // 在后台队列中执行，避免阻塞主线程
        processingQueue.async { [weak self] in
            let showProcess = Process()
            showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            showProcess.arguments = [
                "show",
                "--style", "syslog",
                "--last", "1s",
                "--predicate",
                "process == 'Music' AND message CONTAINS 'ACAppleLosslessDecoder' AND message CONTAINS 'Input format' AND message CONTAINS 'source'",
                "--info",
            ]

            let pipe = Pipe()
            showProcess.standardOutput = pipe

            do {
                try showProcess.run()

                // 同步读取所有输出数据，直到进程结束
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                showProcess.waitUntilExit()  // 确保进程已完全终止

                if let output = String(data: data, encoding: .utf8),
                    !output.isEmpty
                {
                    self?.parseLogOnBackground(output)
                }
            } catch {
                Log.backend.error(
                    "AudioFormatManager: fetchRecentLogs error: \(error)"
                )
            }
        }
    }
    private func setupLogProcess() {
        logProcess = Process()
        logProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        logProcess?.arguments = [
            "stream",
            "--predicate",
            "process == 'Music' AND message CONTAINS 'ACAppleLosslessDecoder' AND message CONTAINS 'Input format' AND message CONTAINS 'source'",
            "--info",
        ]

        let pipe = Pipe()
        self.logPipe = pipe
        logProcess?.standardOutput = pipe

        // 2. ✅ 优化读取处理逻辑
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            // 使用 autoreleasepool 确保每次读取的临时变量立即释放
            autoreleasepool {
                let data = handle.availableData
                guard !data.isEmpty else { return }

                guard let output = String(data: data, encoding: .utf8) else {
                    return
                }

                // 3. ✅ 在后台线程直接解析，不要派发给 MainActor
                self?.parseLogOnBackground(output)
            }
        }

        logProcess?.terminationHandler = { process in
            DispatchQueue.main.async {
                if AudioFormatManager.shared.isMonitoring == true {  // 仅在仍在监控状态时重置
                    AudioFormatManager.shared.isMonitoring = false
                }
            }
        }

        do {
            try logProcess?.run()
        } catch {
            Log.backend.error(
                "AudioFormatManager: setupLogProcess   error: \(error)"
            )
            DispatchQueue.main.async {
                AudioFormatManager.shared.isMonitoring = false  // 启动失败，重置状态
            }
        }
    }
    private func parseLogOnBackground(_ log: String) {
        guard let regex = AudioFormatManager.logRegex else { return }

        let nsLog = log as NSString

        regex.enumerateMatches(
            in: log,
            range: NSRange(location: 0, length: nsLog.length)
        ) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }

            let sampleRateStr = nsLog.substring(with: match.range(at: 1))
            let bitDepthStr = nsLog.substring(with: match.range(at: 2))

            if let sr = Int(sampleRateStr), let bd = Int(bitDepthStr) {
                // 5. ✅ 解析成功后，再检查是否需要更新，减少主线程负担
                if self.currentFormat.sampleRate == sr,
                    self.currentFormat.bitDepth == bd
                {
                    return
                }
                // 只有真正需要更新时，才切回主线程
                Task { @MainActor in
                    AudioFormatManager.shared.currentFormat = (sr, bd)
                    AudioFormatManager.shared.stopMonitoring()
                }
            }
        }
    }

    func updateOutputFormat() {
        if !needChange {
            return
        }
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
        Log.backend.info("stop log monitoring")
        // 1. 清理流式监控的 handler
        logPipe?.fileHandleForReading.readabilityHandler = nil

        // 2. 终止流式监控的进程
        if logProcess?.isRunning == true {
            logProcess?.terminate()
        }

        // 3. 释放资源引用
        logProcess = nil
        logPipe = nil

        DispatchQueue.main.async {
            AudioFormatManager.shared.isMonitoring = false
        }
    }

    deinit {
        // 清理 Process 资源
        logProcess?.terminate()
        logProcess = nil
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
            Log.backend.error("Sample rate set  \(status)")
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
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        if status == noErr {
            return name as String
        } else {
            return nil
        }
    }
    private func setStreamBitDepth(_ depth: Int, for device: AudioDeviceID) {
        // 先获取设备的所有输出流
        guard let streams = getOutputStreams(for: device) else {
            Log.backend.error("无法获取输出流")
            return
        }

        for stream in streams {
            // 1. 获取该流支持的物理格式
            guard let supportedFormats = getSupportedFormats(for: stream) else {
                continue
            }

            // 2. 寻找匹配的格式
            let targetFormat = findMatchingFormat(
                supportedFormats,
                depth: depth,
                rate: currentFormat.sampleRate
            )

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
                let deviceName =
                    getDeviceName(device) as NSString? ?? "Unknown Device"
                Log.backend.info(
                    "成功为「\(deviceName)」同步格式：\(format.mBitsPerChannel)bit/\(format.mSampleRate)Hz"
                )
            } else {
                Log.backend.error("设置失败 - \(status)")
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
                device,
                &address,
                0,
                nil,
                &dataSize,
                &streams
            ) == noErr
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
            repeating: AudioStreamRangedDescription(),
            count: formatCount
        )
        guard
            AudioObjectGetPropertyData(
                stream,
                &address,
                0,
                nil,
                &dataSize,
                &formats
            ) == noErr
        else {
            return nil
        }

        return formats
    }

    // 新增方法：寻找匹配的格式
    private func findMatchingFormat(
        _ formats: [AudioStreamRangedDescription],
        depth: Int,
        rate: Int
    ) -> AudioStreamRangedDescription {
        // 优先寻找完全匹配
        if let exactMatch = formats.first(where: {
            Int($0.mFormat.mSampleRate) == rate
                && $0.mFormat.mBitsPerChannel == UInt32(depth)
        }) {
            return exactMatch
        }
        let simplifiedFormats = formats.map { format in
            [
                "sampleRate": format.mFormat.mSampleRate,
                "bitDepth": format.mFormat.mBitsPerChannel,
            ]
        }
        let msg =
            "从\(JSON.stringify(simplifiedFormats))中未找到匹配「\(depth)Bit \(rate)kHz」的输出格式"
        Log.notice.notice("格式匹配失败", msg)
        Log.backend.info(
            msg
        )
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
