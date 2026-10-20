import Foundation

/// Main app resources take priority; command-line distributions may place a
/// resource beside their executable, while SwiftPM uses its module bundle.
enum BundledResource {
    // Packaged apps may have main resources without any SwiftPM bundle.
    // Resolve the module only when both preceding locations are missing.
    static func url(_ name: String, extension ext: String, main: Bundle = .main,
                    module: @autoclosure () -> Bundle = .module, executable: URL? = nil) throws -> URL {
        if let url = main.url(forResource: name, withExtension: ext) { return url }
        if let executable, FileManager.default.fileExists(atPath: executable.path) { return executable }
        if let url = module().url(forResource: name, withExtension: ext) { return url }
        throw CocoaError(.fileNoSuchFile)
    }
}
