//
//  TransportStrategy.swift
//  MullvadREST
//
//  Created by Marco Nikic on 2023-04-27.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging
import MullvadSettings
import MullvadTypes

public class TransportStrategy: Equatable {
    /// The different transports suggested by the strategy
    public enum Transport {
        /// Connecting a direct connection
        case direct

        /// Connecting via  shadowsocks proxy
        case shadowsocks(configuration: ShadowsocksConfiguration)

        /// Connecting via socks proxy
        case socks5(configuration: Socks5Configuration)

        /// Failing  to retrive transport
        case none
    }

    private let shadowsocksLoader: ShadowsocksLoaderProtocol

    private let accessMethodIterator: AccessMethodIterator

    public init(
        _ userDefaults: UserDefaults,
        datasource: AccessMethodRepositoryDataSource,
        shadowsocksLoader: ShadowsocksLoaderProtocol
    ) {
        self.shadowsocksLoader = shadowsocksLoader
        self.accessMethodIterator = AccessMethodIterator(
            userDefaults,
            dataSource: datasource
        )
    }

    /// Rotating between enabled configurations by what order they were added in
    public func didFail() {
        let configuration = accessMethodIterator.pick()
        switch configuration.kind {
        case .bridges:
            try? shadowsocksLoader.reloadConfiguration()
            fallthrough
        default:
            self.accessMethodIterator.rotate()
        }
    }

    /// The suggested connection transport
    public func connectionTransport() -> Transport {
        let configuration = accessMethodIterator.pick()
        switch configuration.proxyConfiguration {
        case .direct:
            return .direct
        case .bridges:
            do {
                let configuration = try shadowsocksLoader.load()
                return .shadowsocks(configuration: configuration)
            } catch {
                didFail()
                guard accessMethodIterator.pick().kind != .bridges else { return .none }
                return connectionTransport()
            }
        case let .shadowsocks(configuration):
            return .shadowsocks(configuration: ShadowsocksConfiguration(
                address: configuration.server,
                port: configuration.port,
                password: configuration.password,
                cipher: configuration.cipher.rawValue.description
            ))
        case let .socks5(configuration):
            switch configuration.authentication {
            case .noAuthentication:
                return .socks5(configuration: Socks5Configuration(proxyEndpoint: configuration.toAnyIPEndpoint))
            case let .usernamePassword(username, password):
                return .socks5(configuration: Socks5Configuration(
                    proxyEndpoint: configuration.toAnyIPEndpoint,
                    username: username,
                    password: password
                ))
            }
        }
    }

    public static func == (lhs: TransportStrategy, rhs: TransportStrategy) -> Bool {
        lhs.accessMethodIterator.pick() == rhs.accessMethodIterator.pick()
    }
}