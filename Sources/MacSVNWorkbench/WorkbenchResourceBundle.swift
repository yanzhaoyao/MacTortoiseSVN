import Foundation

/// Resolves SPM-processed resources after the workbench is packaged into `.app`.
/// `Bundle.module` only works in the local SwiftPM build directory and crashes in distributed builds.
enum WorkbenchResourceBundle {
    static let bundle: Bundle = {
        let resourceBundleNames = [
            "MacTortoiseSVN_MacSVNWorkbench",
            "MacSVNWorkbench",
        ]

        for name in resourceBundleNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return Bundle.main
    }()
}
