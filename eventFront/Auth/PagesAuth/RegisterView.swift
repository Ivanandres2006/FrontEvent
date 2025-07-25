import SwiftUI

struct RegisterView: View {
    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    @AppStorage("selectedLanguage") var lang: String = "en"
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""

    @State private var currentStep = 0
    @State private var isLoading = false
    @State private var message = ""
    @State private var goToVerify = false

    var body: some View {
        NavigationStack {
            if goToVerify {
                EmailVerificationView(email: email)
            } else {
                ZStack {
                    LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()

                    VStack(spacing: 32) {
                        Spacer()

                        Text(lang == "es" ? "Paso \(currentStep + 1) de 4" : "Step \(currentStep + 1) of 4")
                            .foregroundColor(.gray)
                            .font(.subheadline)

                        Group {
                            if currentStep == 0 {
                                stepOne
                            } else if currentStep == 1 {
                                stepTwo
                            } else if currentStep == 2 {
                                stepThree
                            } else {
                                stepFour
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                        if !message.isEmpty {
                            Text(message)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }

                        Spacer()

                        if isLoading {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .gold))
                        } else {
                            Button(action: handleNext) {
                                Text(
                                    currentStep == 3
                                    ? (lang == "es" ? "Registrarse" : "Register")
                                    : (lang == "es" ? "Siguiente" : "Next")
                                )
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(isCurrentStepValid ? Color.gold : Color.gray)
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                            }
                            .disabled(!isCurrentStepValid)
                            .padding(.horizontal)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    .animation(.easeInOut, value: currentStep)
                }
            }
        }
    }

    var stepOne: some View {
        VStack(spacing: 16) {
            Text(lang == "es" ? "Cual es tu nombre?" : "What's your name?")
                .font(.title.bold())
                .foregroundColor(.white)

            CustomInputField(icon: "person", placeholder: lang == "es" ? "Primer Nombre" :"First Name", text: $firstName)
            CustomInputField(icon: "person", placeholder: lang == "es" ? "Apellido" : "Last Name", text: $lastName)
                             CustomInputField(icon: "person.text.rectangle", placeholder: lang == "es" ? "Nombre de Usuario" : "Username", text: $username)
        }
    }

    var stepTwo: some View {
        VStack(spacing: 16) {
            Text(lang == "es" ? "Como te podemos contactar" : "How can we contact you?")
                .font(.title.bold())
                .foregroundColor(.white)

            CustomInputField(icon: "envelope", placeholder: lang == "es" ? "Correo Electronico" : "Email", text: $email, keyboard: .emailAddress)
            CustomInputField(icon: "phone", placeholder: lang == "es" ? "Numero Telefonico" : "Phone", text: $phone, keyboard: .phonePad)
        }
    }

    var stepThree: some View {
        VStack(spacing: 16) {
            Text(lang == "es" ? "Crea una clave" : "Create a password")
                .font(.title.bold())
                .foregroundColor(.white)

            CustomInputField(icon: "lock", placeholder: lang == "es" ? "Clave" : "Password", text: $password, isSecure: true)
        }
    }

    var stepFour: some View {
        VStack(spacing: 12) {
            Text(lang == "es" ? "Revisa y Confirma" : "Review and Confirm")
                .font(.title.bold())
                .foregroundColor(.white)

            Group {
                summaryRow(lang == "es" ? "Nombre" : "Name", "\(firstName) \(lastName)")
                summaryRow(lang == "es" ? "Nombre de Usuario" : "Username", username)
                summaryRow(lang == "es" ? "Correo Electronico" :"Email", email)
                summaryRow(lang == "es" ? "Numero Telefonico" : "Phone", phone)
            }
        }
    }

    func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.gray)
            Spacer()
            Text(value).foregroundColor(.white)
        }
    }

    var isCurrentStepValid: Bool {
        switch currentStep {
            case 0: return !firstName.isEmpty && !lastName.isEmpty && !username.isEmpty
            case 1: return !email.isEmpty && !phone.isEmpty
            case 2: return !password.isEmpty
            default: return true
        }
    }

    func handleNext() {
        if currentStep < 3 {
            currentStep += 1
        } else {
            registerUser()
        }
    }

    func registerUser() {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/auth/register") else { return }

        let body: [String: Any] = [
            "firstName": firstName,
            "lastName": lastName,
            "username": username,
            "email": email,
            "phone": phone,
            "password": password,
            "useSms": false
        ]

        let jsonData = try? JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        isLoading = true
        message = ""

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                isLoading = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    message = "❌ Unexpected server response"
                    return
                }

                if let status = (response as? HTTPURLResponse)?.statusCode, status == 200 {
                    goToVerify = true
                } else if let backendMsg = json["message"] as? String {
                    message = "❌ \(backendMsg)"
                } else {
                    message = "❌ Registration failed"
                }
            }
        }.resume()
    }
}

