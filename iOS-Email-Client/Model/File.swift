//
//  File.swift
//  iOS-Email-Client
//
//  Created by Daniel Tigse on 4/4/18.
//  Copyright © 2018 Criptext Inc. All rights reserved.
//

import Foundation
import RealmSwift

class File : Object {
    
    @objc dynamic var token = ""
    @objc dynamic var name = ""
    @objc dynamic var size = 0
    @objc dynamic var status = 0
    @objc dynamic var date = Date()
    @objc dynamic var readOnly = 0
    @objc dynamic var emailId = ""
    @objc dynamic var isUploaded = false
    @objc dynamic var mimeType = ""
    @objc dynamic var filePath = ""
    var progress = -1
    var filepath = ""
    var chunksProgress = [Int]()
    var requestType: CriptextFileManager.RequestType = .upload
    var requestStatus: uploadStatus = .none

    override static func primaryKey() -> String? {
        return "token"
    }
    
    override static func ignoredProperties() -> [String] {
        return ["progress", "filepath", "chunksProgress", "requestStatus", "requestType"]
    }
    
    func prettyPrintSize() -> String {
        let mySize = Float(size)
        guard mySize >= 1000 else {
            return "\(String(format: "%.2f", mySize)) Bytes"
        }
        guard mySize >= 1000000 else {
            return "\(String(format: "%.2f", mySize/1000)) KB"
        }
        guard mySize >= 1000000000 else {
            return "\(String(format: "%.2f", mySize/1000000)) MB"
        }
        return "\(String(format: "%.2f", mySize/1000000000)) GB"
    }
    
    enum uploadStatus {
        case none
        case pending
        case processing
        case finish
        case failed
    }
}
