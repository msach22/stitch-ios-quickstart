//
//  ConversationController.swift
//  NexmoConversation
//
//  Created by Shams Ahmed on 14/11/2016.
//  Copyright © 2016 Nexmo. All rights reserved.
//

import Foundation
import RxSwift

/// Conversation controller to handle fetching conversation request, fetching save to cache and database
@objc(NXMConversationController)
public class ConversationController: NSObject {

    // MARK:
    // MARK: Typealias
    
    /// Information about conversation
    public typealias LiteConversation = (name: String, uuid: String)

    // MARK:
    // MARK: Properties

    /// Media Controller
    internal let media: MediaController

    /// Network controller
    private let networkController: NetworkController
    
    /// Rx
    internal let disposeBag = DisposeBag()

    /// Sync Manager
    internal weak var syncManager: SyncManager?

    /// Account controller
    internal let account: AccountController

    /// Contains a collection of all conversations.
    public let conversations: ConversationCollection
    
    // MARK:
    // MARK: Initializers
    
    internal init(network: NetworkController, account: AccountController, rtc: MediaController) {
        networkController = network
        media = rtc
        conversations = ConversationCollection(storage: nil) // Set afterwards
        self.account = account
    }
    
    // MARK:
    // MARK: Create
    
    /// Create a new conversation with/without joining
    ///
    /// - Parameters:
    ///   - displayName: conversation displayName
    ///   - join: should join the new conversation
    /// - Returns: observable with conversation model if persisted in local database following successfull creation in backend. Only persisted if created with Join.
    public func new(_ displayName: String, withJoin shouldJoin: Bool = false) -> NexmoConversation.Observable<Conversation> {
        var uuid: String?
        
        let model = ConversationService.CreateConversation(name: displayName)
        
        guard let userId = account.userId else {
            return RxSwift.Observable<Conversation>.error(ConversationClient.Errors.userNotInCorrectState).wrap
        }
        
        return RxSwift.Observable<String>.create { observer -> Disposable in
            self.networkController.conversationService.create(with: model, success: { newUuid in
                uuid = newUuid
                
                if shouldJoin {
                    observer.onNextWithCompleted(newUuid)
                } else {
                    observer.onCompleted()
                }
            }, failure: { error in
                observer.onError(error)
            })

            return Disposables.create()
        }
        .flatMap { self.join(JoinConversation(userId: userId), forUUID: $0) }
        .map { _ in uuid }
        .unwrap()
        .delay(1.0, scheduler: ConcurrentDispatchQueueScheduler(qos: .utility)) // TODO: remove delay once backend fixes indexing issue [June 17]
        .flatMap { self.conversation(with: $0).rx }
        .observeOnBackground()
        .wrap
    }
    
    // MARK:
    // MARK: Fetch
    
    /// Fetch all users conversations
    ///
    /// - Parameter userId: user id
    /// - Returns: observable with lite conversations
    public func all(with userId: String) -> NexmoConversation.Observable<[ConversationPreviewModel]> {
        return RxSwift.Observable<[ConversationPreviewModel]>.create { observer in
            self.networkController.conversationService.all(for: userId, success: { conversations in
                observer.onNextWithCompleted(conversations)
            }, failure: { error in
                observer.onError(error)
            })
            
            return Disposables.create()
        }
        .observeOnBackground()
        .wrap
    }
    
    /// Fetch all conversations visible to the current user
    ///
    /// - Returns: observable with lite conversations
    public func all() -> NexmoConversation.Observable<[ConversationController.LiteConversation]> {
        return RxSwift.Observable<[ConversationController.LiteConversation]>.create { observer in
            self.networkController.conversationService.all(
                from: 0,
                success: { observer.onNextWithCompleted($0) },
                failure: { observer.onError($0) }
            )
            
            return Disposables.create()
            }
            .observeOnBackground()
            .wrap
    }

    // MARK:
    // MARK: Detailed Conversation

    /// Fetch a detailed conversation
    ///
    /// - Parameter conversationId: conversation Id
    /// - Returns: observable with conversation
    public func conversation(with conversationId: String) -> NexmoConversation.Observable<Conversation> {
        return RxSwift.Observable<ConversationModel>.create { observer in
            self.networkController.conversationService.conversation(with: conversationId, success: { conversation in
                observer.onNextWithCompleted(conversation)
            }, failure: { error in
                observer.onError(error)
            })
            
            return Disposables.create()
            }
            .map { try self.syncManager?.save($0) }
            .unwrap()
            .observeOnBackground()
            .wrap
    }

    // MARK:
    // MARK: Internal - Join

    /// Join a conversation
    ///
    /// - Parameters:
    ///   - model: join parameter
    ///   - uuid: conversation uuid
    /// - Returns: observable with status result
    internal func join(_ model: JoinConversation, forUUID uuid: String) -> RxSwift.Observable<MemberModel.State> {
        return RxSwift.Observable<MemberModel.State>.create { observer -> Disposable in
            self.networkController.conversationService.join(with: model, forUUID: uuid, success: { status in
                observer.onNextWithCompleted(status.state)
            }, failure: { error in
                observer.onError(error)
            })

            return Disposables.create()
            }
            .observeOnMainThread()
    }
}
