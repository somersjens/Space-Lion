//
//  MenuPolarBackground.swift
//  Flying Penguin
//
//  The quiet backdrop behind the welcome flow and the main menu. Same layout as
//  before — a wash, a soft light, two low shapes and a sprinkle layer — but
//  drawn from the playfield's own polar palette, so the menu and the sea the
//  penguin is shot across read as one world.
//

import SwiftUI

/// Cool, ice-based backdrop for the welcome flow and the main menu. It stays
/// deliberately pale: the shelf shapes and the drifting clouds keep the wide
/// screens friendly without ever competing with the controls on top of them.
struct MenuPolarBackground: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.74, green: 0.91, blue: 1.00),
                                        Color(red: 0.90, green: 0.97, blue: 1.00),
                                        Color(red: 0.975, green: 0.995, blue: 1.00)],
                               startPoint: .top, endPoint: .bottom)

                Circle()
                    .fill(Color.white.opacity(0.58))
                    .blur(radius: 22)
                    .frame(width: proxy.size.width * 0.52,
                           height: proxy.size.width * 0.52)
                    .offset(x: -proxy.size.width * 0.28,
                            y: -proxy.size.height * 0.28)

                MenuDriftingClouds(size: proxy.size)

                // The ice shelf the menu sits on, and a tinted floe beside it
                // that carries the selected character's colour.
                Ellipse()
                    .fill(Color(red: 0.72, green: 0.92, blue: 0.99).opacity(0.58))
                    .frame(width: proxy.size.width * 0.72,
                           height: max(110, proxy.size.height * 0.30))
                    .offset(x: proxy.size.width * 0.25,
                            y: proxy.size.height * 0.46)

                // Still ice, only tinted toward the character's colour. Filling
                // it with the accent outright turned the floe into sand as soon
                // as that accent was a warm one.
                Ellipse()
                    .fill(Color(red: 0.84, green: 0.95, blue: 1.00)
                        .mix(with: accent, by: 0.16)
                        .opacity(0.62))
                    .frame(width: proxy.size.width * 0.58,
                           height: max(90, proxy.size.height * 0.23))
                    .offset(x: -proxy.size.width * 0.32,
                            y: proxy.size.height * 0.50)

                MenuFrostSprinkles(accent: accent)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

}

/// Three of the playfield's own clouds, parked high and faint. They are the
/// clearest signal that this menu belongs to the flight below it.
private struct MenuDriftingClouds: View {
    let size: CGSize

    private let layout: [(x: CGFloat, y: CGFloat, width: CGFloat, opacity: Double)] = [
        (0.13, 0.15, 0.20, 0.58),
        (0.84, 0.11, 0.15, 0.48),
        (0.44, 0.07, 0.12, 0.34)
    ]

    var body: some View {
        ForEach(Array(layout.enumerated()), id: \.offset) { index, cloud in
            PolarCloud(seed: index &* 9 &+ 4)
                .frame(width: size.width * cloud.width,
                       height: size.width * cloud.width * 0.45)
                .opacity(cloud.opacity)
                .position(x: size.width * cloud.x, y: size.height * cloud.y)
        }
    }
}

/// Frost instead of leaves: ice shards and snow specks in the same count and
/// scatter the meadow sprinkles used, so the menu's density is unchanged.
private struct MenuFrostSprinkles: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<11, id: \.self) { index in
                Group {
                    if index.isMultiple(of: 3) {
                        Circle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: CGFloat(6 + index % 3 * 3))
                    } else {
                        IceShard()
                            .fill(index.isMultiple(of: 2)
                                  ? accent.opacity(0.12)
                                  : Color(red: 0.45, green: 0.80, blue: 0.95).opacity(0.16))
                            .frame(width: CGFloat(9 + index % 3 * 3),
                                   height: CGFloat(20 + index % 4 * 5))
                    }
                }
                .rotationEffect(.degrees(Double(index * 31 - 70)))
                .position(x: proxy.size.width * CGFloat((index * 37 + 9) % 100) / 100,
                          y: proxy.size.height * CGFloat((index * 53 + 17) % 100) / 100)
            }
        }
    }
}

private struct IceShard: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.34))
        path.closeSubpath()
        return path
    }
}
