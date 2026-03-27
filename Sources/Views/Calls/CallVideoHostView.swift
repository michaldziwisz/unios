import SwiftUI

#if canImport(UIKit)
import UIKit

struct CallVideoHostView: UIViewRepresentable {
    let requestView: (@escaping (UIView?) -> Void) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VideoContainerView {
        let view = VideoContainerView()
        view.backgroundColor = UIColor.black
        view.clipsToBounds = true
        view.accessibilityElementsHidden = true

        requestView { hostedView in
            DispatchQueue.main.async {
                context.coordinator.attach(hostedView, to: view)
            }
        }

        return view
    }

    func updateUIView(_ uiView: VideoContainerView, context: Context) {
        context.coordinator.layoutHostedView(in: uiView)
        requestView { hostedView in
            DispatchQueue.main.async {
                context.coordinator.attach(hostedView, to: uiView)
            }
        }
    }

    final class Coordinator {
        private weak var hostedView: UIView?

        func attach(_ view: UIView?, to container: VideoContainerView) {
            guard hostedView !== view else {
                layoutHostedView(in: container)
                return
            }

            hostedView?.removeFromSuperview()
            hostedView = view

            guard let view else {
                return
            }

            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.frame = container.bounds
            container.addSubview(view)
        }

        func layoutHostedView(in container: VideoContainerView) {
            hostedView?.frame = container.bounds
        }
    }
}

final class VideoContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        subviews.forEach { $0.frame = bounds }
    }
}
#else
struct CallVideoHostView: View {
    let requestView: (@escaping (Any?) -> Void) -> Void

    var body: some View {
        Color.black
    }
}
#endif
