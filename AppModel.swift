import Foundation
import SwiftUI
import Combine

@MainActor
final class AppModel: ObservableObject {

    @Published var projects: [Project]
    @Published var project: Project
    @Published var currentStep: Int

    init(projects: [Project] = [], project: Project? = nil, currentStep: Int = 1) {
        if let p = project {
            self.project = p
            self.projects = [p]
        } else if let first = projects.first {
            self.projects = projects
            self.project = first
        } else {
            let p = Project(name: "Untitled Project")
            self.projects = [p]
            self.project = p
        }
        self.currentStep = currentStep
    }

    func setOutputPath(_ url: URL?) {
        project.outputPath = url
        objectWillChange.send()
    }

    func saveCaptionTxt(to url: URL) throws {
        try project.caption.write(to: url, atomically: true, encoding: .utf8)
    }

    // FIXED: Load images from selected folders while preserving existing state
    func loadImagesFromSelectedFolders() {
        let allowedExt: Set<String> = ["jpg","jpeg","png","heic","heif","tiff","bmp","gif"]
        
        // Create a lookup of existing images by URL for state preservation
        var existingImagesByURL: [URL: ProjectImage] = [:]
        for img in project.images {
            existingImagesByURL[img.url] = img
        }
        
        var collected: [ProjectImage] = []
        var order = 0

        for folder in project.selectedFolders {
            if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in files {
                    let ext = url.pathExtension.lowercased()
                    if allowedExt.contains(ext) {
                        // Check if this image already exists
                        if var existingImage = existingImagesByURL[url] {
                            // Preserve existing state but update order
                            existingImage.orderIndex = order
                            collected.append(existingImage)
                        } else {
                            // Create new image
                            collected.append(ProjectImage(url: url, orderIndex: order, disabled: false))
                        }
                        order += 1
                    }
                }
            }
        }

        // Only sort by filename if we don't have a custom order
        if !project.hasCustomOrder {
            collected.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
            for i in collected.indices { collected[i].orderIndex = i }
        }

        project.images = collected
        objectWillChange.send()
    }

    func enableImage(_ id: UUID, enabled: Bool) {
        if let idx = project.images.firstIndex(where: { $0.id == id }) {
            project.images[idx].disabled = !enabled
        }
    }

    func moveImage(from: Int, to: Int) {
        guard project.images.indices.contains(from),
              project.images.indices.contains(to) else { return }
        var imgs = project.images
        let item = imgs.remove(at: from)
        imgs.insert(item, at: to)
        for i in imgs.indices { imgs[i].orderIndex = i }
        project.images = imgs
        project.hasCustomOrder = true // Mark that we have a custom order
        objectWillChange.send()
    }
    
    // Set crop offset for repositioning
    func setCropOffset(for id: UUID, offsetX: Double, offsetY: Double) {
        if let idx = project.images.firstIndex(where: { $0.id == id }) {
            project.images[idx].offsetX = offsetX
            project.images[idx].offsetY = offsetY
            objectWillChange.send()
        }
    }
    
    // Set aspect ratio and persist it
    func setAspectRatio(_ aspect: AspectPreset) {
        project.aspect = aspect
        objectWillChange.send()
    }
    
    // NEW: Toggle crop functionality
    func setCropEnabled(_ enabled: Bool) {
        project.cropEnabled = enabled
        objectWillChange.send()
    }
}
