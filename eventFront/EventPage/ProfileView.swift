import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var userSession: UserSession
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @AppStorage("hasPassword") var hasPassword = false
    @AppStorage("selectedLanguage") var lang: String = "en"
    

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var photos: [UIImage] = []
    @State private var isLoading = false
    @State private var animate = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                
                

                ScrollView {
                    VStack(spacing: 30) {
                        Spacer()

                        Text(lang == "es" ? "👤 Mi perfil" : "👤 My Profile")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .opacity(animate ? 1.0 : 0)
                            .offset(y: animate ? 0 : -10)
                            .animation(.easeOut(duration: 0.5), value: animate)

                        VStack(spacing: 12) {
                            Text(userSession.fullName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text(userSession.email)
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 20) {
                                        Text("Language")
                                            .font(.title2.bold())
                                            .foregroundColor(.white)

                                        CustomDropdown(
                                            label: "Select Language",
                                            selection: $lang,
                                            options: ["en", "es"]
                                        )

                                        Spacer()
                                    }
                                    .padding()

                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text("Upload Event Photo")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gold)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        if !photos.isEmpty {
                            Text("Your Event Photos")
                                .foregroundColor(.white)
                                .font(.headline)
                                .padding(.top)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(photos, id: \.self) { image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .cornerRadius(16)
                                            .shadow(radius: 5)
                                            .clipped()
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        Button("Logout") {
                            TokenManager.shared.deleteToken()
                            isLoggedIn = false
                            hasPassword = false
                        }
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                        .padding(.top, 20)

                        Spacer()
                    }
                    .padding()
                    .onAppear { animate = true }
                }

                // ✅ Floating Admin Button
                if userSession.role == "ADMIN" {
                    VStack {
                        HStack {
                            Spacer()
                            NavigationLink(destination: AdminView()) {
                                Image(systemName: "shield.lefthalf.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .padding()
                                    .background(Color.blue.opacity(0.85))
                                    .clipShape(Circle())
                                    .foregroundColor(.white)
                                    .shadow(radius: 5)
                            }
                            .padding(.top, 10)
                            .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                    .transition(.scale)
                }
            }
            .onChange(of: selectedItem) {
                if let item = selectedItem {
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            photos.append(image)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    struct CustomDropdown: View {
        var label: String
        @Binding var selection: String
        var options: [String]

        @State private var isExpanded = false

        var body: some View {
            VStack(spacing: 4) {
                Button(action: {
                    withAnimation { isExpanded.toggle() }
                }) {
                    HStack {
                        Text(selection.isEmpty ? label : selection)
                            .foregroundColor(selection.isEmpty ? .gray : .white)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }

                if isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(options, id: \.self) { option in
                                Button(action: {
                                    selection = option
                                    isExpanded = false
                                }) {
                                    Text(option)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selection == option ? Color.white.opacity(0.1) : Color.clear)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                }
            }
        }
    }

}
