//
//  CustomListsDataSource.swift
//  MullvadVPN
//
//  Created by Jon Petersson on 2024-02-22.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadREST
import MullvadSettings
import MullvadTypes
import UIKit

class CustomListsDataSource: LocationDataSourceProtocol {
    private(set) var nodes = [LocationNode]()
    var didTapEditCustomLists: (() -> Void)?

    var viewForHeader: UIView? {
        LocationSectionHeaderView(configuration: LocationSectionHeaderView.Configuration(
            name: LocationSection.customLists.description,
            primaryAction: UIAction(
                handler: { [weak self] _ in
                    self?.didTapEditCustomLists?()
                }
            )
        ))
    }

    init(didTapEditCustomLists: (() -> Void)?) {
        self.didTapEditCustomLists = didTapEditCustomLists
    }

    var searchableNodes: [LocationNode] {
        nodes.flatMap { $0.children }
    }

    func reload(allLocationNodes: [LocationNode], customLists: [CustomList]) {
        nodes = customLists.map { list in
            let listNode = LocationListNode(
                nodeName: list.name,
                nodeCode: list.name.lowercased(),
                locations: list.locations,
                customList: list
            )

            listNode.children = list.locations.compactMap { location in
                copy(location, from: allLocationNodes, withParent: listNode)
            }

            listNode.forEachDescendant { _, node in
                node.nodeCode = "\(listNode.nodeCode)-\(node.nodeCode)"
            }

            return listNode
        }
    }

    func node(by locations: [RelayLocation], for customList: CustomList) -> LocationNode? {
        guard let customListNode = nodes.first(where: { $0.nodeName == customList.name })
        else { return nil }

        if locations.count > 1 {
            return customListNode
        } else {
            return switch locations.first {
            case let .country(countryCode):
                customListNode.nodeFor(nodeCode: "\(customListNode.nodeCode)-\(countryCode)")
            case let .city(_, cityCode):
                customListNode.nodeFor(nodeCode: "\(customListNode.nodeCode)-\(cityCode)")
            case let .hostname(_, _, hostCode):
                customListNode.nodeFor(nodeCode: "\(customListNode.nodeCode)-\(hostCode)")
            case .none:
                nil
            }
        }
    }

    private func copy(
        _ location: RelayLocation,
        from allLocationNodes: [LocationNode],
        withParent rootNode: LocationNode
    ) -> LocationNode? {
        let rootNode = RootNode(children: allLocationNodes)

        return switch location {
        case let .country(countryCode):
            rootNode
                .countryFor(countryCode: countryCode)?.copy(withParent: rootNode)

        case let .city(countryCode, cityCode):
            rootNode
                .countryFor(countryCode: countryCode)?.copy(withParent: rootNode)
                .cityFor(cityCode: cityCode)

        case let .hostname(countryCode, cityCode, hostCode):
            rootNode
                .countryFor(countryCode: countryCode)?.copy(withParent: rootNode)
                .cityFor(cityCode: cityCode)?
                .hostFor(hostCode: hostCode)
        }
    }
}
