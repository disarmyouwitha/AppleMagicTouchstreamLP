import Foundation

private func rawHex(_ value: UInt32, width: Int) -> String {
    let text = String(value, radix: 16, uppercase: true)
    if text.count >= width {
        return text
    }
    return String(repeating: "0", count: width - text.count) + text
}

private func rawHexString(_ bytes: some Sequence<UInt8>) -> String {
    var output = ""
    output.reserveCapacity(64)
    for byte in bytes {
        output.append(rawHex(UInt32(byte), width: 2))
    }
    return output
}

public struct RawReportSignature: Codable, Sendable {
    public let vendorID: UInt32
    public let productID: UInt32
    public let usagePage: UInt16
    public let usage: UInt16
    public let reportID: UInt8
    public let payloadLength: Int
}

public struct RawSignatureAnalysis: Codable, Sendable {
    public let signature: RawReportSignature
    public let frames: Int
    public let decodedFrames: Int
    public let minContacts: Int
    public let avgContacts: Double
    public let maxContacts: Int
    public let samplesHex: [String]
}

public struct RawCaptureAnalysisResult: Codable, Sendable {
    public let capturePath: String
    public let captureVersion: Int32
    public let tickFrequency: Int64
    public let recordsRead: Int
    public let recordsDecoded: Int
    public let signatures: [RawSignatureAnalysis]

    public func toSummary() -> String {
        var lines: [String] = []
        lines.append("Raw analysis: \(capturePath)")
        lines.append(
            "version=\(captureVersion), tickFrequency=\(tickFrequency), records=\(recordsRead), decoded=\(recordsDecoded), signatures=\(signatures.count)"
        )
        for (index, signature) in signatures.enumerated() {
            lines.append(
                "\(index + 1). vid=0x\(rawHex(signature.signature.vendorID, width: 4)), pid=0x\(rawHex(signature.signature.productID, width: 4)), usage=0x\(rawHex(UInt32(signature.signature.usagePage), width: 2))/0x\(rawHex(UInt32(signature.signature.usage), width: 2)), reportId=0x\(rawHex(UInt32(signature.signature.reportID), width: 2)), len=\(signature.signature.payloadLength), frames=\(signature.frames)"
            )
            if signature.decodedFrames > 0 {
                lines.append(
                    String(
                        format: "   decoded=%d contacts[min/avg/max]=%d/%.2f/%d",
                        signature.decodedFrames,
                        signature.minContacts,
                        signature.avgContacts,
                        signature.maxContacts
                    )
                )
            }
            for (sampleIndex, sampleHex) in signature.samplesHex.enumerated() {
                lines.append("   sample\(sampleIndex + 1): \(sampleHex)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public func writeJSON(to path: String) throws {
        let outputURL = URL(fileURLWithPath: path).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.prettyPrinted]
        }
        let data = try encoder.encode(self)
        try data.write(to: outputURL, options: .atomic)
    }
}

public enum RawCaptureAnalyzer {
    public static func analyze(
        capturePath: String,
        contactsCSVPath: String? = nil
    ) throws -> RawCaptureAnalysisResult {
        let inputURL = URL(fileURLWithPath: capturePath).standardizedFileURL
        let container = try ATPCaptureCodec.loadContainer(from: inputURL)

        struct Key: Hashable {
            let vendorID: UInt32
            let productID: UInt32
            let usagePage: UInt16
            let usage: UInt16
            let reportID: UInt8
            let payloadLength: Int
        }

        final class MutableSignatureStats {
            var frames = 0
            var decodedFrames = 0
            var totalContacts = 0
            var minContacts = Int.max
            var maxContacts = 0
            var samplesHex: [String] = []

            func add(payload: Data, decodedContactCount: Int?) {
                frames += 1
                if samplesHex.count < 3 {
                    samplesHex.append(rawHexString(payload.prefix(96)))
                }
                guard let decodedContactCount else {
                    return
                }
                decodedFrames += 1
                totalContacts += decodedContactCount
                if decodedContactCount < minContacts {
                    minContacts = decodedContactCount
                }
                if decodedContactCount > maxContacts {
                    maxContacts = decodedContactCount
                }
            }
        }

        var signatures: [Key: MutableSignatureStats] = [:]
        signatures.reserveCapacity(16)
        var recordsDecoded = 0

        for record in container.records {
            if record.deviceIndex == -1 {
                continue
            }

            let reportID = record.payload.first ?? 0
            let key = Key(
                vendorID: record.vendorID,
                productID: record.productID,
                usagePage: record.usagePage,
                usage: record.usage,
                reportID: reportID,
                payloadLength: record.payloadLength
            )
            let stats = signatures[key] ?? MutableSignatureStats()
            signatures[key] = stats

            let decodedContactCount = tryDecodeV3ContactCount(record.payload)
            if decodedContactCount != nil {
                recordsDecoded += 1
            }
            stats.add(payload: record.payload, decodedContactCount: decodedContactCount)
        }

        if let contactsCSVPath {
            try writeRecordCSV(records: container.records, outputPath: contactsCSVPath)
        }

        let analyzedSignatures = signatures
            .map { key, stats in
                RawSignatureAnalysis(
                    signature: RawReportSignature(
                        vendorID: key.vendorID,
                        productID: key.productID,
                        usagePage: key.usagePage,
                        usage: key.usage,
                        reportID: key.reportID,
                        payloadLength: key.payloadLength
                    ),
                    frames: stats.frames,
                    decodedFrames: stats.decodedFrames,
                    minContacts: stats.minContacts == Int.max ? 0 : stats.minContacts,
                    avgContacts: stats.decodedFrames == 0
                        ? 0
                        : Double(stats.totalContacts) / Double(stats.decodedFrames),
                    maxContacts: stats.maxContacts,
                    samplesHex: stats.samplesHex
                )
            }
            .sorted {
                if $0.frames != $1.frames {
                    return $0.frames > $1.frames
                }
                if $0.signature.payloadLength != $1.signature.payloadLength {
                    return $0.signature.payloadLength < $1.signature.payloadLength
                }
                if $0.signature.reportID != $1.signature.reportID {
                    return $0.signature.reportID < $1.signature.reportID
                }
                return $0.signature.vendorID < $1.signature.vendorID
            }

        return RawCaptureAnalysisResult(
            capturePath: inputURL.path,
            captureVersion: container.header.version,
            tickFrequency: container.header.tickFrequency,
            recordsRead: container.records.count,
            recordsDecoded: recordsDecoded,
            signatures: analyzedSignatures
        )
    }

    private static func tryDecodeV3ContactCount(_ payload: Data) -> Int? {
        guard payload.count >= 32 else {
            return nil
        }
        let magic = payload.withUnsafeBytes { rawBuffer -> UInt32 in
            let value = rawBuffer.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            return UInt32(littleEndian: value)
        }
        guard magic == 0x33564652 else { // RFV3
            return nil
        }
        let contactCount = payload.withUnsafeBytes { rawBuffer -> Int in
            let value = rawBuffer.loadUnaligned(fromByteOffset: 28, as: UInt16.self)
            return Int(UInt16(littleEndian: value))
        }
        let expectedLength = 32 + (contactCount * 40)
        guard payload.count == expectedLength else {
            return nil
        }
        return contactCount
    }

    private static func writeRecordCSV(records: [ATPCaptureRecord], outputPath: String) throws {
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var lines: [String] = []
        lines.reserveCapacity(records.count + 1)
        lines.append(
            "frame_index,arrival_ticks,device_index,device_hash,vendor_id,product_id,usage_page,usage,side_hint,decoder_profile,report_id,payload_length,payload_hex"
        )
        for (index, record) in records.enumerated() {
            let reportID = record.payload.first ?? 0
            let row = [
                String(index),
                String(record.arrivalTicks),
                String(record.deviceIndex),
                String(record.deviceHash),
                String(record.vendorID),
                String(record.productID),
                String(record.usagePage),
                String(record.usage),
                String(record.sideHint),
                String(record.decoderProfile),
                String(reportID),
                String(record.payloadLength),
                rawHexString(record.payload)
            ].joined(separator: ",")
            lines.append(row)
        }
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: outputURL, atomically: true, encoding: .utf8)
    }

}
