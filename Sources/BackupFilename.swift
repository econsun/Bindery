import Foundation

/// Controls how dates and times are rendered into snapshot names.
/// The defaults keep the compact `yyMMdd` form used by the existing archive names.
struct FilenameStyle: Equatable {
    var dateFormat: String
    var projectDateFormat: String
    var timeFormat: String

    static let standard = FilenameStyle(
        dateFormat: "yyMMdd",
        projectDateFormat: "yyMMdd",
        timeFormat: "HHmmss"
    )
}

struct RenderedFilename: Equatable {
    let name: String
    let identifier: String
    let projectDateText: String?
    let backupDateText: String
}

enum BackupFilenameFormat {
    /// `{bindname}` is the binding's label. `{projectDate}` is optional: the
    /// bracketed group (including its separator) disappears when no project
    /// date can be parsed. `{backupDate}{XX}` is the permanent identity.
    static let defaultFormat = "{bindname}[_{projectDate}]_{backupDate}{XX}"

    static let legacyDefaults: Set<String> = [
        "bk_{category}_{name}_{yymmdd}_{XXXX}",
        "bk_{category}_{name}_{yymmdd}{XXXX}",
        "bk{category}_{name}_{yymmdd}{XXXX}",
        "bk_{category}_{name}_{year}-{month}-{day}_{XXXX}",
        "bk_{category}_{name}_{year}-{month}-{day}_{random}",
        "bk_{category}_{name}_{yymmdd}_{random}"
    ]

    static let variables: [(token: String, description: String)] = [
        ("{bindname}", "Binding name; falls back to the source name"),
        ("{projectDate}", "Project date parsed from the beginning of the source name"),
        ("{backupDate}", "Date this snapshot is created"),
        ("{backupTime}", "Time this snapshot is created"),
        ("{XX}", "Two random uppercase letters; part of the permanent ID"),
        ("{id}", "Permanent ID: backup date + two letters"),
        ("{category}", "Last component of the category path"),
        ("{name}", "Source name at capture time (without extension)"),
        ("{ext}", "Source file extension, without the dot"),
        ("{year} {month} {day} {hour} {minute} {second}", "Legacy date/time aliases"),
        ("{random}", "Legacy alias for four random letters")
    ]

    static let helpText = """
    Filename variables

    {bindname}    binding name (falls back to source name)
    {projectDate} project date parsed from the source name
    {backupDate}  date of this backup
    {backupTime}  time of this backup
    {XX}          two random uppercase letters
    {id}          permanent ID = backup date + {XX}
    {category}    last component of the category path
    {name}        source name at capture
    {ext}         source extension, without dot

    Optional groups
    [_{projectDate}] disappears entirely when there is no project date,
    so no doubled underscore is left behind.

    Date and time variables use the formats set in Settings > General.
    """

    // MARK: - Normalisation

    static func normalize(_ format: String?) -> String {
        let trimmed = (format ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || legacyDefaults.contains(trimmed) {
            return defaultFormat
        }
        return trimmed
    }

    // MARK: - Rendering

    static func render(
        _ rawFormat: String,
        bindingName: String,
        category: String,
        sourceName: String,
        sourceExtension: String,
        projectDate: Date?,
        backupDate: Date,
        style: FilenameStyle = .standard,
        randomLetters: String? = nil,
        identifierOverride: String? = nil
    ) -> RenderedFilename {
        var format = normalize(rawFormat)
        let override = identifierOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let letters = override.flatMap { normalizedLetters(String($0.suffix(2))) }
            ?? normalizedLetters(randomLetters)
            ?? Self.randomLetters(count: 2)
        let backupDateText = dateText(backupDate, pattern: style.dateFormat, fallback: "yyMMdd")
        let projectDateText = projectDate.map {
            dateText($0, pattern: style.projectDateFormat, fallback: "yyMMdd")
        }
        let identifier = override.flatMap { $0.isEmpty ? nil : $0 } ?? (backupDateText + letters)

        let safeBindingName = sanitize(bindingName)
        let resolvedBindingName = safeBindingName.isEmpty ? sanitize(URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent) : safeBindingName
        let safeSourceName = sanitize(URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent)
        let safeCategory = category.split(separator: "/").last.map(String.init) ?? category
        let ext = sourceExtension.hasPrefix(".") ? String(sourceExtension.dropFirst()) : sourceExtension

        var values: [(String, String)] = [
            ("bindname", resolvedBindingName),
            ("projectDate", projectDateText ?? ""),
            ("backupDate", backupDateText),
            ("backupTime", dateText(backupDate, pattern: style.timeFormat, fallback: "HHmmss")),
            ("id", identifier),
            ("XX", letters),
            ("category", sanitize(safeCategory)),
            ("name", safeSourceName),
            ("ext", ext),
            // Legacy aliases. `{random}` is kept at four letters so old custom
            // formats keep their shape; new formats should use `{XX}`.
            ("random", normalizedLetters(nil) ?? Self.randomLetters(count: 4)),
            ("yymmdd", backupDateText),
            ("year", dateText(backupDate, pattern: "yyyy", fallback: "yyyy")),
            ("month", dateText(backupDate, pattern: "MM", fallback: "MM")),
            ("day", dateText(backupDate, pattern: "dd", fallback: "dd")),
            ("hour", dateText(backupDate, pattern: "HH", fallback: "HH")),
            ("minute", dateText(backupDate, pattern: "mm", fallback: "mm")),
            ("second", dateText(backupDate, pattern: "ss", fallback: "ss"))
        ]

        // Keep the permanent identifier even if an old or hand-written format
        // does not mention `{XX}` or `{id}`.
        if !format.localizedCaseInsensitiveContains("{XX}") && !format.localizedCaseInsensitiveContains("{id}") {
            format += "_{id}"
            values.append(("id", identifier))
        }

        let expanded = expandOptionalGroups(format) { inner in
            var value = inner
            for (key, replacement) in values {
                value = value.replacingOccurrences(of: "{\(key)}", with: replacement, options: [.caseInsensitive])
            }
            return value
        }

        var result = expanded
        for (key, replacement) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: replacement, options: [.caseInsensitive])
        }
        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")
        result = cleanup(result)

        if result.isEmpty {
            result = "Snapshot_\(identifier)"
        }
        result = clipped(result, identifier: identifier)
        return RenderedFilename(
            name: result,
            identifier: identifier,
            projectDateText: projectDateText,
            backupDateText: backupDateText
        )
    }

    /// Compatibility entry point for code that used the old binding-based API.
    static func render(
        _ format: String,
        binding: BackupBinding,
        date: Date,
        randomLetters: String? = nil
    ) -> String {
        render(
            format,
            bindingName: binding.name,
            category: binding.category,
            sourceName: binding.sourcePath.isEmpty ? binding.name : URL(fileURLWithPath: binding.sourcePath).lastPathComponent,
            sourceExtension: URL(fileURLWithPath: binding.sourcePath).pathExtension,
            projectDate: binding.projectDate,
            backupDate: date,
            style: .standard,
            randomLetters: randomLetters
        ).name
    }

    static func example(for binding: BackupBinding, style: FilenameStyle = .standard) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let backup = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 16, minute: 2)) ?? Date()
        let sourceName = binding.sourcePath.isEmpty ? binding.name : URL(fileURLWithPath: binding.sourcePath).lastPathComponent
        let projectDate = binding.projectDate ?? parseProjectDate(from: sourceName)
        return render(
            binding.filenameFormat,
            bindingName: binding.name.isEmpty ? "Project" : binding.name,
            category: binding.category,
            sourceName: sourceName,
            sourceExtension: URL(fileURLWithPath: binding.sourcePath).pathExtension,
            projectDate: projectDate,
            backupDate: backup,
            style: style,
            randomLetters: "AB"
        ).name
    }

    static func example(for binding: BackupBinding, style: FilenameStyle = .standard, projectDate: Date?) -> String {
        let backup = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 7, day: 23, hour: 16, minute: 2)
        ) ?? Date()
        return render(
            binding.filenameFormat,
            bindingName: binding.name.isEmpty ? "Project" : binding.name,
            category: binding.category,
            sourceName: binding.sourcePath.isEmpty ? binding.name : URL(fileURLWithPath: binding.sourcePath).lastPathComponent,
            sourceExtension: URL(fileURLWithPath: binding.sourcePath).pathExtension,
            projectDate: projectDate,
            backupDate: backup,
            style: style,
            randomLetters: "AB"
        ).name
    }

    // MARK: - Project date parsing

    /// Parses a project date from the very beginning of a file or folder name.
    /// Accepted forms: `260312`, `26 03 12`, `26-03-12`, `26_03_12`, `26.03.12`.
    static func parseProjectDate(from name: String) -> Date? {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return nil }

        let patterns = [
            #"^(\d{2})\s+(\d{2})\s+(\d{2})(?=\D|$)"#,
            #"^(\d{2})[\-_.](\d{2})[\-_.](\d{2})(?=\D|$)"#,
            #"^(\d{2})(\d{2})(\d{2})(?=\D|$)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..<stem.endIndex, in: stem)),
                  match.numberOfRanges == 4 else { continue }
            let values = (1...3).compactMap { index -> Int? in
                guard let range = Range(match.range(at: index), in: stem) else { return nil }
                return Int(stem[range])
            }
            guard values.count == 3 else { continue }
            if let date = makeDate(year: values[0], month: values[1], day: values[2]) {
                return date
            }
        }
        return nil
    }

    /// Older Backup Harbor archives could carry a descriptive title *after*
    /// the date and UID, e.g. `bkMedia_Project_260823BTTG_Title.zip`.
    /// In that shape the embedded date describes the content (for example a
    /// publication date), not the moment the archive was made.
    /// Imported records used to read that date as `capturedAt`; this helper
    /// lets the scanner move it to `projectDate` and recover the real backup
    /// time from the file itself.
    static func legacySourceProjectDate(fromSourcePath path: String) -> Date? {
        guard !path.isEmpty else { return nil }
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard stem.lowercased().hasPrefix("bk") else { return nil }
        let pattern = #"_(\d{6})(?:[xX])?[A-Za-z]{4}_.+$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..<stem.endIndex, in: stem)),
              let dateRange = Range(match.range(at: 1), in: stem) else { return nil }
        return parseCompactDate(String(stem[dateRange]))
    }

    // MARK: - Identifier extraction

    /// Extracts a permanent identifier from a filename. This is a fallback for
    /// catalogs that were lost; the catalog is always authoritative.
    static func extractIdentifier(from filename: String, style: FilenameStyle = .standard) -> String? {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let pattern = #"(\d{6})([A-Z]{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..<stem.endIndex, in: stem)),
              let dateRange = Range(match.range(at: 1), in: stem),
              let lettersRange = Range(match.range(at: 2), in: stem) else { return nil }
        let dateToken = String(stem[dateRange])
        guard parseCompactDate(dateToken) != nil else { return nil }
        return dateToken + String(stem[lettersRange]).uppercased()
    }

    // MARK: - Helpers

    static func dateText(_ date: Date, pattern: String, fallback: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = pattern.isEmpty ? fallback : pattern
        let value = formatter.string(from: date)
        if value.isEmpty {
            formatter.dateFormat = fallback
            return formatter.string(from: date)
        }
        return value
    }

    static func randomLetters(count: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<max(1, count)).map { _ in alphabet.randomElement() ?? "A" })
    }

    static func normalizedLetters(_ value: String?) -> String? {
        guard let value else { return nil }
        let upper = value.uppercased()
        guard upper.count == 2, upper.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return nil }
        return upper
    }

    static func sanitize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        var cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        cleaned = cleaned.components(separatedBy: .controlCharacters).joined()
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        cleaned = cleaned.replacingOccurrences(of: #"_{2,}"#, with: "_", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return cleaned
    }

    /// Keeps names inside the filesystem limit without ever cutting the
    /// permanent identifier off the end.
    private static func clipped(_ value: String, identifier: String) -> String {
        let limit = 220
        guard value.utf8.count > limit else { return value }
        var base = value
        if base.hasSuffix(identifier) {
            base = String(base.dropLast(identifier.count))
        }
        let suffix = "_" + identifier
        let budget = max(24, limit - suffix.utf8.count)
        var prefix = ""
        for character in base {
            let candidate = prefix + String(character)
            if candidate.utf8.count > budget { break }
            prefix = candidate
        }
        prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
        return (prefix.isEmpty ? "Snapshot" : prefix) + suffix
    }

    private static func cleanup(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: #"_{2,}"#, with: "_", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
        return result
    }

    /// Expands `[ ... ]` groups. If the expanded group has no meaningful
    /// characters (only separators), the group is omitted.
    private static func expandOptionalGroups(_ value: String, transform: (String) -> String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "[", let close = value[index...].firstIndex(of: "]") {
                let innerStart = value.index(after: index)
                let inner = String(value[innerStart..<close])
                let expanded = transform(inner)
                if !isEffectivelyEmpty(expanded) {
                    result += expanded
                }
                index = value.index(after: close)
            } else {
                result.append(character)
                index = value.index(after: index)
            }
        }
        return result
    }

    private static func isEffectivelyEmpty(_ value: String) -> Bool {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " _-.")).isEmpty
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var fullYear = 2000 + year
        if let candidate = calendar.date(from: DateComponents(year: fullYear, month: month, day: day, hour: 12)),
           candidate > Date().addingTimeInterval(366 * 24 * 60 * 60),
           year >= 70 {
            fullYear = 1900 + year
        }
        guard let date = calendar.date(from: DateComponents(year: fullYear, month: month, day: day, hour: 12)) else {
            return nil
        }
        // Reject rolled-over dates such as 26-02-31.
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == fullYear, components.month == month, components.day == day else { return nil }
        return date
    }

    private static func parseCompactDate(_ value: String) -> Date? {
        guard value.count == 6,
              let year = Int(value.prefix(2)),
              let month = Int(value.dropFirst(2).prefix(2)),
              let day = Int(value.suffix(2)) else { return nil }
        return makeDate(year: year, month: month, day: day)
    }
}
