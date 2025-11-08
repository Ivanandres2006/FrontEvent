import SwiftUI
import Contacts

struct ContactsSyncView: View {
    @State private var syncing = false
    @State private var suggestions: [UserSummary] = []
    @State private var error: String?
    @State private var hasPermission = false
    
    

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !hasPermission {
                Text("Find friends from your contacts")
                    .font(.headline).foregroundStyle(.white)
                Text("We match by email and phone. We don’t store your address book.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task { await requestAndSync() }
                } label: {
                    Label("Sync contacts", systemImage: "person.crop.circle.badge.plus")
                }.buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await syncContacts() }
                } label: {
                    Label("Re-sync contacts", systemImage: "arrow.clockwise")
                }.buttonStyle(.bordered)
            }

            if syncing { ProgressView().padding(.top, 6) }
            if let error { Text(error).foregroundStyle(.red) }

            if !suggestions.isEmpty {
                Divider().padding(.vertical, 4)
                Text("People you may know").font(.headline)
                ForEach(suggestions, id: \.id) { u in
                    SuggestedPersonRow(user: u)
                }
            } else if hasPermission && !syncing {
                ContentUnavailableView("No suggestions yet", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .task { await preloadSuggestions() }
    }

    private func requestAndSync() async {
        let store = CNContactStore()
        do {
            try await store.requestAccess(for: .contacts)
            hasPermission = true
            await syncContacts()
        } catch {
            hasPermission = false
            self.error = "Contacts permission denied."
        }
    }

    private func preloadSuggestions() async {
        do {
            // Ask server for mutuals-only first (no contacts yet)
            suggestions = try await SuggestionsAPI.suggestions(hashed: false, emails: [], phones: [], limit: 50)
        } catch {
            // ignore on first load
        }
    }

    private func syncContacts() async {
        syncing = true
        defer { syncing = false }
        do {
            let (emails, phones) = await readContacts()
            // Option A: call suggestions immediately using plaintext (server will hash)
            suggestions = try await SuggestionsAPI.suggestions(hashed: false, emails: emails, phones: phones, limit: 50)

            // Option B (optional): also persist your contacts server-side for faster future matching
            // try await SuggestionsAPI.importContacts(hashed: false, emails: emails, phones: phones)

        } catch {
            self.error = "Failed to sync contacts."
        }
    }

    private func readContacts() async -> ([String], [String]) {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        var emails = Set<String>()
        var phones = Set<String>()
        let req = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: req) { c, _ in
            for e in c.emailAddresses {
                let norm = String(e.value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !norm.isEmpty else { continue }
                emails.insert(norm)
            }
            for p in c.phoneNumbers {
                let digits = p.value.stringValue.filter(\.isNumber)
                guard !digits.isEmpty else { continue }
                phones.insert(digits)
            }
        }
        return (Array(emails), Array(phones))
    }
}

struct SuggestedPersonRow: View {
    let user: UserSummary
    @State private var working = false
    @State private var followed = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarUrl.flatMap(URL.init(string:))) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName ?? user.username)
                    .font(.headline)
                Text("@\(user.username)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Spacer()

            Button(followed ? "Following" : "Follow") {
                Task {
                    working = true
                    defer { working = false }
                    do {
                        try await SocialAPI.follow(userId: user.id)
                        followed = true
                    } catch {
                        // optionally show a toast / alert
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(working || followed)
        }
        .padding(.vertical, 6)
    }
}
