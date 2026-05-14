//
//  CloudStorageService.swift
//  Session Proof
//
//  Created by Ian Miller on 5/9/26.
//

import Foundation
import FirebaseStorage

enum UploadError: LocalizedError {
    case fileNotFound
    case uploadFailed(String)
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}

@Observable
class CloudStorageService {
    var uploadProgress: Double = 0.0
    var downloadProgress: Double = 0.0
    var isUploading = false
    var isDownloading = false
    
    private let storage = Storage.storage()
    
    // MARK: - Upload Mix
    
    func uploadMix(
        projectId: String,
        songId: String,
        mixId: String,
        fileURL: URL
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.fileNotFound
        }
        
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.0
        }
        
        // Create storage reference
        let fileName = fileURL.lastPathComponent
        let storagePath = "projects/\(projectId)/songs/\(songId)/mixes/\(mixId)/\(fileName)"
        let storageRef = storage.reference().child(storagePath)
        
        // Upload file
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "audio/wav" // Adjust based on file type
            
            let _ = try await storageRef.putFileAsync(from: fileURL, metadata: metadata) { progress in
                if let progress = progress {
                    Task { @MainActor in
                        self.uploadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    }
                }
            }
            
            // Get download URL
            let downloadURL = try await storageRef.downloadURL()
            
            await MainActor.run {
                isUploading = false
                uploadProgress = 1.0
            }
            
            return downloadURL.absoluteString
            
        } catch {
            await MainActor.run {
                isUploading = false
            }
            throw UploadError.uploadFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Download Mix
    
    func downloadMix(
        downloadURL: String,
        destinationURL: URL
    ) async throws {
        guard URL(string: downloadURL) != nil else {
            throw UploadError.downloadFailed("Invalid download URL")
        }
        
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }
        
        let storageRef = storage.reference(forURL: downloadURL)
        
        do {
            let _ = try await storageRef.writeAsync(toFile: destinationURL) { progress in
                if let progress = progress {
                    Task { @MainActor in
                        self.downloadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    }
                }
            }
            
            await MainActor.run {
                isDownloading = false
                downloadProgress = 1.0
            }
            
        } catch {
            await MainActor.run {
                isDownloading = false
            }
            throw UploadError.downloadFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Delete Mix
    
    func deleteMix(downloadURL: String) async throws {
        let storageRef = storage.reference(forURL: downloadURL)
        try await storageRef.delete()
    }
    
    // MARK: - Upload Voice Note
    
    func uploadVoiceNote(
        projectId: String,
        commentId: String,
        fileURL: URL
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.fileNotFound
        }
        
        let fileName = fileURL.lastPathComponent
        let storagePath = "projects/\(projectId)/comments/\(commentId)/\(fileName)"
        let storageRef = storage.reference().child(storagePath)
        
        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"
        
        let _ = try await storageRef.putFileAsync(from: fileURL, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
}

// MARK: - Storage Reference Extensions

extension StorageReference {
    func putFileAsync(
        from fileURL: URL,
        metadata: StorageMetadata? = nil,
        onProgress: ((Progress?) -> Void)? = nil
    ) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            let uploadTask = self.putFile(from: fileURL, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                }
            }
            
            uploadTask.observe(.progress) { snapshot in
                onProgress?(snapshot.progress)
            }
        }
    }
    
    func writeAsync(
        toFile fileURL: URL,
        onProgress: ((Progress?) -> Void)? = nil
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let downloadTask = self.write(toFile: fileURL) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                }
            }
            
            downloadTask.observe(.progress) { snapshot in
                onProgress?(snapshot.progress)
            }
        }
    }
}
