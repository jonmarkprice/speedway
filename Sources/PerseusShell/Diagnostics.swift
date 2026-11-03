import Foundation

/// Unbuffered logging. `print` is block-buffered when stdout is a pipe, so a
/// process killed from a script would lose its last lines; writing through
/// `FileHandle` hits the file descriptor directly. Bridge traffic goes to
/// stdout (one line per message, which is how the shell is verified without a
/// UI) and everything else to stderr.
enum Diagnostics {
    static func stdout(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func stderr(_ line: String) {
        FileHandle.standardError.write(Data(("PerseusShell: " + line + "\n").utf8))
    }
}
