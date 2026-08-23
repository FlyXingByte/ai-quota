// Builds a macOS iconset and a masked 1024 px master from the Codex ImageGen
// artwork. Convert Resources/AppIcon.png to .icns with sips after rendering.
// The generated source has an opaque canvas, so each size is clipped to the
// app-icon plate here to preserve transparent corners in the final .icns.
import AppKit

let resourcesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let sourceURL = resourcesDir.appendingPathComponent("AppIcon-ImageGen.png")
let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : resourcesDir.appendingPathComponent("AppIcon.iconset")

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load ImageGen artwork at \(sourceURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func renderIcon(pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let size = CGFloat(pixels)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    context.cgContext.clear(rect)

    // Clip just inside the generated white plate, removing its opaque corners
    // while keeping the artwork, padding, and subtle edge depth intact.
    let inset = size * 0.022
    let plate = rect.insetBy(dx: inset, dy: inset)
    let mask = NSBezierPath(
        roundedRect: plate,
        xRadius: plate.width * 0.235,
        yRadius: plate.height * 0.235
    )
    mask.addClip()
    source.draw(
        in: rect,
        from: CGRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    NSGraphicsContext.restoreGraphicsState()
    if pixels == 1024 {
        // sips expects a 1024 px @2x master (144 dpi) for ICNS conversion.
        bitmap.size = NSSize(width: 512, height: 512)
    }
    return bitmap.representation(using: .png, properties: [:])
}

let sizes: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (points, scale) in sizes {
    let pixels = points * scale
    guard let png = renderIcon(pixels: pixels) else {
        fputs("Could not render \(pixels) px icon\n", stderr)
        exit(1)
    }

    let name = scale == 1
        ? "icon_\(points)x\(points).png"
        : "icon_\(points)x\(points)@2x.png"
    try png.write(to: outDir.appendingPathComponent(name))
    if pixels == 1024 {
        try png.write(to: resourcesDir.appendingPathComponent("AppIcon.png"))
    }
}

print("wrote \(sizes.count) sizes and Resources/AppIcon.png from \(sourceURL.lastPathComponent)")
