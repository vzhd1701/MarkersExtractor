import ArgumentParser
import Foundation
import Logging
import MarkersExtractor

struct MarkersExtractorCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Tool to extract markers from FCPXML(D).",
        version: "0.1.1"
    )

    @Option(
        help: ArgumentHelp(
            "Marker thumb image format.",
            valueName: MarkerImageFormat.allCases.map { $0.rawValue }.joined(separator: ",")
        )
    )
    var imageFormat: MarkerImageFormat = MarkersExtractorSettings.Defaults.imageFormat

    @Option(
        help: ArgumentHelp(
            "Image quality percent for JPG.",
            valueName: "0-100"
        )
    )
    var imageQuality: Int = MarkersExtractorSettings.Defaults.imageQuality

    @Option(help: ArgumentHelp("Limit image width keeping aspect ratio.", valueName: "w"))
    var imageWidth: Int?

    @Option(help: ArgumentHelp("Limit image height keeping aspect ratio.", valueName: "h"))
    var imageHeight: Int?

    @Option(
        help: ArgumentHelp(
            "Limit image size to % keeping aspect ratio. (default for GIF: 50)",
            valueName: "%"
        )
    )
    var imageSizePercent: Int?

    @Option(help: ArgumentHelp("GIF frame rate.", valueName: "1-50"))
    var gifFPS: Int = MarkersExtractorSettings.Defaults.gifFPS

    @Option(help: ArgumentHelp("GIF capture span around marker.", valueName: "sec"))
    var gifSpan: Int = MarkersExtractorSettings.Defaults.gifSpan

    @Option(
        help: ArgumentHelp(
            "Marker naming mode.",
            valueName: MarkerIDMode.allCases
                .map { $0.rawValue }.joined(separator: ",")
        )
    )
    var idNamingMode: MarkerIDMode = MarkersExtractorSettings.Defaults.idNamingMode

    @Option(
        name: [.customLong("label")],
        help: ArgumentHelp(
            "Label to put on a thumb image, can be used multiple times form multiple labels."
                + " Use --help-labels to get full list of available labels.",
            valueName: "label"
        )
    )
    var imageLabels: [MarkerHeader] = []

    @Option(
        name: [.customLong("label-copyright")],
        help: ArgumentHelp(
            "Copyright label, will be added after all other labels.",
            valueName: "text"
        )
    )
    var imageLabelCopyright: String?

    @Option(
        name: [.customLong("label-font")],
        help: ArgumentHelp("Font for image labels", valueName: "name")
    )
    var imageLabelFont: String = MarkersExtractorSettings.Defaults.imageLabelFont

    @Option(
        name: [.customLong("label-font-size")],
        help: ArgumentHelp(
            "Maximum font size for image labels, "
                + "font size is automatically reduced to fit all labels.",
            valueName: "pt"
        )
    )
    var imageLabelFontMaxSize: Int = MarkersExtractorSettings.Defaults.imageLabelFontMaxSize

    @Option(
        name: [.customLong("label-opacity")],
        help: ArgumentHelp("Label opacity percent", valueName: "0-100")
    )
    var imageLabelFontOpacity: Int = MarkersExtractorSettings.Defaults.imageLabelFontOpacity

    @Option(
        name: [.customLong("label-font-color")],
        help: ArgumentHelp("Label font color", valueName: "#RRGGBB / #RGB")
    )
    var imageLabelFontColor: String = MarkersExtractorSettings.Defaults.imageLabelFontColor

    @Option(
        name: [.customLong("label-stroke-color")],
        help: ArgumentHelp("Label stroke color", valueName: "#RRGGBB / #RGB")
    )
    var imageLabelFontStrokeColor: String = MarkersExtractorSettings.Defaults
        .imageLabelFontStrokeColor

    @Option(
        name: [.customLong("label-stroke-width")],
        help: ArgumentHelp("Label stroke width, 0 to disable. (default: auto)", valueName: "w")
    )
    var imageLabelFontStrokeWidth: Int?

    @Option(
        name: [.customLong("label-align-horizontal")],
        help: ArgumentHelp(
            "Horizontal alignment of image label.",
            valueName: MarkerLabelProperties.AlignHorizontal.allCases
                .map { $0.rawValue }.joined(separator: ",")
        )
    )
    var imageLabelAlignHorizontal: MarkerLabelProperties.AlignHorizontal = MarkersExtractorSettings
        .Defaults.imageLabelAlignHorizontal

    @Option(
        name: [.customLong("label-align-vertical")],
        help: ArgumentHelp(
            "Vertical alignment of image label.",
            valueName: MarkerLabelProperties.AlignVertical.allCases
                .map { $0.rawValue }.joined(separator: ",")
        )
    )
    var imageLabelAlignVertical: MarkerLabelProperties.AlignVertical = MarkersExtractorSettings
        .Defaults.imageLabelAlignVertical

    @Flag(help: "Create 'done.txt' file in output directory on successful export.")
    var createDoneFile = false

    @Option(help: "Log file path.", transform: URL.init(fileURLWithPath:))
    var log: URL?

    @Option(
        help: ArgumentHelp(
            "Log level.",
            valueName: Logger.Level.allCases.map { $0.rawValue }.joined(separator: ",")
        )
    )
    var logLevel: Logger.Level = .info

    @Flag(name: [.customLong("quiet")], help: "Disable log.")
    var logQuiet = false

    @Flag(help: "List all possible labels to use with --label.")
    var helpLabels = false

    @Argument(help: "Input FCPXML file / FCPXMLD bundle.", transform: URL.init(fileURLWithPath:))
    var fcpxmlPath: URL

    @Argument(help: "Output directory.", transform: URL.init(fileURLWithPath:))
    var outputDir: URL

    mutating func validate() throws {
        if let log = log, !FileManager.default.isWritableFile(atPath: log.path) {
            throw ValidationError("Cannot write log file at '\(log.path)'")
        }

        if imageFormat == .gif && imageSizePercent == nil {
            imageSizePercent = MarkersExtractorSettings.Defaults.imageSizePercentGIF
        }
    }

    mutating func run() throws {
        initLogging(logLevel: logQuiet ? nil : logLevel, logFile: log)

        let settings: MarkersExtractorSettings

        do {
            settings = try MarkersExtractorSettings(
                imageFormat: imageFormat,
                imageQuality: imageQuality,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                imageSizePercent: imageSizePercent,
                gifFPS: gifFPS,
                gifSpan: gifSpan,
                idNamingMode: idNamingMode,
                imageLabels: imageLabels,
                imageLabelCopyright: imageLabelCopyright,
                imageLabelFont: imageLabelFont,
                imageLabelFontMaxSize: imageLabelFontMaxSize,
                imageLabelFontOpacity: imageLabelFontOpacity,
                imageLabelFontColor: imageLabelFontColor,
                imageLabelFontStrokeColor: imageLabelFontStrokeColor,
                imageLabelFontStrokeWidth: imageLabelFontStrokeWidth,
                imageLabelAlignHorizontal: imageLabelAlignHorizontal,
                imageLabelAlignVertical: imageLabelAlignVertical,
                createDoneFile: createDoneFile,
                fcpxmlPath: fcpxmlPath,
                outputDir: outputDir
            )
        } catch MarkersExtractorError.validationError(let error) {
            throw ValidationError(error)
        }

        try MarkersExtractor.extract(settings)
    }

    private func initLogging(logLevel: Logger.Level?, logFile: URL?) {
        LoggingSystem.bootstrap { label in
            guard let logLevel = logLevel else {
                return SwiftLogNoOpLogHandler()
            }

            var logHandlers: [LogHandler] = [
                ConsoleLogHandler.init(label: label)
            ]

            if let logFile = logFile {
                do {
                    logHandlers.append(try FileLogHandler.init(label: label, localFile: logFile))
                } catch {
                    print(
                        "Cannot write to log file '\(logFile.lastPathComponent)':"
                            + " \(error.localizedDescription)"
                    )
                }
            }

            for i in 0..<logHandlers.count {
                logHandlers[i].logLevel = logLevel
            }

            return MultiplexLogHandler(logHandlers)
        }
    }
}
