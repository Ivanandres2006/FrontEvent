import SwiftUI

struct LanguageSelectionView: View {
    var onLanguageSelected: (String) -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Select Language")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Button(action: { onLanguageSelected("en") }) {
                    Text("English")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }

                Button(action: { onLanguageSelected("es") }) {
                    Text("Español")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 32)
        }
    }
}
