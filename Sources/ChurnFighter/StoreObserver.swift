//
//  StoreObserver.swift
//  ChurnFighter
//
//  Created by Bastien Cojan on 21/11/2019.
//  Copyright © 2019 Bastien Cojan. All rights reserved.
//

import Foundation
import StoreKit

class StoreObserver: NSObject, SKPaymentTransactionObserver {

    //Initialize the store observer.
    public var delegate: ChurnFighter?

    //Observe transaction updates.
    func paymentQueue(_ queue: SKPaymentQueue,updatedTransactions transactions: [SKPaymentTransaction]) {
        
        //Handle transaction states here.
        for transaction in transactions {
            
            if let originalTransaction=transaction.original,
                let originalTransactionIdentifier = originalTransaction.transactionIdentifier {
                delegate?.addOriginalTransactionId(originalTransactionIdentifier)
            }
            
            switch transaction.transactionState {
                case .purchasing: break
                // Do not block your UI. Allow the user to continue using your app.
                case .deferred:
                    print("deferred")
                    break
                // The purchase was successful.
                case .purchased:
                    delegate?.loadReceipt()
                    print("purchased")
                    break
                // The transaction failed.
                case .failed:
                    print("failed")
                    break
                // There are restored products.
                case .restored:
                    delegate?.loadReceipt()
                    print("restored")
                    break
                @unknown default:
                    fatalError("unknownDefault")
            }
        }
    }
}
