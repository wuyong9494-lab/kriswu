import SwiftUI

enum StarRailStyle {
    static func accent(_ back: StarRail.CardBack) -> Color {
        switch back { case .starlines:return TileTheme.mint; case .orbit:return .cyan; case .aurora:return RailPalette.lilac; case .solar:return TileTheme.gold }
    }
    static func sky(_ theme: StarRail.SkyTheme) -> [Color] {
        switch theme {
        case .midnight:return [Color(red:0.035,green:0.065,blue:0.15),Color(red:0.07,green:0.16,blue:0.22)]
        case .dawn:return [Color(red:0.18,green:0.09,blue:0.20),Color(red:0.31,green:0.18,blue:0.19)]
        case .nebula:return [Color(red:0.10,green:0.07,blue:0.23),Color(red:0.19,green:0.11,blue:0.34)]
        }
    }
}

struct RailSkyBackdrop: View {
    var theme: StarRail.SkyTheme = .midnight
    var body: some View {
        ZStack {
            LinearGradient(colors:StarRailStyle.sky(theme),startPoint:.topLeading,endPoint:.bottomTrailing)
            Canvas { context, size in
                for i in 0..<62 {
                    let x = CGFloat((i*73+17)%997)/997*size.width
                    let y = CGFloat((i*137+43)%991)/991*size.height
                    let side: CGFloat = i.isMultiple(of:7) ? 2.8 : 1.2
                    context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:side,height:side)),with:.color(.white.opacity(i.isMultiple(of:7) ? 0.45 : 0.14)))
                }
                var orbit = Path()
                orbit.addEllipse(in:CGRect(x:size.width*0.4,y:-size.width*0.3,width:size.width*0.9,height:size.width*0.9))
                context.stroke(orbit,with:.color(.white.opacity(0.04)),lineWidth:1)
            }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct RailBrandMark: View {
    var side: CGFloat = 62
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:side*0.3).fill(LinearGradient(colors:[TileTheme.mint,Color(red:0.19,green:0.55,blue:0.65)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Canvas { context, size in
                let center = CGPoint(x:size.width/2,y:size.height/2)
                var star = Path()
                for i in 0..<8 {
                    let angle = Double(i)*Double.pi/4-Double.pi/2
                    let radius = size.width*(i.isMultiple(of:2) ? 0.31 : 0.12)
                    let p = CGPoint(x:center.x+cos(angle)*radius,y:center.y+sin(angle)*radius)
                    if i==0 { star.move(to:p) } else { star.addLine(to:p) }
                }
                star.closeSubpath()
                context.fill(star,with:.color(RailPalette.ink))
                let ring=CGRect(x:size.width*0.12,y:size.height*0.31,width:size.width*0.76,height:size.height*0.38)
                context.stroke(Path(ellipseIn:ring),with:.color(.white.opacity(0.8)),lineWidth:1.3)
                context.fill(Path(ellipseIn:CGRect(x:size.width*0.8,y:size.height*0.4,width:4,height:4)),with:.color(TileTheme.gold))
            }
        }
        .frame(width:side,height:side).shadow(color:TileTheme.mint.opacity(0.18),radius:12,y:5)
        .accessibilityHidden(true)
    }
}

struct RailCardBack: View {
    let style: StarRail.CardBack
    var side: CGFloat
    var body: some View {
        let accent = StarRailStyle.accent(style)
        ZStack {
            RoundedRectangle(cornerRadius:side*0.21).fill(LinearGradient(colors:[accent.opacity(0.8),RailPalette.ink],startPoint:.topLeading,endPoint:.bottomTrailing))
            Canvas { context, size in
                let center=CGPoint(x:size.width/2,y:size.height/2)
                if style == .orbit || style == .solar {
                    for i in 0..<3 {
                        let inset=CGFloat(i)*size.width*0.1+size.width*0.12
                        let r=CGRect(x:inset,y:inset,width:size.width-inset*2,height:size.height-inset*2)
                        context.stroke(Path(ellipseIn:r),with:.color(.white.opacity(0.6)),lineWidth:1)
                    }
                } else {
                    for i in 0..<5 {
                        var p=Path();let offset=CGFloat(i)*size.width/6
                        p.move(to:CGPoint(x:offset,y:0));p.addQuadCurve(to:CGPoint(x:size.width,y:offset+size.height*0.3),control:center)
                        context.stroke(p,with:.color(.white.opacity(0.45)),lineWidth:1.2)
                    }
                }
                context.fill(Path(ellipseIn:CGRect(x:center.x-3,y:center.y-3,width:6,height:6)),with:.color(TileTheme.gold))
            }
            .padding(side*0.08)
            RoundedRectangle(cornerRadius:side*0.21).strokeBorder(accent.opacity(0.7),lineWidth:1.5)
        }
        .frame(width:side,height:side).accessibilityHidden(true)
    }
}
