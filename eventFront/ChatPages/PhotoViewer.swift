//
//  PhotoViewer.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 25/9/25.
//


import SwiftUI
import UIKit

struct PhotoViewer: View {
    let url: URL
    var caption: String?

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var backgroundOpacity: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.opacity(backgroundOpacity).ignoresSafeArea()

            GeometryReader { geo in
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .failure(_):
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                            Text("Couldn’t load image")
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            // Double-tap to zoom
                            .onTapGesture(count: 2) {
                                if scale > 1 {
                                    resetZoom()
                                } else {
                                    withAnimation(.easeInOut) {
                                        scale = 2
                                        lastScale = 2
                                    }
                                }
                            }
                            // Pinch + drag
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let new = (lastScale * value).clamped(1, 4)
                                            withAnimation(.linear(duration: 0.001)) { // buttery
                                                scale = new
                                            }
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                            // clamp offset after scaling
                                            offset = clamped(offset, in: geo.size, scale: scale)
                                            lastOffset = offset
                                        },
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { g in
                                            if scale > 1 {
                                                // pan when zoomed
                                                offset = CGSize(
                                                    width: lastOffset.width + g.translation.width,
                                                    height: lastOffset.height + g.translation.height
                                                )
                                            } else {
                                                // swipe down to dismiss
                                                let dy = max(0, g.translation.height)
                                                backgroundOpacity = max(0.4, 1 - dy / 600)
                                            }
                                        }
                                        .onEnded { g in
                                            if scale == 1 && g.translation.height > 120 {
                                                dismiss(); return
                                            }
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                                backgroundOpacity = 1
                                                offset = clamped(offset, in: geo.size, scale: scale)
                                                lastOffset = offset
                                            }
                                        }
                                )
                            )
                            .animation(.default, value: scale)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Top bar + caption
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                        .padding(.bottom, 24)
                        .padding(.horizontal, 12)
                }
            }
        }
        .statusBarHidden(true)
    }

    private func resetZoom() {
        withAnimation(.easeInOut) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    // Clamp pan so you can’t drag past the image bounds
    private func clamped(_ offset: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
        let extraW = max(0, size.width  * (scale - 1)) / 2
        let extraH = max(0, size.height * (scale - 1)) / 2

        return CGSize(
            width:  offset.width.clamped(-extraW,  extraW),
            height: offset.height.clamped(-extraH, extraH)
        )
    }
}

// Tiny helper
private extension Comparable {
    func clamped(_ a: Self, _ b: Self) -> Self {
        let (minV, maxV) = (min(a, b), max(a, b))
        return min(max(self, minV), maxV)
    }
}



struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        scroll.addSubview(iv)
        context.coordinator.imageView = iv

        // double-tap to zoom
        let dt = UITapGestureRecognizer(target: context.coordinator,
                                        action: #selector(Coordinator.doubleTap(_:)))
        dt.numberOfTapsRequired = 2
        iv.addGestureRecognizer(dt)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        guard let iv = context.coordinator.imageView else { return }
        iv.image = image
        iv.frame = scroll.bounds
        scroll.contentSize = scroll.bounds.size
        context.coordinator.configureZoom(for: scroll, imageSize: image.size)
        context.coordinator.centerImage(in: scroll)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func configureZoom(for scroll: UIScrollView, imageSize: CGSize) {
            let b = scroll.bounds.size
            let xScale = b.width  / max(imageSize.width, 1)
            let yScale = b.height / max(imageSize.height, 1)
            let minZoom = max(min(xScale, yScale), 1e-3)

            scroll.minimumZoomScale = minZoom
            scroll.maximumZoomScale = max(minZoom * 4, 1)
            if abs(scroll.zoomScale - minZoom) > 0.001 {
                scroll.zoomScale = minZoom
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(in: scrollView) }

        @objc func doubleTap(_ gr: UITapGestureRecognizer) {
            guard let scroll = gr.view?.superview as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let newScale = min(scroll.maximumZoomScale, scroll.minimumZoomScale * 2)
                let p = gr.location(in: gr.view)
                let size = CGSize(width: scroll.bounds.width / newScale,
                                  height: scroll.bounds.height / newScale)
                let origin = CGPoint(x: p.x - size.width/2, y: p.y - size.height/2)
                scroll.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        func centerImage(in scroll: UIScrollView) {
            guard let v = imageView else { return }
            let bounds = scroll.bounds.size
            let content = scroll.contentSize
            let offsetX = max((bounds.width  - content.width ) * 0.5, 0)
            let offsetY = max((bounds.height - content.height) * 0.5, 0)
            v.center = CGPoint(x: content.width * 0.5 + offsetX,
                               y: content.height * 0.5 + offsetY)
        }
    }
}


