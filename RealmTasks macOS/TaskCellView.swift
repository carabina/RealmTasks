////////////////////////////////////////////////////////////////////////////
//
// Copyright 2016 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

// FIXME: This file should be split up.
// swiftlint:disable file_length

import Cocoa
import Cartography

protocol TaskCellViewDelegate: class {

    func cellView(view: TaskCellView, didComplete complete: Bool)
    func cellViewDidDelete(view: TaskCellView)

    func cellViewDidBeginEditing(view: TaskCellView)
    func cellViewDidChangeText(view: TaskCellView)
    func cellViewDidEndEditing(view: TaskCellView)

}

private let iconWidth: CGFloat = 40
private let iconOffset = iconWidth / 2
private let swipeThreshold = iconWidth * 2

class TaskCellView: NSTableCellView {

    weak var delegate: TaskCellViewDelegate?

    var text: String {
        set {
            textView.stringValue = newValue
        }

        get {
            return textView.stringValue
        }
    }

    var completed = false {
        didSet {
            completed ? textView.strike() : textView.unstrike()
            overlayView.hidden = !completed
            overlayView.backgroundColor = completed ? .completeDimBackgroundColor() : .completeGreenBackgroundColor()
            textView.alphaValue = completed ? 0.3 : 1
            textView.editable = !completed
        }
    }

    var editable: Bool {
        set {
            textView.editable = newValue && !completed
        }

        get {
            return textView.editable
        }
    }

    var backgroundColor: NSColor {
        set {
            contentView.backgroundColor = newValue
        }

        get {
            return contentView.backgroundColor
        }
    }

    private let doneIconView: NSImageView = {
        let imageView = NSImageView()
        imageView.image = NSImage(named: "DoneIcon")
        return imageView
    }()

    private let deleteIconView: NSImageView = {
        let imageView = NSImageView()
        imageView.image = NSImage(named: "DeleteIcon")
        return imageView
    }()

    private let contentView = ColorView()
    private let overlayView = ColorView()
    private let textView = TaskTextField()

    private var releaseAction: ReleaseAction?

    init(identifier: String) {
        super.init(frame: .zero)
        self.identifier = identifier

        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureWithTask(item: Task) {
        textView.stringValue = item.text
        completed = item.completed
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        alphaValue = 1
        contentView.frame.origin.x = 0
    }

    override func acceptsFirstMouse(theEvent: NSEvent?) -> Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        return textView.forceBecomeFirstResponder()
    }

    private func setupUI() {
        setupIconViews()
        setupContentView()
        setupOverlayView()
        setupTextView()
    }

    private func setupIconViews() {
        doneIconView.frame.size.width = iconWidth
        doneIconView.frame.origin.x = iconOffset
        doneIconView.autoresizingMask = [.ViewMaxXMargin, .ViewHeightSizable]
        addSubview(doneIconView, positioned: .Below, relativeTo: contentView)

        deleteIconView.frame.size.width = iconWidth
        deleteIconView.frame.origin.x = bounds.width - deleteIconView.bounds.width - iconOffset
        deleteIconView.autoresizingMask = [.ViewMinXMargin, .ViewHeightSizable]
        addSubview(deleteIconView, positioned: .Below, relativeTo: contentView)
    }

    private func setupContentView() {
        addSubview(contentView)

        contentView.frame = bounds
        contentView.autoresizingMask = [.ViewWidthSizable, .ViewHeightSizable]

        setupBorders()
    }

    private func setupBorders() {
        let highlightLine = ColorView(backgroundColor: NSColor(white: 1, alpha: 0.05))
        let shadowLine = ColorView(backgroundColor: NSColor(white: 0, alpha: 0.05))

        contentView.addSubview(highlightLine)
        contentView.addSubview(shadowLine)

        let singlePixelInPoints = 1 / NSScreen.mainScreen()!.backingScaleFactor

        constrain(highlightLine, shadowLine) { highlightLine, shadowLine in
            highlightLine.top == highlightLine.superview!.top
            highlightLine.left == highlightLine.superview!.left
            highlightLine.right == highlightLine.superview!.right
            highlightLine.height == singlePixelInPoints

            shadowLine.bottom == shadowLine.superview!.bottom
            shadowLine.left == shadowLine.superview!.left
            shadowLine.right == shadowLine.superview!.right
            shadowLine.height == singlePixelInPoints
        }
    }

    private func setupOverlayView() {
        contentView.addSubview(overlayView)

        constrain(overlayView) { overlayView in
            overlayView.edges == overlayView.superview!.edges
        }
    }

    private func setupTextView() {
        textView.delegate = self

        contentView.addSubview(textView)

        constrain(textView) { textView in
            textView.edges == inset(textView.superview!.edges, 8, 14)
        }
    }

    private func setupGestures() {
        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan))
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
    }

}

// MARK: TaskTextFieldDelegate

extension TaskCellView: TaskTextFieldDelegate {

    func textFieldDidBecomeFirstResponder(textField: NSTextField) {
        delegate?.cellViewDidBeginEditing(self)
    }

    override func controlTextDidChange(obj: NSNotification) {
        delegate?.cellViewDidChangeText(self)
    }

    override func controlTextDidEndEditing(obj: NSNotification) {
        delegate?.cellViewDidEndEditing(self)
    }

}

// MARK: NSGestureRecognizerDelegate

extension TaskCellView: NSGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard gestureRecognizer is NSPanGestureRecognizer else {
            return false
        }

        let currentlyEditingTextField = ((window?.firstResponder as? NSText)?.delegate as? NSTextField)

        guard let event = NSApp.currentEvent where currentlyEditingTextField != textView else {
            return false
        }

        return fabs(event.deltaX) > fabs(event.deltaY)
    }

    // FIXME: This could easily be refactored to avoid such a high CC.
    // swiftlint:disable:next cyclomatic_complexity
    private dynamic func handlePan(recognizer: NSPanGestureRecognizer) {
        let originalDoneIconOffset = iconOffset
        let originalDeleteIconOffset = bounds.width - deleteIconView.bounds.width - iconOffset

        switch recognizer.state {
        case .Began:
            window?.makeFirstResponder(nil)

            releaseAction = nil
        case .Changed:
            let translation = recognizer.translationInView(self)
            recognizer.setTranslation(translation, inView: self)

            contentView.frame.origin.x = translation.x

            if abs(translation.x) > swipeThreshold {
                doneIconView.frame.origin.x = originalDoneIconOffset + translation.x - swipeThreshold

                deleteIconView.frame.origin.x = originalDeleteIconOffset + translation.x + swipeThreshold
            } else {
                doneIconView.frame.origin.x = originalDoneIconOffset
                deleteIconView.frame.origin.x = originalDeleteIconOffset
            }

            let fractionOfThreshold = min(1, Double(abs(translation.x) / swipeThreshold))

            doneIconView.alphaValue = CGFloat(fractionOfThreshold)
            deleteIconView.alphaValue = CGFloat(fractionOfThreshold)

            releaseAction = fractionOfThreshold == 1 ? (translation.x > 0 ? .Complete : .Delete) : nil

            if completed {
                overlayView.hidden = releaseAction == .Complete
                textView.alphaValue = releaseAction == .Complete ? 1 : 0.3

                if contentView.frame.origin.x > 0 {
                    textView.strike(1 - fractionOfThreshold)
                } else {
                    releaseAction == .Complete ? textView.unstrike() : textView.strike()
                }
            } else {
                overlayView.backgroundColor = .completeGreenBackgroundColor()
                overlayView.hidden = releaseAction != .Complete

                if contentView.frame.origin.x > 0 {
                    textView.strike(fractionOfThreshold)
                } else {
                    releaseAction == .Complete ? textView.strike() : textView.unstrike()
                }
            }
        case .Ended:
            let animationBlock: () -> ()
            let completionBlock: () -> ()

            // If not deleting, slide it back into the middle
            // If we are deleting, slide it all the way out of the view
            switch releaseAction {
            case .Complete?:
                animationBlock = {
                    self.contentView.frame.origin.x = 0
                }

                completionBlock = {
                    NSView.animateWithDuration(0.2, animations: {
                        self.completed = !self.completed
                    }, completion: {
                        self.delegate?.cellView(self, didComplete: self.completed)
                    })
                }
            case .Delete?:
                animationBlock = {
                    self.alphaValue = 0

                    self.contentView.frame.origin.x = -self.contentView.bounds.width - swipeThreshold
                    self.deleteIconView.frame.origin.x = -swipeThreshold + self.deleteIconView.bounds.width + iconOffset
                }

                completionBlock = {
                    self.delegate?.cellViewDidDelete(self)
                }
            case nil:
                completed ? textView.strike() : textView.unstrike()

                animationBlock = {
                    self.contentView.frame.origin.x = 0
                }

                completionBlock = {}
            }

            NSView.animateWithDuration(0.2, animations: animationBlock) {
                completionBlock()

                self.doneIconView.frame.origin.x = originalDoneIconOffset
                self.deleteIconView.frame.origin.x = originalDeleteIconOffset
            }
        default:
            break
        }
    }

}

// MARK: Private Classes

private enum ReleaseAction {
    case Complete, Delete
}

protocol TaskTextFieldDelegate: NSTextFieldDelegate {

    func textFieldDidBecomeFirstResponder(textField: NSTextField)

}

private final class TaskTextField: NSTextField {

    private var _acceptsFirstResponder = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        bordered = false
        focusRingType = .None
        font = .systemFontOfSize(18)
        textColor = .whiteColor()
        backgroundColor = .clearColor()
        lineBreakMode = .ByWordWrapping
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        return _acceptsFirstResponder
    }

    override func acceptsFirstMouse(theEvent: NSEvent?) -> Bool {
        return false
    }

    override func becomeFirstResponder() -> Bool {
        (delegate as? TaskTextFieldDelegate)?.textFieldDidBecomeFirstResponder(self)

        return super.becomeFirstResponder()
    }

    func forceBecomeFirstResponder() -> Bool {
        _acceptsFirstResponder = true
        becomeFirstResponder()
        _acceptsFirstResponder = false

        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrowCursor())
    }

    override var intrinsicContentSize: NSSize {
        // By default editable NSTextField doesn't respect wrapping while calculating intrinsic content size,
        // let's calculate the correct one by ourselves
        let placeholderFrame = NSRect(origin: .zero, size: NSSize(width: frame.width, height: .max))
        let calculatedHeight = cell!.cellSizeForBounds(placeholderFrame).height

        return NSSize(width: frame.width, height: calculatedHeight)
    }

    override func textDidChange(notification: NSNotification) {
        super.textDidChange(notification)

        // Update height on text change
        invalidateIntrinsicContentSize()
    }

}

private final class ColorView: NSView {

    var backgroundColor = NSColor.clearColor() {
        didSet {
            needsDisplay = true
        }
    }

    convenience init(backgroundColor: NSColor) {
        self.init(frame: .zero)
        self.backgroundColor = backgroundColor
    }

    override func drawRect(dirtyRect: NSRect) {
        backgroundColor.setFill()
        NSRectFillUsingOperation(dirtyRect, .SourceOver)
    }

}

// MARK: Private Extensions

private extension NSTextField {

    func strike(fraction: Double = 1) {
        if fraction < 1 {
            unstrike()
        }

        let range = NSRange(location: 0, length: Int(fraction * Double(stringValue.characters.count)))
        setAttribute(NSStrikethroughStyleAttributeName, value: NSUnderlineStyle.StyleThick.rawValue, range: range)
    }

    func unstrike() {
        setAttribute(NSStrikethroughStyleAttributeName, value: NSUnderlineStyle.StyleNone.rawValue)
    }

    private func setAttribute(name: String, value: AnyObject, range: NSRange? = nil) {
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedStringValue)
        let range = range ?? NSRange(location: 0, length: mutableAttributedString.length)
        mutableAttributedString.addAttribute(name, value: value, range: range)
        attributedStringValue = mutableAttributedString
    }

}
