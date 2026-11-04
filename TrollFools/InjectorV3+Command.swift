//
//  InjectorV3+Command.swift
//  TrollFools
//
//  Created by 82Flex on 2025/1/9.
//

import Foundation
import MachOKit

extension InjectorV3 {
    // MARK: - chown

    fileprivate static let chownBinaryURL = findExecutable("chown")

    func cmdChangeOwner(_ target: URL, owner: uid_t, groupOwner: uid_t? = nil, recursively: Bool = false) throws {
        if isPrivileged {
            try rootChangeOwner(target, owner: owner, groupOwner: groupOwner, recursively: recursively)
            return
        }
        var args = [String]()
        if recursively {
            args.append("-R")
        }
        if let groupOwner {
            args.append(String(format: "%d:%d", owner, groupOwner))
        } else {
            args.append(String(format: "%d", owner))
        }
        args.append(target.path)
        let retCode = try Execute.rootSpawn(binary: Self.chownBinaryURL.path, arguments: args, ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("chown", reason: retCode)
        }
    }

    func cmdChangeOwnerToInstalld(_ target: URL, recursively: Bool = false) throws {
        try cmdChangeOwner(target, owner: 33, groupOwner: 33, recursively: recursively)
    }

    private func rootChangeOwner(_ target: URL, owner: uid_t, groupOwner: uid_t? = nil, recursively: Bool = false) throws {
        let attrs: [FileAttributeKey: Any] = [
            .ownerAccountID: NSNumber(value: owner),
            .groupOwnerAccountID: NSNumber(value: groupOwner ?? owner),
        ]
        if !recursively {
            try FileManager.default.setAttributes(attrs, ofItemAtPath: target.path)
            return
        }
        if let enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                try FileManager.default.setAttributes(attrs, ofItemAtPath: fileURL.path)
            }
        }
    }

    // MARK: - cp

    fileprivate static let cpBinaryURL: URL = {
        if #available(iOS 16, *) {
            findExecutable("cp")
        } else {
            findExecutable("cp-15")
        }
    }()

    func cmdCopy(from srcURL: URL, to destURL: URL, clone: Bool = false, overwrite: Bool = false) throws {
        if isPrivileged {
            try rootCopy(from: srcURL, to: destURL, overwrite: overwrite)
            return
        }
        if overwrite {
            try? cmdRemove(destURL, recursively: true)
        }
        var args = [String]()
        if clone {
            args.append("--reflink=auto")
        }
        args += ["-rfp", srcURL.path, destURL.path]
        let retCode = try Execute.rootSpawn(binary: Self.cpBinaryURL.path, arguments: args, ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("cp", reason: retCode)
        }
    }

    private func rootCopy(from srcURL: URL, to destURL: URL, overwrite: Bool = false) throws {
        if overwrite {
            try? rootRemove(destURL, recursively: true)
        }
        try FileManager.default.copyItem(at: srcURL, to: destURL)
    }

    // MARK: - ldid

    fileprivate static let ldidBinaryURL: URL = findExecutable("ldid")

    func cmdPseudoSign(_ target: URL, force: Bool = false) throws {
        var hasCodeSign = false
        var preservesEntitlements = false

        let targetFile = try MachOKit.loadFromFile(url: target)
        switch targetFile {
        case let .machO(machOFile):
            preservesEntitlements = machOFile.header.fileType == .execute
            for command in machOFile.loadCommands {
                switch command {
                case .codeSignature:
                    hasCodeSign = true
                    break
                default:
                    continue
                }
            }
        case let .fat(fatFile):
            let machOFiles = try fatFile.machOFiles()
            for machOFile in machOFiles {
                preservesEntitlements = machOFile.header.fileType == .execute
                for command in machOFile.loadCommands {
                    switch command {
                    case .codeSignature:
                        hasCodeSign = true
                        break
                    default:
                        continue
                    }
                }
            }
        }

        guard force || !hasCodeSign else {
            return
        }

        if preservesEntitlements {
            var receipt: AuxiliaryExecute.ExecuteReceipt

            receipt = try Execute.rootSpawnWithOutputs(binary: Self.ldidBinaryURL.path, arguments: [
                "-e", target.path,
            ], ddlog: logger)

            guard case let .exit(code) = receipt.terminationReason, code == EXIT_SUCCESS else {
                try throwCommandFailure("ldid", reason: receipt.terminationReason)
            }

            let xmlContent = receipt.stdout
            let xmlURL = temporaryDirectoryURL
                .appendingPathComponent("\(UUID().uuidString)_\(target.lastPathComponent)")
                .appendingPathExtension("xml")

            try xmlContent.write(to: xmlURL, atomically: true, encoding: .utf8)

            receipt = try Execute.rootSpawnWithOutputs(binary: Self.ldidBinaryURL.path, arguments: [
                "-S\(xmlURL.path)", target.path,
            ], ddlog: logger)

            guard case let .exit(code) = receipt.terminationReason, code == EXIT_SUCCESS else {
                try throwCommandFailure("ldid", reason: receipt.terminationReason)
            }
        } else {
            let retCode = try Execute.rootSpawn(binary: Self.ldidBinaryURL.path, arguments: [
                "-S", target.path,
            ], ddlog: logger)

            guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
                try throwCommandFailure("ldid", reason: retCode)
            }
        }
    }

    // MARK: - mkdir

    fileprivate static let mkdirBinaryURL = findExecutable("mkdir")

    func cmdMakeDirectory(at target: URL, withIntermediateDirectories: Bool = false) throws {
        if isPrivileged {
            try rootMakeDirectory(at: target, withIntermediateDirectories: withIntermediateDirectories)
            return
        }
        var args = [String]()
        if withIntermediateDirectories {
            args.append("-p")
        }
        args.append(target.path)
        let retCode = try Execute.rootSpawn(binary: Self.mkdirBinaryURL.path, arguments: args, ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("mkdir", reason: retCode)
        }
    }

    private func rootMakeDirectory(at target: URL, withIntermediateDirectories: Bool = false) throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: withIntermediateDirectories)
    }

    // MARK: - mv

    fileprivate static let mvBinaryURL: URL = {
        if #available(iOS 16, *) {
            findExecutable("mv")
        } else {
            findExecutable("mv-15")
        }
    }()

    func cmdMove(from srcURL: URL, to destURL: URL, overwrite: Bool = false) throws {
        if isPrivileged {
            try rootMove(from: srcURL, to: destURL, overwrite: overwrite)
            return
        }
        if overwrite {
            try? cmdRemove(destURL, recursively: true)
        }
        var args = [String]()
        if overwrite {
            args.append("-f")
        }
        args += [srcURL.path, destURL.path]
        let retCode = try Execute.rootSpawn(binary: Self.mvBinaryURL.path, arguments: args, ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("mv", reason: retCode)
        }
    }

    private func rootMove(from srcURL: URL, to destURL: URL, overwrite: Bool = false) throws {
        if overwrite {
            try? rootRemove(destURL, recursively: true)
        }
        try FileManager.default.moveItem(at: srcURL, to: destURL)
    }

    // MARK: - rm

    fileprivate static let rmBinaryURL = findExecutable("rm")

    func cmdRemove(_ target: URL, recursively: Bool = false) throws {
        if isPrivileged {
            try rootRemove(target, recursively: recursively)
            return
        }
        let retCode = try Execute.rootSpawn(binary: Self.rmBinaryURL.path, arguments: [
            recursively ? "-rf" : "-f", target.path,
        ], ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("rm", reason: retCode)
        }
    }

    private func rootRemove(_ target: URL, recursively: Bool = false) throws {
        if !recursively {
            let retCode = target.withUnsafeFileSystemRepresentation { unlink($0) }
            guard retCode == 0 else {
                throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EPERM)
            }
            return
        }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: - ct_bypass

    fileprivate static let ctBypassBinaryURL = findExecutable("ct_bypass")

    func cmdCoreTrustBypass(_ target: URL, teamID: String) throws {
        // `ct_bypass` (ChOma) recomputes the code-directory page hashes over
        // `codeLimit` bytes before it swaps in the App Store signature. A
        // payload that still carries a *foreign* signature — e.g. a shipping
        // App Store dylib whose `codeLimit` describes a larger build than the
        // file on disk — makes it read past EOF and die with an uncaught
        // SIGSEGV (signal 11) a few milliseconds after spawn.
        //
        // Re-signing with `ldid` first always yields a self-consistent
        // signature (`codeLimit` == signature offset), which is exactly the
        // "fake-signed at minimum" input the bypass expects.
        if let reason = Self.whyCodeSignatureIsUnusable(at: target) {
            DDLogWarn("Refreshing code signature of \(target.lastPathComponent) before ct_bypass: \(reason)", ddlog: logger)
            try cmdPseudoSign(target, force: true)
        } else {
            try cmdPseudoSign(target)
        }

        let receipt = try Execute.rootSpawnWithOutputs(binary: Self.ctBypassBinaryURL.path, arguments: [
            "-r", "-i", target.path, "-t", teamID,
        ], ddlog: logger)

        let output = [receipt.stdout, receipt.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        switch receipt.terminationReason {
        case let .exit(code):
            guard code == EXIT_SUCCESS else {
                if !output.isEmpty {
                    DDLogError("ct_bypass output for \(target.lastPathComponent): \(output)", ddlog: logger)
                }
                throw Error.generic(String(
                    format: NSLocalizedString("%@ exited with code %d", comment: ""),
                    "ct_bypass", code
                ))
            }
        case let .uncaughtSignal(signal):
            if !output.isEmpty {
                DDLogError("ct_bypass output for \(target.lastPathComponent): \(output)", ddlog: logger)
            }
            let base = String(
                format: NSLocalizedString("%@ terminated with signal %d", comment: ""),
                "ct_bypass", signal
            )
            throw Error.generic(output.isEmpty ? base : "\(base): \(output)")
        }

        if !output.isEmpty {
            DDLogInfo("ct_bypass output for \(target.lastPathComponent): \(output)", ddlog: logger)
        }
    }

    /// Returns a human readable reason when the Mach-O's embedded signature
    /// cannot be trusted as input for `ct_bypass`, or `nil` when it looks sound.
    ///
    /// Anything that cannot be parsed confidently is considered unusable: the
    /// caller then re-signs from scratch, which is always safe.
    private static func whyCodeSignatureIsUnusable(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "file is not readable"
        }
        defer {
            try? handle.close()
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0

        guard let header = Self.readData(handle, at: 0, count: 32, fileSize: fileSize) else {
            return "truncated Mach-O header"
        }

        let is64: Bool
        switch Self.readU32(header, 0, bigEndian: false) ?? 0 {
        case 0xFEED_FACF:
            is64 = true
        case 0xFEED_FACE:
            is64 = false
        default:
            // Fat archives and unknown payloads: let ldid deal with them.
            return "unsupported Mach-O magic"
        }

        let headerSize = is64 ? 32 : 28
        guard let ncmds = Self.readU32(header, 16, bigEndian: false),
              let sizeofcmds = Self.readU32(header, 20, bigEndian: false),
              ncmds > 0, ncmds < 0x1_0000, sizeofcmds < 0x10_0000
        else {
            return "malformed Mach-O header"
        }

        guard let commands = Self.readData(
            handle,
            at: UInt64(headerSize),
            count: Int(sizeofcmds),
            fileSize: fileSize
        ) else {
            return "truncated load commands"
        }

        var signatureOffset: UInt32?
        var signatureSize: UInt32?
        var cursor = 0
        for _ in 0 ..< Int(ncmds) {
            guard let cmd = Self.readU32(commands, cursor, bigEndian: false),
                  let cmdSize = Self.readU32(commands, cursor + 4, bigEndian: false),
                  cmdSize >= 8,
                  cursor + Int(cmdSize) <= commands.count
            else {
                return "malformed load command table"
            }
            if cmd == 0x1D { // LC_CODE_SIGNATURE
                guard let offset = Self.readU32(commands, cursor + 8, bigEndian: false),
                      let size = Self.readU32(commands, cursor + 12, bigEndian: false)
                else {
                    return "truncated LC_CODE_SIGNATURE"
                }
                signatureOffset = offset
                signatureSize = size
                break
            }
            cursor += Int(cmdSize)
        }

        guard let signatureOffset, let signatureSize, signatureSize > 0 else {
            return "no embedded code signature"
        }
        guard UInt64(signatureOffset) + UInt64(signatureSize) <= fileSize else {
            return "LC_CODE_SIGNATURE extends past end of file"
        }

        guard let superblob = Self.readData(
            handle,
            at: UInt64(signatureOffset),
            count: min(Int(signatureSize), 4096),
            fileSize: fileSize
        ) else {
            return "unreadable signature superblob"
        }

        let superblobMagic = Self.readU32(superblob, 0, bigEndian: true) ?? 0
        guard superblobMagic == 0xFADE_0CC0 || superblobMagic == 0xFADE_0CC1 else {
            return String(format: "unexpected signature magic 0x%08x", superblobMagic)
        }
        guard let count = Self.readU32(superblob, 8, bigEndian: true), count > 0, count <= 64 else {
            return "invalid signature blob count"
        }

        var codeDirectoryOffset: UInt32?
        for index in 0 ..< Int(count) {
            let entry = 12 + index * 8
            guard let type = Self.readU32(superblob, entry, bigEndian: true),
                  let offset = Self.readU32(superblob, entry + 4, bigEndian: true)
            else {
                return "truncated signature index"
            }
            if type == 0 { // CSSLOT_CODEDIRECTORY
                codeDirectoryOffset = offset
                break
            }
        }

        guard let codeDirectoryOffset else {
            return "no code directory blob"
        }

        guard let codeDirectory = Self.readData(
            handle,
            at: UInt64(signatureOffset) + UInt64(codeDirectoryOffset),
            count: 48,
            fileSize: fileSize
        ) else {
            return "unreadable code directory"
        }

        let codeDirectoryMagic = Self.readU32(codeDirectory, 0, bigEndian: true) ?? 0
        guard codeDirectoryMagic == 0xFADE_0C02 else {
            return String(format: "unexpected code directory magic 0x%08x", codeDirectoryMagic)
        }

        // struct CS_CodeDirectory puts `codeLimit` right after `nCodeSlots`.
        guard let codeLimit = Self.readU32(codeDirectory, 32, bigEndian: true) else {
            return "truncated code directory"
        }

        if UInt64(codeLimit) > UInt64(signatureOffset) {
            return "code directory limit \(codeLimit) exceeds signature offset \(signatureOffset) (stale signature)"
        }
        if UInt64(codeLimit) > fileSize {
            return "code directory limit \(codeLimit) exceeds file size \(fileSize)"
        }

        return nil
    }

    private static func readData(
        _ handle: FileHandle,
        at offset: UInt64,
        count: Int,
        fileSize: UInt64
    ) -> Data? {
        guard count > 0, offset + UInt64(count) <= fileSize else {
            return nil
        }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: count) ?? Data()
            return data.count == count ? data : nil
        } catch {
            return nil
        }
    }

    private static func readU32(_ data: Data, _ offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else {
            return nil
        }
        let bytes = [UInt8](data[offset ..< offset + 4])
        return bigEndian
            ? (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            : (UInt32(bytes[3]) << 24) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[1]) << 8) | UInt32(bytes[0])
    }

    // MARK: - insert_dylib

    fileprivate static let insertDylibBinaryURL = findExecutable("insert_dylib")

    func cmdInsertLoadCommandDylib(_ target: URL, name: String, weak: Bool = false) throws {
        let dylibs = try loadedDylibsOfMachO(target)
        if dylibs.contains(name) {
            return
        }
        var args = [
            name, target.path,
            "--inplace", "--overwrite", "--no-strip-codesig", "--all-yes",
        ]
        if weak {
            args.append("--weak")
        }
        let retCode = try Execute.rootSpawn(binary: Self.insertDylibBinaryURL.path, arguments: args, ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("insert_dylib", reason: retCode)
        }
    }

    // MARK: - install_name_tool

    fileprivate static let installNameToolBinaryURL = findExecutable("install_name_tool")

    func cmdInsertLoadCommandRuntimePath(_ target: URL, name: String) throws {
        let rpaths = try runtimePathsOfMachO(target)
        if rpaths.contains(name) {
            return
        }
        try cmdPseudoSign(target, force: true)
        let retCode = try Execute.rootSpawn(binary: Self.installNameToolBinaryURL.path, arguments: [
            "-add_rpath", name, target.path,
        ], ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("install_name_tool", reason: retCode)
        }
    }

    func cmdChangeLoadCommandDylib(_ target: URL, from srcName: String, to destName: String) throws {
        try cmdPseudoSign(target, force: true)
        let retCode = try Execute.rootSpawn(binary: Self.installNameToolBinaryURL.path, arguments: [
            "-change", srcName, destName, target.path,
        ], ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("install-name-tool", reason: retCode)
        }
    }

    // MARK: - optool

    fileprivate static let optoolBinaryURL = findExecutable("optool")

    func cmdRemoveLoadCommandDylib(_ target: URL, name: String) throws {
        let dylibs = try loadedDylibsOfMachO(target)
        guard dylibs.contains(name) else {
            return
        }
        let retCode = try Execute.rootSpawn(binary: Self.optoolBinaryURL.path, arguments: [
            "uninstall", "-p", name, "-t", target.path,
        ], ddlog: logger)
        guard case let .exit(code) = retCode, code == EXIT_SUCCESS else {
            try throwCommandFailure("optool", reason: retCode)
        }
    }

    // MARK: - Error Handling

    fileprivate func throwCommandFailure(_ command: String, reason: AuxiliaryExecute.TerminationReason) throws -> Never {
        switch reason {
        case let .exit(code):
            throw Error.generic(String(format: NSLocalizedString("%@ exited with code %d", comment: ""), command, code))
        case let .uncaughtSignal(signal):
            throw Error.generic(String(format: NSLocalizedString("%@ terminated with signal %d", comment: ""), command, signal))
        }
    }

    // MARK: - Path Finder

    fileprivate static func findExecutable(_ name: String) -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        if let firstArg = ProcessInfo.processInfo.arguments.first {
            let execURL = URL(fileURLWithPath: firstArg)
                .deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: execURL.path) {
                return execURL
            }
        }
        if let tfProxy = LSApplicationProxy(forIdentifier: Constants.gAppIdentifier),
           let tfBundleURL = tfProxy.bundleURL()
        {
            let execURL = tfBundleURL.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: execURL.path) {
                return execURL
            }
        }
        fatalError("Unable to locate executable \(name)")
    }
}
