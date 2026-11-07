import AppKit
import SwiftUI
import XCTest
@testable import SkillDeck

final class AgentIconTests: XCTestCase {

    func testAgentsHaveBundledBrandIcons() {
        for agent in AgentType.allCases {
            guard let name = agent.iconResourceName else {
                XCTAssertEqual(agent, .qclaw, "Unexpected agent without a brand icon")
                continue
            }

            let url = SkillDeckResources.bundle.url(
                forResource: name,
                withExtension: "svg",
                subdirectory: "AgentIcons"
            )
            XCTAssertNotNil(url, "Missing bundled icon \(name).svg for \(agent.displayName)")
        }
    }

    func testOnlyMonochromeIconsUseTemplateRendering() {
        let monochromeAgents: Set<AgentType> = [.copilotCLI, .openCode, .cursor, .qoder, .pi]

        for agent in AgentType.allCases {
            XCTAssertEqual(
                agent.usesTemplateIcon,
                monochromeAgents.contains(agent),
                "\(agent.displayName) template rendering flag mismatch"
            )
        }
    }

    @MainActor
    func testEveryAgentIconRendersVisiblePixels() throws {
        for agent in AgentType.allCases {
            let renderer = ImageRenderer(
                content: AgentIconView(agentType: agent, size: 32)
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
            )
            renderer.scale = 1

            let image = try XCTUnwrap(renderer.nsImage, "\(agent.displayName) icon did not render")
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))

            var visiblePixels = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                        visiblePixels += 1
                    }
                }
            }

            XCTAssertGreaterThan(
                visiblePixels,
                20,
                "\(agent.displayName) icon rendered blank"
            )
        }
    }

    @MainActor
    func testMonochromeIconsFollowForegroundTint() throws {
        for agent in AgentType.allCases where agent.usesTemplateIcon {
            let renderer = ImageRenderer(
                content: AgentIconView(agentType: agent, size: 32)
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
            )
            renderer.scale = 1

            let image = try XCTUnwrap(renderer.nsImage, "\(agent.displayName) icon did not render")
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))

            var tintedPixels = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard
                        let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                        color.alphaComponent > 0.5
                    else {
                        continue
                    }

                    if color.redComponent > 0.8,
                       color.redComponent > color.greenComponent * 2,
                       color.redComponent > color.blueComponent * 2 {
                        tintedPixels += 1
                    }
                }
            }

            XCTAssertGreaterThan(tintedPixels, 20, "\(agent.displayName) icon did not follow the tint")
            XCTAssertLessThan(
                tintedPixels,
                rep.pixelsWide * rep.pixelsHigh * 9 / 10,
                "\(agent.displayName) tinted the whole bounds instead of the logo shape"
            )
        }
    }
}
