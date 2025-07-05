import SwiftUI
import Stripe

struct StripeCardField: UIViewRepresentable {
    @Binding var cardParams: STPPaymentMethodCardParams
    @Binding var isValid: Bool
    @Binding var brand: STPCardBrand

    func makeCoordinator() -> Coordinator {
        Coordinator(cardParams: $cardParams, isValid: $isValid, brand: $brand)
    }

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let cardField = STPPaymentCardTextField()
        cardField.borderWidth = 0
        cardField.cornerRadius = 14
        cardField.backgroundColor = .white
        cardField.textColor = .black
        cardField.placeholderColor = .darkGray
        cardField.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        cardField.delegate = context.coordinator
        return cardField
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}

    class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        @Binding var cardParams: STPPaymentMethodCardParams
        @Binding var isValid: Bool
        @Binding var brand: STPCardBrand

        init(cardParams: Binding<STPPaymentMethodCardParams>,
             isValid: Binding<Bool>,
             brand: Binding<STPCardBrand>) {
            _cardParams = cardParams
            _isValid = isValid
            _brand = brand
        }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            let params = STPPaymentMethodCardParams()
            params.number = textField.cardNumber
            params.expMonth = NSNumber(value: textField.expirationMonth)
            params.expYear = NSNumber(value: textField.expirationYear)
            params.cvc = textField.cvc

            cardParams = params
            isValid = textField.isValid

            // ✅ Get the card brand using validator
            brand = STPCardValidator.brand(forNumber: textField.cardNumber ?? "")
        }
    }
}
