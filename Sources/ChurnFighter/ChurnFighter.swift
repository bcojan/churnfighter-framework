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
    let customInfo: [String:String]?
}


public class Offer: NSObject, Decodable {
//    public struct Product: Decodable {
//        public let productId: String
//        public let description: String?
//    }
    public let title: String
    public let body: String
    public let productId: String
    public let productDescription: String?
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
    private var customInfo: [String: String] = [:]
    
    private let userDefaults = UserDefaults(suiteName: "churnFighter")
    private let userHashKey="userHash"
    private let receiptHashKey="receiptHash"
    private let userIdKey="userIdKey"
    
    @objc
    public func initialize(apiKey: String, secret: String) {
        
        self.storeObserver = StoreObserver()
        self.apiKey = apiKey
        self.secret = secret
        addIAPObserver()
        loadReceipt()
    }
    
    @objc
    public func cleanup(){
        removeIAPObserver()
    }
    
    @objc
    public func setUserEmail(_ email: String) {
        
        self.email = email
        uploadToServer()
    }
    
    @objc
    public func setUserLocale(_ locale: Locale) {

        self.locale = locale
        uploadToServer()
    }
    
    @objc
    public func setUserProperty(key: String, value: String) {

        customInfo[key] = value
        uploadToServer()
    }
    
    @objc
    public func didRegisterForRemoteNotificationsWithDeviceToken(_ deviceToken: Data) {
     
        self.deviceToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        uploadToServer()
    }
    
    @objc
    public func offerFromNotificationResponse(response: UNNotificationResponse) -> Offer? {
        let userInfo = response.notification.request.content.userInfo
        guard let encodedOffer = userInfo["offer"] as? String,
            let offer = decodeOffer(encodedOffer: encodedOffer) else { return nil }
        
        return offer
    }
    
    @objc
    public func offerFromUniversalLink(userActivity: NSUserActivity) -> Offer? {
        
        // Get URL components from the incoming user activity
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let incomingURL = userActivity.webpageURL,
           let components = NSURLComponents(url: incomingURL, resolvingAgainstBaseURL: true) else {
           return nil
        }

        guard
            let params = components.queryItems,
            let offer = params.first(where: {$0.name == "offer"}),
            let encodedOffer = offer.value,
            let decodedOffer = decodeOffer(encodedOffer: encodedOffer) else { return nil }
        
        return decodedOffer
    }
    
    
    // INTERNAL
    
    func setOriginalTransactionId(originalTransactionId: String){
        self.originalTransactionId = originalTransactionId
        uploadToServer()
    }
    
    internal func uploadToServer() {
    
        let userInfo = generateUserInfo()
        let userHash = getUserHash(userInfo: userInfo)
        
        if let previousUserHash = userDefaults?.integer(forKey: userHashKey),
            userHash == previousUserHash {
             
            return
        }
        
        print(userInfo)
        
        let userId = userID()
        if let url = URL(string: "https://api.churnfighter.io/user/\(userId)"),
            let userInfoData = try?JSONEncoder().encode(userInfo) {
        
            httpPost(url: url, jsonData: userInfoData)
            userDefaults?.set(userHash, forKey: userHashKey)
        }
    }
    
    
    internal func loadReceipt() {
        
        guard let deviceReceiptString = receiptString() else {
            
            return
        }
        let receiptHash = getReceiptHash(receipt: deviceReceiptString)
        
        if let previousReceiptHash = userDefaults?.integer(forKey: receiptHashKey),
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
      
    func addIAPObserver() {
           
           if let storeObserver=storeObserver {
               storeObserver.delegate = self
               SKPaymentQueue.default().add(storeObserver)
           }
       }
       

    func removeIAPObserver() {
       
       if let storeObserver=storeObserver {
           storeObserver.delegate = nil
           SKPaymentQueue.default().remove(storeObserver)
       }
    }

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
    
    func getReceiptHash(receipt: String)->Int {
        
        var hash = Hasher()
        hash.combine(receipt)
        return hash.finalize()
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
                                    originalTransactionId: originalTransactionId,
                                    customInfo: customInfo)
        #elseif os(OSX)
            let userInfo = UserInfo(locale: userLocaleIdentifier,
                                    iosVersion: "macosx",
                                    model: "NA",
                                    identifierForVendor: nil,
                                    timeZone: TimeZone.current.identifier,
                                    email: email,
                                    deviceToken: deviceToken,
                                    originalTransactionId: originalTransactionId,
                                    customInfo: customInfo)
        #endif
        
        
        return userInfo
    }
    
    func receiptString() -> String? {
         
       guard
        let receiptUrl = Bundle.main.appStoreReceiptURL,
        let receiptData = try? Data(contentsOf: receiptUrl, options: .alwaysMapped) else { return nil }
       
       return receiptData.base64EncodedString()
    }
    
    func decodeOffer(encodedOffer: String) -> Offer? {
        
        guard let data = Data(base64Encoded: encodedOffer),
//            let decodedOffer = String(data: data, encoding: .utf8),
        let offer =  try? JSONDecoder().decode(Offer.self, from: data) else { return nil}
        
        return offer
    }
}
