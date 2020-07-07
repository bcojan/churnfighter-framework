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

@objc
public protocol Action: NSObjectProtocol {
    var title: String { get }
    var body: String { get }
}

@objcMembers
public class Offer: NSObject, Action, Decodable {
    public let title: String
    public let body: String
    public let productId: String
    public let offerId: String?
    public let offerType: String
    public let productDescription: String?
}

@objcMembers
public class UpdatePaymentDetails: NSObject, Action , Decodable {
    public let title: String
    public let body: String
    public let cta: String
    public let url: String
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
    public func actionFromNotificationResponse(response: UNNotificationResponse) -> Action? {
        
        let userInfo = response.notification.request.content.userInfo
        
        if let encodedOffer = userInfo["offer"] as? String,
            let offer = decodeOffer(encodedOffer: encodedOffer)  {
            
            return offer
        }
        
        if let encodedUpdatePaymentDetails = userInfo["payment"] as? String,
            let updatePaymentDetails = decodeUpdatePaymentDetails(encodedUpdatepaymentDetails: encodedUpdatePaymentDetails) {
            
            return updatePaymentDetails
        }
        
        return nil
    }
    
    
    @objc
    public func actionFromUniversalLink(userActivity: NSUserActivity) -> Action? {
        
        // Get URL components from the incoming user activity
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let incomingURL = userActivity.webpageURL,
            let components = NSURLComponents(url: incomingURL, resolvingAgainstBaseURL: true),
            let params = components.queryItems else {
                
                return nil
        }

        if let offer = params.first(where: {$0.name == "offer"}),
            let encodedOffer = offer.value,
            let decodedOffer = decodeOffer(encodedOffer: encodedOffer) {
            
            return decodedOffer
        }
        
        if let updatePaymentDetails = params.first(where: {$0.name == "payment"}),
            let encodedUpdatePaymentDetails = updatePaymentDetails.value,
            let decodedUpdatePaymentDetails = decodeUpdatePaymentDetails(encodedUpdatepaymentDetails: encodedUpdatePaymentDetails) {
            
            return decodedUpdatePaymentDetails
        }
        
        return nil
    }
    
    @available(iOS 12.2, *)
    public func prepareOffer(usernameHash: String, productIdentifier: String, offerIdentifier: String, completion: @escaping(SKPaymentDiscount) -> Void) {

        // Make a secure request to your server, providing the username, product, and discount data
        // Your server will use these values to generate the signature and return it, along with the nonce, timestamp, and key identifier that it uses to generate the signature.
        
        let jsonObject = ["applicationUsername": usernameHash,
                          "productIdentifier": productIdentifier,
                          "offerIdentifier": offerIdentifier];
        
        if let json = try? JSONSerialization.data(withJSONObject: jsonObject, options: []) {

//            let userId = userID()
            if let url = URL(string: "https://api.churnfighter.io/subscriptionOfferSignature/2uUsRHeoRWLo61K0BU55")
            {
                httpPost(url: url, jsonData: json) { (data, urlResponse, error) in

                    if let result = try? JSONSerialization.jsonObject(with: data!, options: []) as? [String:AnyObject],
//                        let identifier = result["productIdentifier"] as? String,
                        let keyIdentifier = result["keyIdentifier"] as? String,
                        let nonceString = result["nonce"] as? String,
                        let nonce = UUID(uuidString: nonceString) ,
                        let signature = result["signature"] as? String,
                        let timestamp = result["timestamp"] as? Int {

                        let discountOffer = SKPaymentDiscount(identifier: offerIdentifier,
                                                              keyIdentifier: keyIdentifier,
                                                              nonce: nonce,
                                                              signature: signature,
                                                              timestamp: NSNumber(value: timestamp))
                        completion(discountOffer)

                    }
                }
            }
        }
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
        
            httpPost(url: url, jsonData: userInfoData, completion: {_,_,_ in })
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
            
                httpPost(url: url, jsonData: json, completion: {_,_,_ in })
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

    func httpPost(url: URL, jsonData: Data, completion:  @escaping (Data?, URLResponse?, Error?) -> Void) {
        guard let apiKey=apiKey,
            let secret=secret,
            !jsonData.isEmpty else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue(secret, forHTTPHeaderField: "X-CF-header")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request, completionHandler:completion)
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
        let offer =  try? JSONDecoder().decode(Offer.self, from: data)
        else { return nil }
            
        return offer
    }

    func decodeUpdatePaymentDetails(encodedUpdatepaymentDetails: String) -> UpdatePaymentDetails? {
        
        guard let data = Data(base64Encoded: encodedUpdatepaymentDetails),
            let updatePaymentDetails =  try? JSONDecoder().decode(UpdatePaymentDetails.self, from: data)
        else { return nil }
            
        return updatePaymentDetails
    }
}
