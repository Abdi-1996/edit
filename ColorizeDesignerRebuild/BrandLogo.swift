import SwiftUI

struct BrandLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white)
            HStack(spacing: -3) {
                Capsule().fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom)).frame(width: 11, height: 34).rotationEffect(.degrees(18))
                Capsule().fill(LinearGradient(colors: [.blue, .pink], startPoint: .top, endPoint: .bottom)).frame(width: 11, height: 38).rotationEffect(.degrees(18))
                Capsule().fill(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom)).frame(width: 11, height: 34).rotationEffect(.degrees(18))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18)))
    }
}
