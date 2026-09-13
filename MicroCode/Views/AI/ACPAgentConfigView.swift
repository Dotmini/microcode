//
//  ACPAgentConfigView.swift
//  MicroCode
//
//  ACP External Agent Configuration.
//  Now unified with AgentEcosystemConfigView adhering strictly to Apple HIG
//  and MicroCode IDE dark/light theme.
//

import SwiftUI

public struct ACPAgentConfigView: View {
    public init() {}

    public var body: some View {
        AgentEcosystemConfigView(initialTab: .agents)
    }
}
