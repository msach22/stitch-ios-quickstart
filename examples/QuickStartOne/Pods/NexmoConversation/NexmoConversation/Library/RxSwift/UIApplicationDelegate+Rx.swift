//
//  UIApplicationDelegate+Rx.swift
//  NexmoConversation
//
//  Created by shams ahmed on 24/10/2016.
//  Copyright © 2016 Nexmo. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

/// Application State
///
/// - active: Application in foreground
/// - inactive: Foreground but not receiving events i.e user has opens notification center, phone call, system prompt
/// - background: Background
/// - terminated: Terminated
internal enum ApplicationState: Equatable {
    case active, inactive, background, terminated
}

/// Helper to get the current application state
internal extension RxSwift.Reactive where Base: UIApplication {
    
    // MARK:
    // MARK: Private - Delegate
    
    /// UIApplicationDelegate
    private var delegate: DelegateProxy<UIApplication, UIApplicationDelegate> {
        return RxApplicationDelegateProxy.proxy(for: base)
    }

    // MARK:
    // MARK: Private - UIApplication Notification State
    
    ///  State for when application is active
    private var applicationDidBecomeActive: RxSwift.Observable<ApplicationState> {
        return NotificationCenter.default.rx.notification(.UIApplicationDidBecomeActive)
            .map { _ in .active }
    }
    
    /// State for when application is background
    private var applicationDidEnterBackground: RxSwift.Observable<ApplicationState> {
        return NotificationCenter.default.rx.notification(.UIApplicationDidEnterBackground)
            .map { _ in .background }
    }
    
    /// State for when application is resigning active
    private var applicationWillResignActive: RxSwift.Observable<ApplicationState> {
        return NotificationCenter.default.rx.notification(.UIApplicationWillResignActive)
            .map { _ in .inactive }
    }
    
    /// State for when application is terminating
    private var applicationWillTerminate: RxSwift.Observable<ApplicationState> {
        return NotificationCenter.default.rx.notification(.UIApplicationWillTerminate)
            .map { _ in .terminated }
    }
    
    // MARK:
    // MARK: Push Notification
    
    /// Received remote notification observable
    /// Support iOS 9
    internal var receiveRemoteNotification: RxSwift.Observable<PushNotificationController.State> {
        let remoteNotificationWithFetch = delegate
            .methodInvoked(#selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)))
            .map { value in PushNotificationController.State.receivedRemoteNotification(
                payload: value[1] as? [AnyHashable: Any],
                fetchCompletion: value[2])
        }
        
        // TODO: Deprecate in version 1.0.0
        let remoteNotification = delegate
            .methodInvoked(#selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:)))
            .map { PushNotificationController.State.receivedRemoteNotification(
                payload: $0[1] as? [AnyHashable: Any],
                fetchCompletion: nil)
        }
        
        return RxSwift.Observable.of(remoteNotificationWithFetch, remoteNotification).merge()
    }
    
    /// Registered for remote notifications device token observable
    /// Support iOS 9
    internal var registeredForRemoteNotifications: RxSwift.Observable<PushNotificationController.State> {
        return delegate
            .methodInvoked(#selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)))
            .map { $0.last as? Data }
            .unwrap()
            .map { PushNotificationController.State.registeredWithDeviceToken($0) }
    }

    /// Register for remote notifications failed observable
    internal var registerForRemoteNotificationsFailed: RxSwift.Observable<PushNotificationController.State> {
        return delegate
            .methodInvoked(#selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)))
            .map { $0.last as? Error }
            .unwrap()
            .map { PushNotificationController.State.registerForRemoteNotificationsFailed($0) }
    }
    
    // MARK:
    // MARK: Application State
    
    /// Application state observable
    internal var applicationState: RxSwift.Observable<ApplicationState> {
        return RxSwift.Observable.of(
            applicationDidBecomeActive,
            applicationWillResignActive,
            applicationDidEnterBackground,
            applicationWillTerminate
            )
            .merge()
    }
}

// MARK:
// MARK: Compare

/// Equality Application State
///
/// - Parameters:
///   - lhs: state
///   - rhs: state
/// - Returns: result of comparison
/// :nodoc:
internal func ==(lhs: ApplicationState, rhs: ApplicationState) -> Bool {
    switch (lhs, rhs) {
    case (.active, .active),
         (.inactive, .inactive),
         (.background, .background),
         (.terminated, .terminated):
        return true
    case (.active, _),
         (.inactive, _),
         (.background, _),
         (.terminated, _):
        return false
    }
}
