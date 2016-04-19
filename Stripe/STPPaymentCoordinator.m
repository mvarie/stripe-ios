//
//  STPPaymentCoordinator.m
//  Stripe
//
//  Created by Jack Flintermann on 4/6/16.
//  Copyright © 2016 Stripe, Inc. All rights reserved.
//

#import <PassKit/PassKit.h>
#import <objc/runtime.h>
#import "Stripe+ApplePay.h"
#import "STPPaymentCoordinator.h"
#import "STPAPIClient.h"

@interface STPPaymentCoordinator()<PKPaymentAuthorizationViewControllerDelegate>
@property(nonatomic)UIViewController *paymentViewController;
@property(nonatomic)PKPaymentRequest *paymentRequest;
@property(nonatomic)STPAPIClient *apiClient;
@property(nonatomic, weak)id<STPPaymentCoordinatorDelegate> delegate;
@property(nonatomic)NSError *lastApplePayError;
@property(nonatomic)BOOL applePaySucceeded;
@end

static char kSTPPaymentCoordinatorAssociatedObjectKey;

@implementation STPPaymentCoordinator

- (instancetype)initWithPaymentRequest:(PKPaymentRequest *)paymentRequest
                        apiAdapter:(__unused id<STPBackendAPIAdapter>)apiAdapter
                             apiClient:(STPAPIClient *)apiClient
                              delegate:(id<STPPaymentCoordinatorDelegate>)delegate {
    NSCAssert(paymentRequest != nil, @"You must provide a paymentRequest to STPPaymentCoordinator");
    NSCAssert(apiClient != nil, @"You must provide an apiClient to STPPaymentCoordinator");
    NSCAssert(delegate != nil, @"You must provide a delegate to STPPaymentCoordinator");
    self = [super init];
    if (self) {
        _paymentRequest = paymentRequest;
        _apiClient = apiClient;
        _delegate = delegate;
        if ([Stripe canSubmitPaymentRequest:paymentRequest]) {
            PKPaymentAuthorizationViewController *paymentViewController = [[PKPaymentAuthorizationViewController alloc] initWithPaymentRequest:paymentRequest];
            paymentViewController.delegate = self;
            _paymentViewController = paymentViewController;
        } else {
            // TODO
        }
        [self artificiallyRetain];
    }
    return self;
}

- (void)artificiallyRetain {
    if (self.delegate) {
        objc_setAssociatedObject(self.delegate, &kSTPPaymentCoordinatorAssociatedObjectKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)artificiallyRelease {
    if (self.delegate) {
        objc_setAssociatedObject(self.delegate, &kSTPPaymentCoordinatorAssociatedObjectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - PKPaymentAuthorizationViewControllerDelegate

- (void)paymentAuthorizationViewControllerDidFinish:(__unused PKPaymentAuthorizationViewController *)controller {
    if (self.lastApplePayError) {
        [self.delegate paymentCoordinator:self didFailWithError:self.lastApplePayError];
    } else if (self.applePaySucceeded) {
        [self.delegate paymentCoordinatorDidSucceed:self];
    } else {
        [self.delegate paymentCoordinatorDidCancel:self];
    }
    self.lastApplePayError = nil;
    self.applePaySucceeded = NO;
    [self artificiallyRelease];
}

- (void)paymentAuthorizationViewController:(__unused PKPaymentAuthorizationViewController *)controller
                       didAuthorizePayment:(PKPayment *)payment
                                completion:(void (^)(PKPaymentAuthorizationStatus))completion {
    [self.apiClient createTokenWithPayment:payment completion:^(STPToken * _Nullable token, NSError * _Nullable error) {
        if (error != nil) {
            self.lastApplePayError = error;
            completion(PKPaymentAuthorizationStatusFailure);
            return;
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
        STPAddress *address = [[STPAddress alloc] initWithABRecord:payment.shippingAddress];
#pragma clang diagnostic pop
        STPPaymentResult *result = [[STPPaymentResult alloc] initWithSource:token
                                                                   customer:nil
                                                            shippingAddress:address];
        [self.delegate paymentCoordinator:self didCreatePaymentResult:result completion:^(NSError * _Nullable applicationError) {
            if (applicationError != nil) {
                self.lastApplePayError = applicationError;
                completion(PKPaymentAuthorizationStatusFailure);
                return;
            }
            self.applePaySucceeded = YES;
            completion(PKPaymentAuthorizationStatusSuccess);
        }];
    }];
}


@end