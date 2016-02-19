//  The MIT License (MIT)
//
//  Copyright (c) 2015 Sándor Gyulai
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import UIKit
import StoreKit

let kIAPPurchasedNotification = "IAPPurchasedNotification"
let kIAPFailedNotification = "IAPFailedNotification"

public class InAppFw: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver{
    
    public static let sharedInstance = InAppFw()
    
    var productIdentifiers: Set<String>?
    var productsRequest: SKProductsRequest?
    
    var completionHandler: ((success: Bool, products: [SKProduct]?) -> Void)?
    
    var purchasedProductIdentifiers = Set<String>()
    
    private var hasValidReceipt = false
    
    public override init() {
        super.init()
        SKPaymentQueue.defaultQueue().addTransactionObserver(self)
        productIdentifiers = Set<String>()
    }
    
    /**
        Add a single product ID
    
        - Parameter id: Product ID in string format
    */
    public func addProductId(id: String) {
        productIdentifiers?.insert(id)
    }
    
    /**
        Add multiple product IDs
    
        - Parameter ids: Set of product ID strings you wish to add
    */
    public func addProductIds(ids: Set<String>) {
        productIdentifiers?.unionInPlace(ids)
    }
    
    /**
        Load purchased products
    
        - Parameter checkWithApple: True if you want to validate the purchase receipt with Apple servers
    */
    public func loadPurchasedProducts(checkWithApple: Bool, completion: ((valid: Bool) -> Void)?) {
        
        if let productIdentifiers = productIdentifiers {
            
            for productIdentifier in productIdentifiers {
                
                let isPurchased = NSUserDefaults.standardUserDefaults().boolForKey(productIdentifier)
                
                if isPurchased {
                    purchasedProductIdentifiers.insert(productIdentifier)
                    print("Purchased: \(productIdentifier)")
                } else {
                    print("Not purchased: \(productIdentifier)")
                }
                
            }
            
            if checkWithApple {
                print("Checking with Apple...")
                if let completion = completion {
                    validateReceipt(false, completion: completion)
                } else {
                    validateReceipt(false) { (valid) -> Void in
                        if valid { print("Receipt is Valid!") } else { print("BEWARE! Reciept is not Valid!!!") }
                    }
                }
            }
            
        }
        
    }
    
    private func validateReceipt(sandbox: Bool, completion:(valid: Bool) -> Void) {
        
        let url = NSBundle.mainBundle().appStoreReceiptURL
        let receipt = NSData(contentsOfURL: url!)
        
        if let r = receipt {
            
            let receiptData = r.base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
            let requestContent = [ "receipt-data" : receiptData ]
            
            do {
                let requestData = try NSJSONSerialization.dataWithJSONObject(requestContent, options: NSJSONWritingOptions())
                
                let storeURL = NSURL(string: "https://buy.itunes.apple.com/verifyReceipt")
                let sandBoxStoreURL = NSURL(string: "https://sandbox.itunes.apple.com/verifyReceipt")
                
                let finalURL = sandbox ? sandBoxStoreURL : storeURL
                
                let storeRequest = NSMutableURLRequest(URL: finalURL!)
                storeRequest.HTTPMethod = "POST"
                storeRequest.HTTPBody = requestData
                
                let task = NSURLSession.sharedSession().dataTaskWithRequest(storeRequest, completionHandler: { (data, response, error) -> Void in
                    if (error != nil) {
                        print("Validation Error: \(error)")
                        self.hasValidReceipt = false
                        completion(valid: false)
                    } else {
                        self.checkStatus(data, completion: completion)
                    }
                })
                
                task.resume()
                
            } catch {
                print("validateReceipt: Caught error")
            }
            
        } else {
            hasValidReceipt = false
            completion(valid: false)
        }
        
    }
    
    private func checkStatus(data: NSData?, completion:(valid: Bool) -> Void) {
        do {
            if let data = data, let jsonResponse: AnyObject = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) {
                
                if let status = jsonResponse["status"] as? Int {
                    if status == 0 {
                        print("Status: VALID")
                        hasValidReceipt = true
                        completion(valid: true)
                    } else if status == 21007 {
                        print("Status: CHECK WITH SANDBOX")
                        validateReceipt(true, completion: completion)
                    } else {
                        print("Status: INVALID")
                        hasValidReceipt = false
                        completion(valid: false)
                    }
                }
                
            }
        } catch {
            print("checkStatus: Caught error")
        }
    }
    
    /**
        Request products from Apple
    */
    public func requestProducts(completionHandler: (success:Bool, products:[SKProduct]?) -> Void) {
        self.completionHandler = completionHandler
        
        print("Requesting Products")
        
        if let productIdentifiers = productIdentifiers {
            productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
            productsRequest!.delegate = self
            productsRequest!.start()
        } else {
            print("No productIdentifiers")
            completionHandler(success: false, products: nil)
        }
    }
    
    /**
        Initiate purchase for the product
    
        - Parameter product: The product you want to purchase
    */
    public func purchaseProduct(product: SKProduct) {
        print("Purchasing product: \(product.productIdentifier)")
        let payment = SKPayment(product: product)
        SKPaymentQueue.defaultQueue().addPayment(payment)
    }
    
    /**
        Check if the product with identifier is already purchased
    */
    public func productPurchased(productIdentifier: String) -> (isPurchased: Bool, hasValidReceipt: Bool) {
        let purchased = purchasedProductIdentifiers.contains(productIdentifier)
        return (purchased, hasValidReceipt)
    }
    
    /**
        Begin to start restoration of already purchased products
    */
    public func restoreCompletedTransactions() {
        SKPaymentQueue.defaultQueue().restoreCompletedTransactions()
    }
    
    //MARK: - Transactions
    
    private func completeTransaction(transaction: SKPaymentTransaction) {
        print("Complete Transaction...")
        
        provideContentForProductIdentifier(transaction.payment.productIdentifier)
        SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    }
    
    private func restoreTransaction(transaction: SKPaymentTransaction) {
        print("Restore Transaction...")
        
        provideContentForProductIdentifier(transaction.originalTransaction!.payment.productIdentifier)
        SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    }
    
    private func failedTransaction(transaction: SKPaymentTransaction) {
        print("Failed Transaction...")
        
        if (transaction.error!.code != SKErrorPaymentCancelled) {
            print("Transaction error \(transaction.error!.code): \(transaction.error!.localizedDescription)")
        }
        
        SKPaymentQueue.defaultQueue().finishTransaction(transaction)
        NSNotificationCenter.defaultCenter().postNotificationName(kIAPFailedNotification, object: nil, userInfo: nil)
    }
    
    private func provideContentForProductIdentifier(productIdentifier: String!) {
        purchasedProductIdentifiers.insert(productIdentifier)
        
        NSUserDefaults.standardUserDefaults().setBool(true, forKey: productIdentifier)
        NSUserDefaults.standardUserDefaults().synchronize()
        
        NSNotificationCenter.defaultCenter().postNotificationName(kIAPPurchasedNotification, object: productIdentifier, userInfo: nil)
    }
    
    // MARK: - Delegate Implementations
    
    public func paymentQueue(queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction:AnyObject in transactions
        {
            if let trans = transaction as? SKPaymentTransaction
            {
                switch trans.transactionState {
                case .Purchased:
                    completeTransaction(trans)
                    break
                case .Failed:
                    failedTransaction(trans)
                    break
                case .Restored:
                    restoreTransaction(trans)
                    break
                default:
                    break
                }
            }
        }
    }
    
    public func productsRequest(request: SKProductsRequest, didReceiveResponse response: SKProductsResponse) {

        print("Loaded product list!")
        
        productsRequest = nil
        
        let skProducts = response.products
        
        for skProduct in skProducts  {
            print("Found product: \(skProduct.productIdentifier) - \(skProduct.localizedTitle) - \(skProduct.price)")
        }
        
        if let completionHandler = completionHandler {
            completionHandler(success: true, products: skProducts)
        }
        
        completionHandler = nil

    }
    
    public func request(request: SKRequest, didFailWithError error: NSError) {
        print("Failed to load list of products!")
        productsRequest = nil
        if let completionHandler = completionHandler {
            completionHandler(success: false, products: nil)
        }
        completionHandler = nil
    }
    
    //MARK: - Helpers
    
    /**
        Check if the user can make purchase
    */
    public func canMakePurchase() -> Bool {
        return SKPaymentQueue.canMakePayments()
    }
    
    //MARK: - Class Functions
    
    /**
        Format the price for the given locale
    
        - Parameter price:  The price you want to format
        - Parameter locale: The price locale you want to format with
    
        - Returns: The formatted price
    */
    public class func formatPrice(price: NSNumber, locale: NSLocale) -> String {
        var formattedString = ""
        
        let numberFormatter = NSNumberFormatter()
        numberFormatter.formatterBehavior = NSNumberFormatterBehavior.Behavior10_4
        numberFormatter.numberStyle = NSNumberFormatterStyle.CurrencyStyle
        numberFormatter.locale = locale
        formattedString = numberFormatter.stringFromNumber(price)!
        
        return formattedString
    }
    
}