import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @State private var inputFilePath: String = ""
    @State private var outputFolderPath: String = ""
    @State private var excludeSystemFolders: Bool = true
    @State private var consoleText: String = ""
    @State private var isSearching: Bool = false
    @State private var filesScanned: Int = 0
    @State private var filesCopied: Int = 0
    @State private var startTime: Date = Date()

    func getFileNames(from textFile: URL) -> [String] {
        do {
            let fileContent = try String(contentsOf: textFile, encoding: .utf8)
            let lines = fileContent.split(separator: "\n")
            return lines.map { String($0) }
        } catch {
            print("Error reading file: \(error)")
            return []
        }
    }

    func searchFiles(in directory: URL, names: [String]) -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: excludeSystemFolders ? [.skipsPackageDescendants] : [])
        var foundFiles: [URL] = []

        while let file = enumerator?.nextObject() as? URL {
            if excludeSystemFolders {
                if isSystemFolder(file.path) {
                    enumerator?.skipDescendents()
                    continue
                } else if file.pathComponents.contains(where: { $0.hasPrefix(".") }) && !file.path.starts(with: FileManager.default.homeDirectoryForCurrentUser.path) {
                    continue
                }
                DispatchQueue.main.async {
                    self.filesScanned += 1
                }
            }
            print("Checking file: \(file.lastPathComponent)") // Debugging info
            if names.contains(file.lastPathComponent) {
                foundFiles.append(file)
            }

        }

        return foundFiles
    }

    func isSystemFolder(_ path: String) -> Bool {
        let systemFolders = [
            "/System",
            "/private",
            "/sbin",
            "/usr",
            "/bin",
            "/cores",
            "/etc",
            "/opt",
            "/tmp",
            "/var"
        ]
        return systemFolders.contains { path.starts(with: $0) }
    }





    func copyFiles(_ files: [URL], to destination: URL) {
        let fileManager = FileManager.default
        var failedCopies = 0

        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)

            do {
                try fileManager.copyItem(at: file, to: target)
                DispatchQueue.main.async {
                    self.filesCopied += 1
                }
            } catch {
                print("Error copying file: \(error)")
                failedCopies += 1
            }
        }
        
        DispatchQueue.main.async {
            self.consoleText += "Searched \(self.filesScanned) files\n"
            self.consoleText += "Copied \(self.filesCopied) files\n"

            // Calculate the elapsed time
            let elapsedTime = Date().timeIntervalSince(self.startTime)
            let elapsedTimeFormatted = String(format: "%.2f", elapsedTime)
            self.consoleText += "Time elapsed: \(elapsedTimeFormatted) seconds"
        }

    }



    func startProcessing() {
        consoleText += "Starting file processing...\n"
        startTime = Date() // Record the start time

        guard let inputFileURL = URL(string: "file://" + inputFilePath),
              let outputFolderURL = URL(string: "file://" + outputFolderPath) else {
            consoleText += "Invalid input file or output folder path\n"
            return
        }
        
        isSearching = true // Set isSearching to true when starting the search
        filesScanned = 0 // Reset filesScanned when starting the search
        filesCopied = 0 // Reset filesCopied when starting the search
        DispatchQueue.global(qos: .userInitiated).async {
            let fileNames = self.getFileNames(from: inputFileURL)
            
            // Search in the user's home directory
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            var foundFiles = self.searchFiles(in: homeDirectory, names: fileNames)
            
            // Search in mounted volumes (e.g., external storage devices)
            if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) {
                for volume in volumes {
                    foundFiles.append(contentsOf: self.searchFiles(in: volume, names: fileNames))
                }
            }
            
            self.copyFiles(foundFiles, to: outputFolderURL)
            
            DispatchQueue.main.async {
   }
                self.isSearching = false // Set isSearching to false when the search is complete
            }
        }
    



    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Input File:")
                TextField("Input File", text: $inputFilePath)
                Button("Browse") {
                    browseInputFile()
                }
            }
            
            HStack {
                Text("Output Folder:")
                TextField("Output Folder", text: $outputFolderPath)
                Button("Browse") {
                    browseOutputFolder()
                }
            }
            
            Toggle("Exclude system folders", isOn: $excludeSystemFolders)
            
            Button("Start") {
                startProcessing()
            }
            if isSearching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Text("\(filesScanned) files scanned")
            }

            ScrollView {
                Text(consoleText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
        .padding()
        HStack() {
            Text("Developed by Ben Waco. Source Code: https://github.com/benwaco/FileFinder").padding()
            
        }
    }
    
    func browseInputFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedFileTypes = ["txt"]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                inputFilePath = url.path
            }
        }
    }
    
    func browseOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                outputFolderPath = url.path
            }
        }
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
