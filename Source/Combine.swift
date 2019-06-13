//
//  Combine.swift
//  Alamofire
//
//  Created by Jon Shier on 6/9/19.
//  Copyright © 2019 Alamofire. All rights reserved.
//

#if canImport(Combine)

import Combine
import Dispatch
import Foundation

extension DataRequest {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func futureDecodable<T: Decodable>(of type: T.Type = T.self, queue: DispatchQueue = .main, decoder: DataDecoder = JSONDecoder()) -> Publishers.Future<DataResponse<T>, Never> {
        return Publishers.Future { (completion) in
            self.responseDecodable(queue: queue, decoder: decoder) { (response: DataResponse<T>) in
                completion(.success(response))
            }
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public extension Publisher where Output == URLRequest {
    func request(using session: Session = .default) -> Publishers.AF.Request<Self> {
        return Publishers.AF.Request(self, session: session)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public extension Publisher where Output == DataRequest {
    func response<T: Decodable>(of type: T.Type = T.self, queue: DispatchQueue = .main, decoder: DataDecoder = JSONDecoder()) -> Publishers.AF.Response<Self, T> {
        return Publishers.AF.Response(self, queue: queue, decoder: decoder, of: type)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public extension Publishers {
    enum AF {
        public struct Request<Upstream: Publisher>: Publisher where Upstream.Output == URLRequest {
            public typealias Output = DataRequest
            public typealias Failure = Upstream.Failure

            let upstream: Upstream
            let session: Session

            init(_ upstream: Upstream, session: Session) {
                self.upstream = upstream
                self.session = session
            }

            public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
                let inner = Inner(subscriber,session: session)
                upstream.subscribe(inner)
                subscriber.receive(subscription: inner)
            }

            final class Inner<Downstream: Subscriber>: Subscriber, Subscription where Downstream.Input == DataRequest {
                typealias Input = URLRequest
                typealias Failure = Downstream.Failure

                private struct MutableState {
                    var subscription: Subscription?
                    var downstream: Downstream?
                }

                private var mutableState: Protector<MutableState> = Protector(MutableState())
                private let session: Session

                init(_ downstream: Downstream, session: Session) {
                    self.session = session

                    mutableState.write { $0.downstream = downstream }
                }

                func receive(subscription: Subscription) {
                    if let subscription = mutableState.directValue.subscription {
                        subscription.cancel()
                    } else {
                        mutableState.write { $0.subscription = subscription }
                    }
                }

                func receive(_ input: URLRequest) -> Subscribers.Demand {
                    let request = session.request(input)

                    guard let result = self.mutableState.directValue.downstream?.receive(request), result > 0 else { return .none }

                    guard let subscription = self.mutableState.directValue.subscription else { return .none }

                    subscription.request(result)

                    return .unlimited
                }

                func receive(completion: Subscribers.Completion<Downstream.Failure>) {
                    guard let downstream = mutableState.directValue.downstream else { return }

                    downstream.receive(completion: completion)
                }

                func request(_ demand: Subscribers.Demand) {
                    guard let subscription = mutableState.directValue.subscription else { return }

                    subscription.request(demand)
                }

                func cancel() {
                    mutableState.write { (state) in
                        state.subscription = nil
                        state.downstream = nil
                    }
                }
            }
        }

        public struct Response<Upstream: Publisher, T: Decodable>: Publisher where Upstream.Output == DataRequest {
            public typealias Output = DataResponse<T>
            public typealias Failure = Upstream.Failure

            let upstream: Upstream
            let queue: DispatchQueue
            let decoder: DataDecoder

            init(_ upstream: Upstream, queue: DispatchQueue, decoder: DataDecoder, of: T.Type) {
                self.upstream = upstream
                self.queue = queue
                self.decoder = decoder
            }

            public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
                let inner = Inner(subscriber, queue: queue, decoder: decoder)
                upstream.subscribe(inner)
                subscriber.receive(subscription: inner)
            }

            final class Inner<Downstream: Subscriber>: Subscriber, Subscription where Downstream.Input == DataResponse<T> {
                typealias Input = DataRequest
                typealias Failure = Downstream.Failure

                private struct MutableState {
                    var subscription: Subscription?
                    var downstream: Downstream?
                    var request: DataRequest?
                }

                private var mutableState: Protector<MutableState> = Protector(MutableState())

                private let queue: DispatchQueue
                private let decoder: DataDecoder

                init(_ downstream: Downstream, queue: DispatchQueue = .main, decoder: DataDecoder = JSONDecoder()) {
                    self.queue = queue
                    self.decoder = decoder

                    mutableState.write { $0.downstream = downstream }
                }

                func receive(subscription: Subscription) {
                    if let subscription = mutableState.directValue.subscription {
                        subscription.cancel()
                    } else {
                        mutableState.write { $0.subscription = subscription }
                    }
                }

                func receive(_ input: DataRequest) -> Subscribers.Demand {
                    mutableState.write { $0.request = input }

                    input.responseDecodable(queue: queue, decoder: decoder) { (response: DataResponse<T>) -> Void in
                        guard let result = self.mutableState.directValue.downstream?.receive(response), result > 0 else { return }

                        guard let subscription = self.mutableState.directValue.subscription else { return }

                        subscription.request(result)
                    }

                    return .none
                }

                func receive(completion: Subscribers.Completion<Downstream.Failure>) {
                    guard let downstream = mutableState.directValue.downstream else { return }

                    downstream.receive(completion: completion)
                }

                func request(_ demand: Subscribers.Demand) {
                    guard let subscription = mutableState.directValue.subscription else { return }

                    subscription.request(demand)
                }

                func cancel() {
                    mutableState.write { (state) in
                        state.request?.cancel()
                        state.request = nil
                        state.subscription = nil
                        state.downstream = nil
                    }
                }
            }
        }
    }
}

#endif
