import ReplayKit
import SwiftUI

/// Wraps RPSystemBroadcastPickerView so it works reliably in SwiftUI.
///
/// The trick: SwiftUI ignores touches on near-zero-opacity views,
/// so we keep the SwiftUI view fully opaque but hide the picker's
/// native button icon at the UIKit level. The button is still in
/// the responder chain and receives taps normally.
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> PickerContainerView {
        let container = PickerContainerView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = true
        return container
    }

    func updateUIView(_ uiView: PickerContainerView, context: Context) {}

    class PickerContainerView: UIView {
        private let picker = RPSystemBroadcastPickerView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            picker.preferredExtension = "com.dayouxia.ScreenCaster.Broadcast"
            picker.showsMicrophoneButton = false
            picker.backgroundColor = .clear
            picker.translatesAutoresizingMaskIntoConstraints = false
            addSubview(picker)

            NSLayoutConstraint.activate([
                picker.leadingAnchor.constraint(equalTo: leadingAnchor),
                picker.trailingAnchor.constraint(equalTo: trailingAnchor),
                picker.topAnchor.constraint(equalTo: topAnchor),
                picker.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Stretch the internal button to fill the entire area,
            // and hide its icon so our SwiftUI decorations show through.
            for child in picker.subviews where child is UIButton {
                let btn = child as! UIButton
                btn.frame = picker.bounds
                btn.setImage(nil, for: .normal)
                btn.tintColor = .clear
            }
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // Always route taps to the picker's internal UIButton.
            for child in picker.subviews where child is UIButton {
                return child
            }
            return super.hitTest(point, with: event)
        }
    }
}
