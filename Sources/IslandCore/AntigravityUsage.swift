import Foundation

/// Antigravity has no usage API. The app caches its last `GetUserStatus` answer in its own state database
/// (`antigravityAuthStatus` → `userStatusProtoBinaryBase64`): one entry per model with the remaining quota
/// fraction and the time it resets. That cache is read-only and holds no credentials we use.
public enum AntigravityUsageDecoder {
    /// `data` is the JSON stored under `antigravityAuthStatus`.
    public static func decodeAuthStatus(_ data: Data, fetchedAt: Date, now: Date = Date()) throws -> UsageSnapshot {
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64 = row["userStatusProtoBinaryBase64"] as? String,
              let proto = Data(base64Encoded: base64)
        else { throw AIUsageDecoder.Failure() }
        return try decodeUserStatus(proto, fetchedAt: fetchedAt, now: now)
    }

    public static func decodeUserStatus(_ proto: Data, fetchedAt: Date, now: Date = Date()) throws -> UsageSnapshot {
        var windows: [UsageWindow] = []
        for field in fields(proto) where field.number == 33 {
            guard case .bytes(let configs) = field.value else { continue }
            for model in fields(configs) where model.number == 1 {
                guard case .bytes(let body) = model.value, let window = window(body, now: now) else { continue }
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { throw AIUsageDecoder.Failure() }
        return UsageSnapshot(fetchedAt: fetchedAt, windows: windows, creditRemaining: nil, creditUnit: nil)
    }

    private static func window(_ model: Data, now: Date) -> UsageWindow? {
        var name: String?
        var quota: Data?
        for field in fields(model) {
            switch (field.number, field.value) {
            case (1, .bytes(let bytes)): name = String(data: bytes, encoding: .utf8)
            case (15, .bytes(let bytes)): quota = bytes
            default: break
            }
        }
        guard let name, !name.isEmpty, let quota else { return nil }
        var remaining: Double?
        var reset: Date?
        for field in fields(quota) {
            switch (field.number, field.value) {
            case (1, .fixed32(let bits)): remaining = Double(Float(bitPattern: bits))
            case (2, .bytes(let bytes)):
                for inner in fields(bytes) where inner.number == 1 {
                    if case .varint(let seconds) = inner.value { reset = Date(timeIntervalSince1970: Double(seconds)) }
                }
            default: break
            }
        }
        guard let remaining, remaining.isFinite, (0...1).contains(remaining) else { return nil }
        // A reset time in the past means the cached fraction is from before the quota refilled.
        if let reset, reset <= now { return UsageWindow(id: name, usedPercent: 0, resetsAt: nil) }
        return UsageWindow(id: name, usedPercent: (1 - remaining) * 100, resetsAt: reset)
    }

    // MARK: Minimal protobuf wire-format reader

    private enum Value {
        case varint(UInt64)
        case fixed32(UInt32)
        case bytes(Data)
    }

    private struct Field {
        let number: Int
        let value: Value
    }

    private static func fields(_ data: Data) -> [Field] {
        let bytes = [UInt8](data)
        var index = 0
        var result: [Field] = []
        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count, shift < 64 {
                let byte = bytes[index]
                index += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while index < bytes.count {
            guard let key = varint() else { break }
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = varint() else { return result }
                result.append(Field(number: number, value: .varint(value)))
            case 1:
                guard index + 8 <= bytes.count else { return result }
                index += 8
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - index) else { return result }
                let end = index + Int(length)
                result.append(Field(number: number, value: .bytes(Data(bytes[index..<end]))))
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return result }
                let bits = UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
                index += 4
                result.append(Field(number: number, value: .fixed32(bits)))
            default:
                return result
            }
        }
        return result
    }
}
