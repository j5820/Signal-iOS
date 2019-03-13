//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public protocol ImageEditorPaletteViewDelegate: class {
    func selectedColorDidChange()
}

// MARK: -

// We represent image editor colors using this (color, phase)
// tuple so that we can consistently restore palette view
// state.
@objc
public class ImageEditorColor: NSObject {
    public let color: UIColor

    // Colors are chosen from a spectrum of colors.
    // This unit value represents the location of the
    // color within that spectrum.
    public let palettePhase: CGFloat

    public var cgColor: CGColor {
        return color.cgColor
    }

    public required init(color: UIColor, palettePhase: CGFloat) {
        self.color = color
        self.palettePhase = palettePhase
    }

    public class func defaultColor() -> ImageEditorColor {
        return ImageEditorColor(color: UIColor(rgbHex: 0xffffff), palettePhase: 0)
    }

    public static var gradientUIColors: [UIColor] {
        return [
            UIColor(rgbHex: 0xffffff),
            UIColor(rgbHex: 0xff0000),
            UIColor(rgbHex: 0xff00ff),
            UIColor(rgbHex: 0x0000ff),
            UIColor(rgbHex: 0x00ffff),
            UIColor(rgbHex: 0x00ff00),
            UIColor(rgbHex: 0xffff00),
            UIColor(rgbHex: 0xff5500),
            UIColor(rgbHex: 0x000000)
        ]
    }

    public static var gradientCGColors: [CGColor] {
        return gradientUIColors.map({ (color) in
            return color.cgColor
        })
    }

    static func ==(left: ImageEditorColor, right: ImageEditorColor) -> Bool {
        return left.palettePhase.fuzzyEquals(right.palettePhase)
    }
}

// MARK: -

public class ImageEditorPaletteView: UIView {

    public weak var delegate: ImageEditorPaletteViewDelegate?

    public var selectedValue: ImageEditorColor

    public required init(currentColor: ImageEditorColor) {
        self.selectedValue = currentColor

        super.init(frame: .zero)

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Views

    private let imageView = UIImageView()
    private let selectionView = UIView()
    // imageWrapper is used to host the "selection view".
    private let imageWrapper = OWSLayerView()
    private let shadowView = UIView()
    private var selectionConstraint: NSLayoutConstraint?

    private func createContents() {
        self.backgroundColor = .clear
        self.isOpaque = false
        self.layoutMargins = .zero

        shadowView.backgroundColor = .black
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowRadius = 2.0
        shadowView.layer.shadowOpacity = 0.33
        shadowView.layer.shadowOffset = .zero
        addSubview(shadowView)

        if let image = ImageEditorPaletteView.buildPaletteGradientImage() {
            imageView.image = image
            let imageRadius = image.size.width * 0.5
            imageView.layer.cornerRadius = imageRadius
            shadowView.layer.cornerRadius = imageRadius
            imageView.clipsToBounds = true
        } else {
            owsFailDebug("Missing image.")
        }
        addSubview(imageView)
        // We use an invisible margin to expand the hot area of this control.
        let margin: CGFloat = 20
        imageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin))
        imageView.addBorder(with: .white)

        imageWrapper.layoutCallback = { [weak self] (view) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateState()
        }
        addSubview(imageWrapper)
        imageWrapper.autoPin(toEdgesOf: imageView)
        shadowView.autoPin(toEdgesOf: imageView)

        selectionView.addBorder(with: .white)
        selectionView.layer.cornerRadius = selectionSize / 2
        selectionView.autoSetDimensions(to: CGSize(width: selectionSize, height: selectionSize))
        imageWrapper.addSubview(selectionView)
        selectionView.autoHCenterInSuperview()

        // There must be a better way to pin the selection view's location,
        // but I can't find it.
        let selectionConstraint = NSLayoutConstraint(item: selectionView,
                                                     attribute: .centerY, relatedBy: .equal, toItem: imageWrapper, attribute: .top, multiplier: 1, constant: 0)
        selectionConstraint.autoInstall()
        self.selectionConstraint = selectionConstraint

        isUserInteractionEnabled = true
        addGestureRecognizer(PaletteGestureRecognizer(target: self, action: #selector(didTouch)))

        updateState()
    }

    // 0 = the color at the top of the image is selected.
    // 1 = the color at the bottom of the image is selected.
    private let selectionSize: CGFloat = 20

    private func selectColor(atLocationY y: CGFloat) {
        let palettePhase = y.inverseLerp(0, imageView.height(), shouldClamp: true)
        self.selectedValue = value(for: palettePhase)

        updateState()

        delegate?.selectedColorDidChange()
    }

    private func value(for palettePhase: CGFloat) -> ImageEditorColor {
        // We find the color in the palette's gradient that corresponds
        // to the "phase".
        //
        // 0 = top of gradient, first color.
        // 1 = bottom of gradient, last color.
        struct GradientSegment {
            let color0: UIColor
            let color1: UIColor
            let palettePhase0: CGFloat
            let palettePhase1: CGFloat
        }
        var segments = [GradientSegment]()
        let segmentCount = ImageEditorColor.gradientUIColors.count - 1
        var prevColor: UIColor?
        for color in ImageEditorColor.gradientUIColors {
            if let color0 = prevColor {
                let index = CGFloat(segments.count)
                let color1 = color
                let palettePhase0: CGFloat = index / CGFloat(segmentCount)
                let palettePhase1: CGFloat = (index + 1) / CGFloat(segmentCount)
                segments.append(GradientSegment(color0: color0, color1: color1, palettePhase0: palettePhase0, palettePhase1: palettePhase1))
            }
            prevColor = color
        }
        var bestSegment = segments.first
        for segment in segments {
            if palettePhase >= segment.palettePhase0 {
                bestSegment = segment
            }
        }
        guard let segment = bestSegment else {
            owsFailDebug("Couldn't find matching segment.")
            return ImageEditorColor.defaultColor()
        }
        guard palettePhase >= segment.palettePhase0,
            palettePhase <= segment.palettePhase1 else {
            owsFailDebug("Invalid segment.")
            return ImageEditorColor.defaultColor()
        }
        let segmentPhase = palettePhase.inverseLerp(segment.palettePhase0, segment.palettePhase1).clamp01()
        // If CAGradientLayer doesn't do naive RGB color interpolation,
        // this won't be WYSIWYG.
        let color = segment.color0.blend(with: segment.color1, alpha: segmentPhase)
        return ImageEditorColor(color: color, palettePhase: palettePhase)
    }

    private func updateState() {
        selectionView.backgroundColor = selectedValue.color

        guard let selectionConstraint = selectionConstraint else {
            owsFailDebug("Missing selectionConstraint.")
            return
        }
        let selectionY = imageWrapper.height() * selectedValue.palettePhase
        selectionConstraint.constant = selectionY
    }

    // MARK: Events

    @objc
    func didTouch(gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began, .changed, .ended:
            break
        default:
            return
        }

        let location = gesture.location(in: imageView)
        selectColor(atLocationY: location.y)
    }

    private static func buildPaletteGradientImage() -> UIImage? {
        let gradientSize = CGSize(width: 8, height: 200)
        let gradientBounds = CGRect(origin: .zero, size: gradientSize)
        let gradientView = UIView()
        gradientView.frame = gradientBounds
        let gradientLayer = CAGradientLayer()
        gradientView.layer.addSublayer(gradientLayer)
        gradientLayer.frame = gradientBounds
        // See: https://github.com/signalapp/Signal-Android/blob/master/res/values/arrays.xml#L267
        gradientLayer.colors = ImageEditorColor.gradientCGColors
        gradientLayer.startPoint = CGPoint.zero
        gradientLayer.endPoint = CGPoint(x: 0, y: gradientSize.height)
        gradientLayer.endPoint = CGPoint(x: 0, y: 1.0)
        return gradientView.renderAsImage(opaque: true, scale: UIScreen.main.scale)
    }
}

// MARK: -

// The most permissive GR possible. Accepts any number of touches in any locations.
private class PaletteGestureRecognizer: UIGestureRecognizer {

    @objc
    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    private func handle(event: UIEvent) {
        var hasValidTouch = false
        if let allTouches = event.allTouches {
            for touch in allTouches {
                switch touch.phase {
                case .began, .moved, .stationary:
                    hasValidTouch = true
                default:
                    break
                }
            }
        }

        if hasValidTouch {
            switch self.state {
            case .possible:
                self.state = .began
            case .began, .changed:
                self.state = .changed
            default:
                self.state = .failed
            }
        } else {
            switch self.state {
            case .began, .changed:
                self.state = .ended
            default:
                self.state = .failed
            }
        }
    }
}