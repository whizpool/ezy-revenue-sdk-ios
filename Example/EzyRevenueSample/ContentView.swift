import SwiftUI
import EzyRevenue

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("EzyRevenue Sample")
                .font(.title)
            Text("SDK version \(EzyRevenue.sdkVersion)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
