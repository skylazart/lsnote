import AppKit

/// NSTextView subclass that adds column-mode editing (Alt+drag, Alt+Shift+↑/↓)
/// and multi-match selection (⌘G next, ⇧⌘G previous, ⇧⌘L all).
///
/// NSTextView has no public multi-cursor API, so `cursors` is the source of
/// truth. Non-empty cursor ranges are rendered through the native discontiguous
/// selection (falling back to temporary attributes when AppKit rejects the
/// range set), and zero-length carets are drawn in `draw(_:)` with a blink
/// timer. All simultaneous edits go through a single
/// `shouldChangeText(in:replacementStrings:)` call so each operation is one
/// undo step.
final class MultiCursorTextView: NSTextView {

    enum MultiCursorMode { case none, column, match }

    private(set) var mode: MultiCursorMode = .none
    /// Sorted, non-overlapping. Length 0 = caret, length > 0 = selection.
    private(set) var cursors: [NSRange] = []

    /// Column mode: when a line is shorter than the target column, place the
    /// cursor at the end of that line instead of skipping the line.
    var insertAtLineEndWhenShort = false
    /// Badge text for the host view ("3 of 7 matches selected", "4 cursors") or nil.
    var onStatusChange: ((String?) -> Void)?

    var isMultiCursorActive: Bool { mode != .none && !cursors.isEmpty }

    // Column-mode anchor (character column, not visual column)
    private var columnAnchorLine = 0
    private var columnExtentLine = 0
    private var columnChar = 0
    private var columnSelectionLength = 0

    // Match-mode state
    private var matchQuery: String?
    private var matchWholeWord = false
    private var matchTotal = 0
    private var lastClickWasDouble = false

    private var isProgrammaticSelection = false
    private var isPerformingMultiEdit = false
    private var blinkTimer: Timer?
    private var caretsVisible = true

    private static let columnBlockType = NSPasteboard.PasteboardType("com.lsnote.column-block")

    deinit {
        blinkTimer?.invalidate()
    }

    // MARK: - Event handling

    override func mouseDown(with event: NSEvent) {
        lastClickWasDouble = event.clickCount == 2
        let mods = event.modifierFlags
        if mods.contains(.option) && !mods.contains(.command) && event.clickCount == 1 && isSelectable {
            trackColumnSelection(startingAt: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags
        if mods.contains(.option) && mods.contains(.shift) && !mods.contains(.command) {
            switch event.keyCode {
            case 126: extendColumnSelection(by: -1); return // up arrow
            case 125: extendColumnSelection(by: 1); return  // down arrow
            default: break
            }
        }
        if event.keyCode == 53, isMultiCursorActive { // escape
            clearMultiCursors()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.type == .keyDown {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "g", mods == .command, addNextMatch(forward: true) { return true }
            if key == "g", mods == [.command, .shift], addNextMatch(forward: false) { return true }
            if key == "l", mods == [.command, .shift], selectAllMatches() { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if isMultiCursorActive {
            clearMultiCursors()
            return
        }
        // Preserve NSTextView's default Escape behavior (completion).
        complete(sender)
    }

    // Any selection change not initiated by this class (click, arrow keys,
    // select-all, undo) exits multi-cursor mode.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        let userDriven = !isProgrammaticSelection && !isPerformingMultiEdit && isMultiCursorActive
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if userDriven {
            clearMultiCursors(keepCaret: false)
        }
    }

    // Text changed by something other than our multi-edit path (toolbar
    // formatting, undo, programmatic replacement) → cursors are stale.
    override func didChangeText() {
        super.didChangeText()
        if !isPerformingMultiEdit && isMultiCursorActive {
            clearMultiCursors(keepCaret: false)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            blinkTimer?.invalidate()
            blinkTimer = nil
        }
    }

    // MARK: - Editing operations

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard isMultiCursorActive else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        // Marked-text input (IME / dead keys) is not multi-cursor aware.
        guard replacementRange.location == NSNotFound else {
            clearMultiCursors()
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        guard !s.isEmpty else { return }
        multiEdit(ranges: cursors, strings: cursors.map { _ in s })
    }

    override func insertNewline(_ sender: Any?) {
        if isMultiCursorActive {
            multiEdit(ranges: cursors, strings: cursors.map { _ in "\n" })
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if isMultiCursorActive {
            multiEdit(ranges: cursors, strings: cursors.map { _ in "\t" })
        } else {
            super.insertTab(sender)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        guard isMultiCursorActive else {
            super.deleteBackward(sender)
            return
        }
        var ranges: [NSRange] = []
        for c in cursors {
            if c.length > 0 {
                ranges.append(c)
            } else if c.location > 0 {
                ranges.append(NSRange(location: c.location - 1, length: 1))
            }
        }
        guard !ranges.isEmpty else { NSSound.beep(); return }
        let merged = normalize(ranges)
        multiEdit(ranges: merged, strings: Array(repeating: "", count: merged.count))
    }

    override func deleteForward(_ sender: Any?) {
        guard isMultiCursorActive else {
            super.deleteForward(sender)
            return
        }
        let length = (string as NSString).length
        var ranges: [NSRange] = []
        for c in cursors {
            if c.length > 0 {
                ranges.append(c)
            } else if c.location < length {
                ranges.append(NSRange(location: c.location, length: 1))
            }
        }
        guard !ranges.isEmpty else { NSSound.beep(); return }
        let merged = normalize(ranges)
        multiEdit(ranges: merged, strings: Array(repeating: "", count: merged.count))
    }

    // MARK: - Copy / cut / paste

    override func copy(_ sender: Any?) {
        guard isMultiCursorActive, cursors.contains(where: { $0.length > 0 }) else {
            super.copy(sender)
            return
        }
        let ns = string as NSString
        let block = cursors.map { ns.substring(with: $0) }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, Self.columnBlockType], owner: nil)
        pb.setString(block, forType: .string)
        pb.setString(block, forType: Self.columnBlockType)
    }

    override func cut(_ sender: Any?) {
        guard isMultiCursorActive, cursors.contains(where: { $0.length > 0 }) else {
            super.cut(sender)
            return
        }
        copy(sender)
        multiEdit(ranges: cursors, strings: cursors.map { _ in "" })
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if isMultiCursorActive, let s = pb.string(forType: .string) {
            let lines = s.components(separatedBy: "\n")
            // A block with one entry per cursor distributes; anything else
            // pastes whole at every cursor.
            let strings = lines.count == cursors.count ? lines : cursors.map { _ in s }
            multiEdit(ranges: cursors, strings: strings)
            return
        }
        if let block = pb.string(forType: Self.columnBlockType) {
            pasteColumnBlock(block)
            return
        }
        super.paste(sender)
    }

    /// Pastes a rectangular block at a single caret: entry i goes to line
    /// (caret line + i) at the caret's column. Lines shorter than the column
    /// are skipped (or appended at line end, per setting); entries past the
    /// last line are appended as new lines.
    private func pasteColumnBlock(_ block: String) {
        let ns = string as NSString
        let entries = block.components(separatedBy: "\n")
        guard !entries.isEmpty else { return }
        let sel = selectedRange()
        let starts = lineStarts()
        let startLine = lineIndex(of: sel.location, starts: starts)
        let col = sel.location - starts[startLine]
        var ranges: [NSRange] = []
        var strings: [String] = []
        var trailing = ""
        for (i, entry) in entries.enumerated() {
            let line = startLine + i
            if line < starts.count {
                let content = lineContentRange(line: line, starts: starts, ns: ns)
                if col <= content.length {
                    let length = i == 0 ? sel.length : 0
                    ranges.append(NSRange(location: content.location + col, length: length))
                    strings.append(entry)
                } else if insertAtLineEndWhenShort {
                    ranges.append(NSRange(location: NSMaxRange(content), length: 0))
                    strings.append(entry)
                }
            } else {
                trailing += "\n" + entry
            }
        }
        if !trailing.isEmpty {
            ranges.append(NSRange(location: ns.length, length: 0))
            strings.append(trailing)
        }
        guard let ends = applyEdit(ranges: ranges, strings: strings) else { return }
        if let last = ends.last {
            isProgrammaticSelection = true
            setSelectedRange(last)
            isProgrammaticSelection = false
        }
    }

    // MARK: - Column mode

    private func trackColumnSelection(startingAt event: NSEvent) {
        guard let window else { return }
        window.makeFirstResponder(self)
        let start = convert(event.locationInWindow, from: nil)
        updateColumnSelection(from: start, to: start)
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if next.type == .leftMouseUp { break }
            autoscroll(with: next)
            updateColumnSelection(from: start, to: convert(next.locationInWindow, from: nil))
        }
        // A click (or single-line drag) without vertical extent is not a
        // column selection — fall back to a normal selection.
        if cursors.count == 1 {
            let only = cursors[0]
            clearMultiCursors(keepCaret: false)
            isProgrammaticSelection = true
            setSelectedRange(only)
            isProgrammaticSelection = false
        }
    }

    private func updateColumnSelection(from p1: NSPoint, to p2: NSPoint) {
        guard let lm = layoutManager, let tc = textContainer else { return }
        let ns = string as NSString
        let origin = textContainerOrigin
        let minY = min(p1.y, p2.y) - origin.y
        let maxY = max(p1.y, p2.y) - origin.y
        let minX = min(p1.x, p2.x) - origin.x
        let maxX = max(p1.x, p2.x) - origin.x

        var newCursors: [NSRange] = []
        let fullGlyphs = lm.glyphRange(for: tc)
        var gi = fullGlyphs.location
        while gi < NSMaxRange(fullGlyphs) {
            var effRange = NSRange(location: gi, length: 0)
            let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &effRange)
            if frag.maxY > minY && frag.minY < maxY {
                let midY = frag.midY
                let a = insertionIndex(forX: minX, y: midY, layoutManager: lm, container: tc)
                let b = insertionIndex(forX: maxX, y: midY, layoutManager: lm, container: tc)
                let charRange = lm.characterRange(forGlyphRange: effRange, actualGlyphRange: nil)
                var contentEnd = NSMaxRange(charRange)
                while contentEnd > charRange.location, isNewline(ns.character(at: contentEnd - 1)) {
                    contentEnd -= 1
                }
                let lo = max(charRange.location, min(min(a, b), contentEnd))
                let hi = max(lo, min(max(a, b), contentEnd))
                newCursors.append(NSRange(location: lo, length: hi - lo))
            }
            if effRange.length == 0 { break }
            gi = NSMaxRange(effRange)
        }
        // Empty document or drag below the last fragment
        if newCursors.isEmpty {
            newCursors = [NSRange(location: ns.length, length: 0)]
        }
        mode = .column
        matchQuery = nil
        cursors = normalize(newCursors)
        reanchorColumnState()
        refreshRendering()
    }

    private func insertionIndex(forX x: CGFloat, y: CGFloat, layoutManager lm: NSLayoutManager, container tc: NSTextContainer) -> Int {
        var fraction: CGFloat = 0
        let idx = lm.characterIndex(for: NSPoint(x: x, y: y), in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return fraction > 0.5 ? idx + 1 : idx
    }

    private func extendColumnSelection(by delta: Int) {
        guard isEditable || isSelectable else { return }
        let starts = lineStarts()
        if mode != .column {
            let sel = selectedRange()
            let line = lineIndex(of: sel.location, starts: starts)
            columnAnchorLine = line
            columnExtentLine = line
            columnChar = sel.location - starts[line]
            // Reuse a same-line selection as the column's width
            let selLine = sel.length > 0 ? lineIndex(of: NSMaxRange(sel) - 1, starts: starts) : line
            columnSelectionLength = selLine == line ? sel.length : 0
            mode = .column
            matchQuery = nil
        }
        let newExtent = max(0, min(starts.count - 1, columnExtentLine + delta))
        guard newExtent != columnExtentLine || cursors.isEmpty else {
            NSSound.beep()
            return
        }
        columnExtentLine = newExtent
        rebuildColumnCursors()
    }

    private func rebuildColumnCursors() {
        let ns = string as NSString
        let starts = lineStarts()
        let lo = min(columnAnchorLine, columnExtentLine)
        let hi = max(columnAnchorLine, columnExtentLine)
        guard lo >= 0, hi < starts.count else { return }
        var newCursors: [NSRange] = []
        for line in lo...hi {
            let content = lineContentRange(line: line, starts: starts, ns: ns)
            if columnChar <= content.length {
                let len = min(columnSelectionLength, content.length - columnChar)
                newCursors.append(NSRange(location: content.location + columnChar, length: len))
            } else if insertAtLineEndWhenShort {
                newCursors.append(NSRange(location: NSMaxRange(content), length: 0))
            }
        }
        guard !newCursors.isEmpty else { NSSound.beep(); return }
        cursors = normalize(newCursors)
        refreshRendering()
        if let edge = columnExtentLine >= columnAnchorLine ? cursors.last : cursors.first {
            scrollRangeToVisible(edge)
        }
    }

    private func reanchorColumnState() {
        guard let first = cursors.first, let last = cursors.last else { return }
        let starts = lineStarts()
        columnAnchorLine = lineIndex(of: first.location, starts: starts)
        columnExtentLine = lineIndex(of: last.location, starts: starts)
        columnChar = first.location - starts[columnAnchorLine]
        columnSelectionLength = first.length
    }

    // MARK: - Match mode

    @discardableResult
    private func addNextMatch(forward: Bool) -> Bool {
        guard startMatchSessionIfNeeded() else { return false }
        guard let query = matchQuery else { return false }
        let occ = occurrences(of: query)
        matchTotal = occ.count
        let candidates: [NSRange]
        if forward {
            let anchor = cursors.map { NSMaxRange($0) }.max() ?? 0
            candidates = occ.filter { $0.location >= anchor } + occ.filter { $0.location < anchor }
        } else {
            let anchor = cursors.map { $0.location }.min() ?? 0
            candidates = Array(occ.filter { NSMaxRange($0) <= anchor }.reversed())
                + Array(occ.filter { NSMaxRange($0) > anchor }.reversed())
        }
        let next = candidates.first { cand in
            !cursors.contains { $0 == cand || NSIntersectionRange($0, cand).length > 0 }
        }
        if let next {
            cursors = normalize(cursors + [next])
            refreshRendering()
            scrollRangeToVisible(next)
        } else {
            NSSound.beep()
            refreshRendering()
        }
        return true
    }

    @discardableResult
    private func selectAllMatches() -> Bool {
        guard startMatchSessionIfNeeded() else { return false }
        guard let query = matchQuery else { return false }
        let occ = occurrences(of: query)
        guard !occ.isEmpty else { NSSound.beep(); return true }
        matchTotal = occ.count
        cursors = occ
        refreshRendering()
        return true
    }

    /// Begins a match session from the current (non-empty) selection if one
    /// isn't already active. Returns false when there is nothing to match.
    private func startMatchSessionIfNeeded() -> Bool {
        if mode == .match, matchQuery != nil { return true }
        let sel = selectedRange()
        guard sel.length > 0 else { return false }
        matchQuery = (string as NSString).substring(with: sel)
        matchWholeWord = lastClickWasDouble
        mode = .match
        cursors = [sel]
        return true
    }

    /// Occurrences are recomputed from the current text on every call, so
    /// matches stay live across document edits between ⌘G presses.
    private func occurrences(of query: String) -> [NSRange] {
        let ns = string as NSString
        guard !query.isEmpty else { return [] }
        var result: [NSRange] = []
        var location = 0
        while location < ns.length {
            let found = ns.range(of: query, options: [], range: NSRange(location: location, length: ns.length - location))
            guard found.location != NSNotFound else { break }
            if !matchWholeWord || isWholeWord(found, in: ns) {
                result.append(found)
            }
            location = found.location + max(found.length, 1)
        }
        return result
    }

    private func isWholeWord(_ range: NSRange, in ns: NSString) -> Bool {
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if range.location > 0,
           let scalar = Unicode.Scalar(ns.character(at: range.location - 1)),
           wordChars.contains(scalar) {
            return false
        }
        let end = NSMaxRange(range)
        if end < ns.length,
           let scalar = Unicode.Scalar(ns.character(at: end)),
           wordChars.contains(scalar) {
            return false
        }
        return true
    }

    // MARK: - Multi-range editing core

    /// Performs all replacements as a single undo step and turns each edited
    /// range into a caret after the inserted text.
    private func multiEdit(ranges: [NSRange], strings: [String]) {
        guard let ends = applyEdit(ranges: ranges, strings: strings) else { return }
        cursors = normalize(ends)
        if mode == .match { matchQuery = nil } // matches were rewritten; session over, carets remain
        if mode == .column { reanchorColumnState() }
        refreshRendering()
        if let last = cursors.last { scrollRangeToVisible(last) }
    }

    /// Applies (range, string) replacements atomically. Ranges must be sorted
    /// ascending and non-overlapping. Returns the caret position after each
    /// inserted string, or nil if the change was refused (e.g. locked note).
    private func applyEdit(ranges: [NSRange], strings: [String]) -> [NSRange]? {
        guard !ranges.isEmpty, ranges.count == strings.count, let textStorage else { return nil }
        guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: strings) else { return nil }
        isPerformingMultiEdit = true
        textStorage.beginEditing()
        for (range, str) in zip(ranges, strings).reversed() {
            textStorage.replaceCharacters(in: range, with: str)
        }
        textStorage.endEditing()
        var delta = 0
        var ends: [NSRange] = []
        for (range, str) in zip(ranges, strings) {
            let strLength = (str as NSString).length
            ends.append(NSRange(location: range.location + delta + strLength, length: 0))
            delta += strLength - range.length
        }
        didChangeText()
        isPerformingMultiEdit = false
        return ends
    }

    // MARK: - State / rendering

    func clearMultiCursors(keepCaret: Bool = true) {
        guard mode != .none else { return }
        let last = cursors.last
        mode = .none
        cursors = []
        matchQuery = nil
        if keepCaret, let last {
            let length = (string as NSString).length
            isProgrammaticSelection = true
            setSelectedRange(NSRange(location: min(NSMaxRange(last), length), length: 0))
            isProgrammaticSelection = false
        }
        refreshRendering()
    }

    private func refreshRendering() {
        guard let lm = layoutManager else { return }
        let full = NSRange(location: 0, length: (string as NSString).length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)

        guard isMultiCursorActive else {
            emitStatus(nil)
            updateBlinkTimer()
            needsDisplay = true
            return
        }

        // Subtle highlight on the occurrences that are not yet selected
        if mode == .match, let query = matchQuery {
            for occ in occurrences(of: query) where !cursors.contains(occ) {
                lm.addTemporaryAttribute(.backgroundColor,
                                         value: NSColor.systemYellow.withAlphaComponent(0.3),
                                         forCharacterRange: occ)
            }
        }

        isProgrammaticSelection = true
        let nonEmpty = cursors.filter { $0.length > 0 }
        var nativeHoldsSelections = false
        if nonEmpty.count == cursors.count {
            super.setSelectedRanges(cursors.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
            nativeHoldsSelections = selectedRanges.count == cursors.count
        }
        if !nativeHoldsSelections {
            // Carets (or AppKit refused the range set): highlight selections
            // ourselves and park the native caret on the last cursor.
            for range in nonEmpty {
                lm.addTemporaryAttribute(.backgroundColor,
                                         value: NSColor.selectedTextBackgroundColor,
                                         forCharacterRange: range)
            }
            if let last = cursors.last {
                super.setSelectedRanges([NSValue(range: NSRange(location: NSMaxRange(last), length: 0))],
                                        affinity: .downstream, stillSelecting: false)
            }
        }
        isProgrammaticSelection = false

        if mode == .match, matchQuery != nil {
            emitStatus("\(cursors.count) of \(matchTotal) matches selected")
        } else {
            emitStatus(cursors.count == 1 ? "1 cursor" : "\(cursors.count) cursors")
        }
        updateBlinkTimer()
        needsDisplay = true
    }

    private func emitStatus(_ status: String?) {
        let callback = onStatusChange
        DispatchQueue.main.async { callback?(status) }
    }

    // MARK: - Caret drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isMultiCursorActive, caretsVisible else { return }
        let native = selectedRange()
        for cursor in cursors where cursor.length == 0 {
            // The native caret already blinks at this position
            if native.length == 0 && native.location == cursor.location { continue }
            if let rect = caretRect(at: cursor.location) {
                insertionPointColor.setFill()
                rect.fill()
            }
        }
    }

    private func caretRect(at location: Int) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let ns = string as NSString
        var rect: NSRect
        if location >= ns.length {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 {
                rect = NSRect(x: extra.minX + lineFragmentPadding(), y: extra.minY, width: 1, height: extra.height)
            } else if ns.length > 0 {
                let gi = lm.glyphIndexForCharacter(at: ns.length - 1)
                let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
                let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc)
                rect = NSRect(x: glyphRect.maxX, y: frag.minY, width: 1, height: frag.height)
            } else {
                return nil
            }
        } else {
            let gi = lm.glyphIndexForCharacter(at: location)
            let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            let x = lm.location(forGlyphAt: gi).x
            rect = NSRect(x: frag.minX + x, y: frag.minY, width: 1, height: frag.height)
        }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect.integral
    }

    private func lineFragmentPadding() -> CGFloat {
        textContainer?.lineFragmentPadding ?? 0
    }

    private func updateBlinkTimer() {
        let native = selectedRange()
        let hasCustomCarets = isMultiCursorActive && cursors.contains {
            $0.length == 0 && !(native.length == 0 && native.location == $0.location)
        }
        if hasCustomCarets {
            guard blinkTimer == nil else { return }
            caretsVisible = true
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.caretsVisible.toggle()
                self.needsDisplay = true
            }
        } else {
            blinkTimer?.invalidate()
            blinkTimer = nil
            caretsVisible = true
        }
    }

    // MARK: - Line helpers

    /// Character offsets where each line starts ("a\nb\n" → [0, 2, 4]:
    /// a trailing newline yields an empty final line).
    private func lineStarts() -> [Int] {
        let ns = string as NSString
        var starts = [0]
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            let end = NSMaxRange(enclosing)
            if end < ns.length { starts.append(end) }
        }
        if ns.length > 0, isNewline(ns.character(at: ns.length - 1)) {
            starts.append(ns.length)
        }
        return starts
    }

    private func lineIndex(of charIndex: Int, starts: [Int]) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= charIndex { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The line's range excluding its trailing line terminator.
    private func lineContentRange(line: Int, starts: [Int], ns: NSString) -> NSRange {
        let start = starts[line]
        var end = line + 1 < starts.count ? starts[line + 1] : ns.length
        while end > start, isNewline(ns.character(at: end - 1)) {
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    private func isNewline(_ utf16Char: unichar) -> Bool {
        utf16Char == 0x0A || utf16Char == 0x0D || utf16Char == 0x2028 || utf16Char == 0x2029
    }

    /// Sorts and merges overlapping or duplicate ranges.
    private func normalize(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted {
            $0.location != $1.location ? $0.location < $1.location : $0.length < $1.length
        }
        var result: [NSRange] = []
        for range in sorted {
            if let last = result.last, NSMaxRange(last) > range.location || last.location == range.location {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
