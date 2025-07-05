import SwiftUI
import Stripe

struct CustomCardInputView: View {
    @Binding var cardParams: STPPaymentMethodCardParams
    @Binding var isValid: Bool

    @State private var number = ""
    @State private var expMonth = ""
    @State private var expYear = ""
    @State private var cvc = ""
    @State private var name = ""
    @State private var country = "US"
    @State private var zip = ""

    let countries = ["US", "VE", "CA", "MX", "GB", "FR"]

    var body: some View {
        VStack(spacing: 16) {
            Text("Card Information")
                .font(.headline)
                .foregroundColor(.white)

            TextField("Card Number", text: $number)
                .keyboardType(.numberPad)
                .padding()
                .background(Color.white)
                .cornerRadius(12)

            HStack(spacing: 12) {
                TextField("MM", text: $expMonth)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)

                TextField("YY", text: $expYear)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)

                TextField("CVC", text: $cvc)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
            }

            TextField("Cardholder Name", text: $name)
                .autocapitalization(.words)
                .padding()
                .background(Color.white)
                .cornerRadius(12)

            Picker("Country", selection: $country) {
                ForEach(countries, id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            .background(Color.white)
            .cornerRadius(12)

            TextField("ZIP Code", text: $zip)
                .keyboardType(.default)
                .padding()
                .background(Color.white)
                .cornerRadius(12)

            if !isValid {
                Text("Invalid card information")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .onChange(of: number) { _ in validate() }
        .onChange(of: expMonth) { _ in validate() }
        .onChange(of: expYear) { _ in validate() }
        .onChange(of: cvc) { _ in validate() }
        .onChange(of: name) { _ in validate() }
        .onChange(of: zip) { _ in validate() }
    }

    private func validate() {
        guard let month = Int(expMonth),
              let year = Int(expYear),
              month > 0, month <= 12,
              year >= 24,
              number.count >= 13 && number.count <= 19,
              cvc.count >= 3 && cvc.count <= 4,
              !name.isEmpty,
              !zip.isEmpty else {
            isValid = false
            return
        }

        let params = STPPaymentMethodCardParams()
        params.number = number
        params.expMonth = NSNumber(value: month)
        params.expYear = NSNumber(value: 2000 + year)
        params.cvc = cvc

        cardParams = params
        isValid = true
    }

    func getBillingDetails(email: String) -> STPPaymentMethodBillingDetails {
        let billing = STPPaymentMethodBillingDetails()
        billing.name = name
        billing.email = email

        let address = STPPaymentMethodAddress()
        address.country = country
        address.postalCode = zip
        billing.address = address

        return billing
    }
}
