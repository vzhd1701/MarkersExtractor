import AVFoundation
import Foundation
import Logging

final class ImageExtractorGIF {
    enum Error: LocalizedError {
        case invalidSettings
        case unreadableFile
        case gifInitializationFailed
        case gifFinalizationFailed
        case notEnoughFrames(Int)
        case generateFrameFailed(Swift.Error)
        case addFrameFailed(Swift.Error)
        case writeFailed(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .invalidSettings:
                return "Invalid settings."
            case .unreadableFile:
                return "The selected file is no longer readable."
            case .gifInitializationFailed:
                return "Failed to initialize the GIF file"
            case .gifFinalizationFailed:
                return "Failed to finalize the GIF file"
            case .notEnoughFrames(let frameCount):
                return
                    "An animated GIF requires a minimum of 2 frames. Your video contains \(frameCount) frame\(frameCount == 1 ? "" : "s")."
            case .generateFrameFailed(let error):
                return "Failed to generate frame: \(error.localizedDescription)"
            case .addFrameFailed(let error):
                return "Failed to add frame, with underlying error: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Failed to write, with underlying error: \(error.localizedDescription)"
            }
        }
    }

    struct Conversion {
        let asset: AVAsset
        let sourceURL: URL
        let destURL: URL
        var timeRange: ClosedRange<Double>?
        var dimensions: CGSize?
        var frameRate: Int
        let imageFilter: ((CGImage) -> CGImage)?
    }

    private let logger = Logger(label: "\(ImageExtractorGIF.self)")

    private let conversion: Conversion

    init(_ conversion: Conversion) {
        self.conversion = conversion
    }

    static func convert(_ conversion: Conversion) throws {
        try self.init(conversion).generateGif()
    }

    private func generateGif() throws {
        let generator = imageGenerator()
        let times = try rangeToTimes()

        let startTime = times.first?.seconds ?? 0
        let delayTime = 1.0 / Float(conversion.frameRate)

        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delayTime
            ]
        ]

        let gifDestination = try initGif(framesCount: times.count)

        var result: Result<Void, Error> = .failure(.invalidSettings)

        let group = DispatchGroup()
        group.enter()

        generator.generateCGImagesAsynchronously(forTimePoints: times) { [weak self] imageResult in
            guard let self = self else {
                result = .failure(.invalidSettings)
                group.leave()
                return
            }

            let frameResult = self.processFrame(
                for: imageResult,
                at: startTime,
                destination: gifDestination,
                frameProperties: frameProperties as CFDictionary
            )

            switch frameResult {
            case .success(let finished):
                if finished {
                    result = .success(())
                    group.leave()
                }
            case .failure(let error):
                result = .failure(error)
                group.leave()
            }
        }

        group.wait()

        if !CGImageDestinationFinalize(gifDestination) {
            throw Error.gifFinalizationFailed
        }

        switch result {
        case .failure(let error):
            throw error
        case .success():
            return
        }
    }

    private func initGif(framesCount: Int) throws -> CGImageDestination {
        let fileProperties =
            [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: NSNumber(value: 0)
                ],
                kCGImagePropertyGIFHasGlobalColorMap as String: NSValue(nonretainedObject: true),
            ] as [String: Any]

        guard
            let destination = CGImageDestinationCreateWithURL(
                conversion.destURL as CFURL,
                kUTTypeGIF,
                framesCount,
                nil
            )
        else {
            throw Error.gifInitializationFailed
        }

        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        return destination
    }

    private func imageGenerator() -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: conversion.asset)

        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // This improves the performance a little bit.
        if let dimensions = conversion.dimensions {
            generator.maximumSize = CGSize(widthHeight: dimensions.longestSide)
        }

        return generator
    }

    private func rangeToTimes() throws -> [CMTime] {
        let (firstVideoTrack, assetFrameRate, videoTrackRange) = try assetVideoParams()

        // Even though we enforce a minimum of 3 FPS in the GUI, a source video could have lower FPS, and we should allow that.
        var fps = Double(conversion.frameRate).clamped(to: 0.1...50)
        fps = min(fps, assetFrameRate)

        // TODO: Instead of calculating what part of the video to get, we could just trim the actual `AVAssetTrack`.
        let videoRange = conversion.timeRange?.clamped(to: videoTrackRange) ?? videoTrackRange
        let startTime = videoRange.lowerBound
        let duration = videoRange.length
        let frameCount = Int(duration * fps)
        let timescale = firstVideoTrack.naturalTimeScale

        guard frameCount >= 2 else {
            throw Error.notEnoughFrames(frameCount)
        }

        let frameStep = 1 / fps
        let frameForTimes: [CMTime] = (0..<frameCount).map { index in
            let presentationTimestamp = startTime + (frameStep * Double(index))
            return CMTime(
                seconds: presentationTimestamp,
                preferredTimescale: timescale
            )
        }

        // Ensure we include the last frame. For example, the above might have calculated `[..., 6.25, 6.3]`, but the duration is `6.3647`, so we might miss the last frame if it appears for a short time.
        //        frameForTimes.append(CMTime(seconds: duration, preferredTimescale: timescale))

        logger.trace("Frame count: \(frameCount)")
        logger.trace("fps: \(fps)")
        logger.trace("videoRange: \(videoRange)")
        logger.trace("frameCount: \(frameCount)")
        logger.trace("frameForTimes: \(frameForTimes.map(\.seconds))")

        return frameForTimes
    }

    private func assetVideoParams() throws -> (
        firstVideoTrack: AVAssetTrack, frameRate: Double, videoTrackRange: ClosedRange<Double>
    ) {
        let asset = conversion.asset

        guard
            asset.isReadable,
            let frameRate = asset.frameRate,
            let firstVideoTrack = asset.firstVideoTrack,

            // We use the duration of the first video track since the total duration of the asset can actually be longer than the video track. If we use the total duration and the video is shorter, we'll get errors in `generateCGImagesAsynchronously` (#119).
            // We already extract the video into a new asset in `VideoValidator` if the first video track is shorter than the asset duration, so the handling here is not strictly necessary but kept just to be safe.
            let videoTrackRange = firstVideoTrack.timeRange.range
        else {
            // This can happen if the user selects a file, and then the file becomes
            // unavailable or deleted before the "Convert" button is clicked.
            throw Error.unreadableFile
        }

        return (firstVideoTrack, frameRate, videoTrackRange)
    }

    private func processFrame(
        for result: Result<AVAssetImageGenerator.CompletionHandlerResult, Swift.Error>,
        at startTime: TimeInterval,
        destination: CGImageDestination,
        frameProperties: CFDictionary
    ) -> Result<Bool, Error> {
        switch result {
        case .success(let result):
            // This happens if the last frame in the video failed to be generated.
            if result.isFinishedIgnoreImage {
                return .success(true)
            }

            if result.completedCount == 1 {
                logger.trace("CGImage: \(result.image.debugInfo)")
            }

            // TODO: This is just a workaround. Look into the cause of this.
            // https://github.com/sindresorhus/Gifski/pull/262
            // Skip incorrect out-of-range frames.
            if result.actualTime.seconds < startTime {
                return .success(false)
            }

            let image = conversion.imageFilter?(result.image) ?? result.image

            let frameNumber = result.completedCount - 1
            assert(result.actualTime.seconds > 0 || frameNumber == 0)

            CGImageDestinationAddImage(destination, image, frameProperties)

            return .success(result.isFinished)
        case .failure(let error):
            return .failure(.generateFrameFailed(error))
        }
    }
}
