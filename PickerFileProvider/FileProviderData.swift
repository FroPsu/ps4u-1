//
//  FileProviderData.swift
//  Files
//
//  Created by Marino Faggiana on 27/05/18.
//  Copyright © 2018 TWS. All rights reserved.
//
//  Author Marino Faggiana <m.faggiana@twsweb.it>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import FileProvider

class FileProviderData: NSObject {
    
    var fileManager = FileManager()
    
    var account = ""
    var accountUser = ""
    var accountUserID = ""
    var accountPassword = ""
    var accountUrl = ""
    var homeServerUrl = ""
    var directoryUser = ""
    
    // Directory
    var groupURL: URL?
    var fileProviderStorageURL: URL?
    
    // metadata Selector
    let selectorPostImportDocument = "importDocument"
    let selectorPostItemChanged = "itemChanged"
    
    // Metadata Temp for Import
    let FILEID_IMPORT_METADATA_TEMP = k_uploadSessionID + "FILE_PROVIDER_EXTENSION"
    
    // Max item for page
    let itemForPage = 20

    // List of etag for serverUrl
    var listServerUrlEtag = [String:String]()
    
    // Anchor
    var currentAnchor: UInt64 = 0

    // Rank favorite
    var listFavoriteIdentifierRank = [String:NSNumber]()
    
    // Queue for trade-safe
    let queueTradeSafe = DispatchQueue(label: "com.nextcloud.fileproviderextension.tradesafe", attributes: .concurrent)

    // Item for signalEnumerator
    var fileProviderSignalDeleteContainerItemIdentifier = [NSFileProviderItemIdentifier:NSFileProviderItemIdentifier]()
    var fileProviderSignalUpdateContainerItem = [NSFileProviderItemIdentifier:FileProviderItem]()
    var fileProviderSignalDeleteWorkingSetItemIdentifier = [NSFileProviderItemIdentifier:NSFileProviderItemIdentifier]()
    var fileProviderSignalUpdateWorkingSetItem = [NSFileProviderItemIdentifier:FileProviderItem]()

    // MARK: - 
    
    func setupActiveAccount() -> Bool {
        
        queueTradeSafe.sync(flags: .barrier) {
            groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NCBrandOptions.sharedInstance.capabilitiesGroups)
            fileProviderStorageURL = groupURL!.appendingPathComponent(k_assetLocalIdentifierFileProviderStorage)
        }
        
        // Create dir File Provider Storage
        do {
            try FileManager.default.createDirectory(atPath: fileProviderStorageURL!.path, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            NSLog("Unable to create directory \(error.debugDescription)")
        }
        
        if CCUtility.getDisableFilesApp() {
            return false
        }
        
        guard let activeAccount = NCManageDatabase.sharedInstance.getAccountActive() else {
            return false
        }
        
        if account != "" && account != activeAccount.account {
            assert(false, "change user")
        }
        
        queueTradeSafe.sync(flags: .barrier) {
            account = activeAccount.account
            accountUser = activeAccount.user
            accountUserID = activeAccount.userID
            accountPassword = activeAccount.password
            accountUrl = activeAccount.url
            homeServerUrl = CCUtility.getHomeServerUrlActiveUrl(activeAccount.url)
            directoryUser = CCUtility.getDirectoryActiveUser(activeAccount.user, activeUrl: activeAccount.url)
        }
        
        return true
    }
    
    func getAccountFromItemIdentifier(_ itemIdentifier: NSFileProviderItemIdentifier) -> String? {
        
        let fileID = itemIdentifier.rawValue
        return NCManageDatabase.sharedInstance.getMetadata(predicate: NSPredicate(format: "account = %@ AND fileID = %@", account, fileID))?.account
    }
    
    func getTableMetadataFromItemIdentifier(_ itemIdentifier: NSFileProviderItemIdentifier) -> tableMetadata? {
        
        let fileID = itemIdentifier.rawValue
        return NCManageDatabase.sharedInstance.getMetadata(predicate: NSPredicate(format: "account = %@ AND fileID = %@", account, fileID))
    }

    func getItemIdentifier(metadata: tableMetadata) -> NSFileProviderItemIdentifier {
        
        return NSFileProviderItemIdentifier(metadata.fileID)
    }
    
    func createFileIdentifierOnFileSystem(metadata: tableMetadata) {
        
        let itemIdentifier = getItemIdentifier(metadata: metadata)
        let identifierPath = fileProviderStorageURL!.path + "/" + itemIdentifier.rawValue
        let fileIdentifier = identifierPath + "/" + metadata.fileName
        
        do {
            try FileManager.default.createDirectory(atPath: identifierPath, withIntermediateDirectories: true, attributes: nil)
        } catch { }
        
        if metadata.directory == false {
            // If do not exists create file with size = 0
            if FileManager.default.fileExists(atPath: fileIdentifier) == false {
                FileManager.default.createFile(atPath: fileIdentifier, contents: nil, attributes: nil)
            }
        }
    }
    
    func getParentItemIdentifier(metadata: tableMetadata) -> NSFileProviderItemIdentifier? {
        
        /* ONLY iOS 11*/
        guard #available(iOS 11, *) else { return NSFileProviderItemIdentifier("") }
        
        if let directory = NCManageDatabase.sharedInstance.getTableDirectory(predicate: NSPredicate(format: "account = %@ AND directoryID = %@", account, metadata.directoryID))  {
            if directory.serverUrl == homeServerUrl {
                return NSFileProviderItemIdentifier(NSFileProviderItemIdentifier.rootContainer.rawValue)
            } else {
                // get the metadata.FileID of parent Directory
                if let metadata = NCManageDatabase.sharedInstance.getMetadata(predicate: NSPredicate(format: "account = %@ AND fileID = %@", account, directory.fileID))  {
                    let identifier = getItemIdentifier(metadata: metadata)
                    return identifier
                }
            }
        }
        
        return nil
    }
    
    func getTableDirectoryFromParentItemIdentifier(_ parentItemIdentifier: NSFileProviderItemIdentifier) -> tableDirectory? {
        
        /* ONLY iOS 11*/
        guard #available(iOS 11, *) else { return nil }
        
        var predicate: NSPredicate
        
        if parentItemIdentifier == .rootContainer {
            
            predicate = NSPredicate(format: "account = %@ AND serverUrl = %@", account, homeServerUrl)
            
        } else {
            
            guard let metadata = getTableMetadataFromItemIdentifier(parentItemIdentifier) else {
                return nil
            }
            predicate = NSPredicate(format: "account = %@ AND fileID = %@", account, metadata.fileID)
        }
        
        guard let directory = NCManageDatabase.sharedInstance.getTableDirectory(predicate: predicate) else {
            return nil
        }
        
        return directory
    }
    
    func copyFile(_ atPath: String, toPath: String) -> Error? {
        
        var errorResult: Error?
        
        if !fileManager.fileExists(atPath: atPath) {
            return NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo:[:])
        }
        
        do {
            try fileManager.removeItem(atPath: toPath)
        } catch let error {
            print("error: \(error)")
        }
        do {
            try fileManager.copyItem(atPath: atPath, toPath: toPath)
        } catch let error {
            errorResult = error
        }
        
        return errorResult
    }
    
    func moveFile(_ atPath: String, toPath: String) -> Error? {
        
        var errorResult: Error?
        
        if !fileManager.fileExists(atPath: atPath) {
            return NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo:[:])
        }
        
        do {
            try fileManager.removeItem(atPath: toPath)
        } catch let error {
            print("error: \(error)")
        }
        do {
            try fileManager.moveItem(atPath: atPath, toPath: toPath)
        } catch let error {
            errorResult = error
        }
        
        return errorResult
    }
    
    func deleteFile(_ atPath: String) -> Error? {
        
        var errorResult: Error?
        
        do {
            try fileManager.removeItem(atPath: atPath)
        } catch let error {
            errorResult = error
        }
        
        return errorResult
    }
}
