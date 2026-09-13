//
//  PlatformCompatibilityInspectorView.swift
//  MicroCode
//
//  Platform Compatibility & Rules Inspector.
//  Now unified with AgentEcosystemConfigView adhering strictly to Apple HIG
//  and MicroCode IDE dark/light theme.
//

import SwiftUI

public struct PlatformCompatibilityInspectorView: View {
    public init() {}

    public var body: some View {
        AgentEcosystemConfigView(initialTab: .rules)
    }
}
