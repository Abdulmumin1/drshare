import AppKit
import CoreImage

enum QRCodeRenderer {
    private static let context = CIContext(options: nil)

    static func image(for string: String, dimension: CGFloat = 172) -> NSImage? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let extent = outputImage.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let scale = floor(dimension / max(extent.width, extent.height))
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: max(scale, 1), y: max(scale, 1)))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
    }
}
