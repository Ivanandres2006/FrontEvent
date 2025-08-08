import SwiftUI
import GooglePlaces

struct GooglePlacesAutocompleteView: UIViewControllerRepresentable {
    @Binding var location: String
    @Binding var address: String
    @Binding var city: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> GMSAutocompleteViewController {
        let autocompleteController = GMSAutocompleteViewController()
        autocompleteController.delegate = context.coordinator
        return autocompleteController
    }
    func updateUIViewController(_ uiViewController: GMSAutocompleteViewController, context: Context) {}
    
    

    class Coordinator: NSObject, GMSAutocompleteViewControllerDelegate {
        var parent: GooglePlacesAutocompleteView
        init(_ parent: GooglePlacesAutocompleteView) { self.parent = parent }

        func viewController(_ viewController: GMSAutocompleteViewController, didAutocompleteWith place: GMSPlace) {
            parent.location = place.name ?? place.formattedAddress ?? ""
            parent.address = place.formattedAddress ?? ""
            parent.latitude = place.coordinate.latitude
            parent.longitude = place.coordinate.longitude

            // Parse city from address components
            if let city = place.addressComponents?.first(where: { $0.types.contains("locality") })?.name {
                parent.city = city
            } else if let city = place.addressComponents?.first(where: { $0.types.contains("administrative_area_level_2") })?.name {
                parent.city = city
            } else {
                parent.city = ""
            }
            parent.dismiss()
        }
        func viewController(_ viewController: GMSAutocompleteViewController, didFailAutocompleteWithError error: Error) {
            print("Autocomplete error: \(error)")
            parent.dismiss()
        }
        func wasCancelled(_ viewController: GMSAutocompleteViewController) {
            parent.dismiss()
        }
    }
}
