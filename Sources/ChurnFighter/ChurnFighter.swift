//
//  ChurnFighter.swift
//  ChurnFighter
//
//  Created by Bastien Cojan on 21/11/2019.
//  Copyright © 2019 Bastien Cojan. All rights reserved.
//

import Foundation
import StoreKit
import CommonCrypto

struct UserInfo: Encodable, Hashable {
    let locale: String?
    let iosVersion: String?
    let model: String?
    let identifierForVendor: UUID?
    let timeZone: String?
    let email: String?
    let deviceToken: String?
    let originalTransactionId: String?
}

@objc
public class ChurnFighter: NSObject {
    
    private var storeObserver: StoreObserver?
    private var apiKey: String?
    private var secret: String?
    private var email: String?
    private var locale: Locale?
    private var deviceToken: String?
    private var originalTransactionId: String?
    
    private let userDefaults = UserDefaults(suiteName: "churnFighter")
    private let userHashKey="userHash"
    private let receiptHashKey="receiptHash"
    private let userIdKey="userIdKey"
    

    public func initialize(apiKey: String, secret: String) {
        
        self.storeObserver = StoreObserver()
        self.apiKey = apiKey
        self.secret = secret
    }
    
    public func addIAPObserver() {
        
        if let storeObserver=storeObserver {
            storeObserver.delegate = self
            SKPaymentQueue.default().add(storeObserver)
        }
    }
    
    public func removeIAPObserver() {
        
        if let storeObserver=storeObserver {
            storeObserver.delegate = nil
            SKPaymentQueue.default().remove(storeObserver)
        }
    }
    
    public func setUserEmail(_ email: String) {
        
        self.email = email
        uploadToServer()
    }
    
    public func setUserLocale(_ locale: Locale) {

        self.locale = locale
        uploadToServer()
    }
    
    public func didRegisterForRemoteNotificationsWithDeviceToken(_ deviceToken: Data) {
     
        self.deviceToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        uploadToServer()
    }
    
    
    // INTERNAL
    internal func setOriginalTransactionId(_ transactionId: String) {
        
        self.originalTransactionId = transactionId
        uploadToServer()
    }
    
    internal func uploadToServer() {
    
        let userInfo = generateUserInfo()
        let userHash = getUserHash(userInfo: userInfo)
        
        if let previousUserHash = userDefaults?.integer(forKey: userHashKey),
            userHash == previousUserHash {
             
            return
        }
        
        let userId = userID()
        if let url = URL(string: "https://api.churnfighter.io/user/\(userId)"),
            let userInfoData = try?JSONEncoder().encode(userInfo) {
        
            httpPost(url: url, jsonData: userInfoData)
            userDefaults?.set(userHash, forKey: userHashKey)
        }
    }
    
    
    internal func loadReceipt() {
        
        guard let deviceReceiptString = receiptString(),
            let receiptHash = getReceiptHash(receipt: deviceReceiptString) else {
                
                return
        }
        
        if let previousReceiptHash = userDefaults?.string(forKey: receiptHashKey),
            previousReceiptHash == receiptHash {
            
            return
        }
        
        let jsonObject = ["receipt": deviceReceiptString]
        if let json = try? JSONSerialization.data(withJSONObject: jsonObject, options: []) {

            let userId = userID()
            if let url = URL(string: "https://api.churnfighter.io/receipt/\(userId)")
            {
            
                httpPost(url: url, jsonData: json)
                userDefaults?.setValue(receiptHash, forKey: receiptHashKey)
            }
        }
    }
}

private extension ChurnFighter {
        
    func httpPost(url: URL, jsonData: Data) {
        guard let apiKey=apiKey,
            let secret=secret,
            !jsonData.isEmpty else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue(secret, forHTTPHeaderField: "X-CF-header")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request, completionHandler: { (responseData: Data?, response: URLResponse?, error: Error?) in
            if let error = error {
                print(error.localizedDescription)
            }
        })
        task.resume()
    }
    
     func userID() -> String {
        
        if let userDefaults = userDefaults,
            let userId = userDefaults.string(forKey: userIdKey)  {
            return userId
        }

        let uuid = UUID().uuidString
        userDefaults?.set(uuid, forKey:userIdKey)
        return uuid
    }
    
    func getUserHash(userInfo: UserInfo)->Int {
        var hash = Hasher()
        hash.combine(userInfo)
        hash.combine(userID())
        return hash.finalize()
    }
    
    func getReceiptHash(receipt: String)->String? {
        
        guard let data = receipt.data(using: .utf8) else { return nil }

        let hash = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash: [UInt8] = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }

        let hashString = hash.map { String(format: "%02x", $0) }.joined()

        return hashString
    }
    
    func generateUserInfo() -> UserInfo {
        var userLocaleIdentifier = Locale.current.identifier
        if let locale = locale {
            userLocaleIdentifier = locale.identifier
        }
        
        #if os(iOS) || os(watchOS) || os(tvOS)
            let userInfo = UserInfo(locale: userLocaleIdentifier,
                                    iosVersion: UIDevice.current.systemVersion,
                                    model: UIDevice.current.localizedModel,
                                    identifierForVendor: UIDevice.current.identifierForVendor,
                                    timeZone: TimeZone.current.identifier,
                                    email: email,
                                    deviceToken: deviceToken,
                                    originalTransactionId: originalTransactionId)
        #elseif os(OSX)
            let userInfo = UserInfo(locale: userLocaleIdentifier,
                                    iosVersion: "macosx",
                                    model: "NA",
                                    identifierForVendor: nil,
                                    timeZone: TimeZone.current.identifier,
                                    email: email,
                                    deviceToken: deviceToken,
                                    originalTransactionId: originalTransactionId)
        #endif
        
        
        return userInfo
    }
    
    func receiptString() -> String? {
         
       guard
        let receiptUrl = Bundle.main.appStoreReceiptURL,
        let receiptData = try? Data(contentsOf: receiptUrl, options: .alwaysMapped) else { return nil }
       
       return receiptData.base64EncodedString()
    }
}
