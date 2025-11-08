import SwiftUI
import UIKit
import Stripe
import StripePaymentSheet
import PhotosUI


// MARK: - Shared formatters/coders (put near other globals)
private let isoDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

private let isoEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let plainNumberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    return f
}()

// FeeBreakdownDTO (add fields)
struct FeeBreakdownDTO: Codable {
    let currency: String
    let subtotalCents: Int
    let platformFeeCents: Int
    let stripeFeeCents: Int
    let serviceFeeCents: Int
    let totalCents: Int
    let servicePctUsed: Double?
    let stripePctUsed: Double?
    let stripeFixedCents: Int?

    // NEW:
    let originalSubtotalCents: Int?
    let discountCentsApplied: Int?
    let discountCodeApplied: String?
    let discountMessage: String?
}

private extension Int {
    func asUSD() -> String { String(format: "$%.2f", Double(self) / 100.0) }
}

struct RegisterTicketView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @State var event: Event
    @EnvironmentObject var userSession: UserSession
    let userEmail: String
    var onComplete: ([TicketDTO]) -> Void

    // 👇 set to true from the parent if the current user can edit the event
    var canEdit: Bool = false
    
    
    @State private var proofImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var proofUploadError: String? = nil


    @Environment(\.dismiss) var dismiss

    @State private var selectedTierId: Int?
    @State private var quantity = 1
    @State private var isLoading = false
    @State private var message = ""
    @State private var paymentSheet: PaymentSheet?
    @State private var isPaymentSheetPresented = false
    @State private var retryCount = 0
    @State private var showFreeTicketSuccess = false
    @Namespace private var animation

    @State private var showPaymentPopup = false
    @State private var selectedPaymentMethod: String = "card" // "card" | "zelle" | "pagoMovil" | "cash"
    @State private var isZelleAvailable: Bool = false

    @State private var showWaitlistPopup = false
    @State private var waitlistStatus: String? = nil // "pending", "approved", "denied"
    @State private var waitlistLoading = false

    @State private var showWaitlistStatusSheet = false
    @State private var waitlistSheetType: String? = nil // "pending" or "denied"
    @State private var autoDismissWorkItem: DispatchWorkItem?

    @State private var waitlistDragOffset: CGFloat = 0
    @State private var waitlistShouldHide: Bool = false

    @State private var loadedTiers: [TicketTier] = []

    @State private var isRefreshingEvent = false

    @State private var isLoadingTiers = true
    @State private var tiersError: String? = nil

    // 1) Add near your other @State/@Environment vars
    @State private var permissionsTick = 0   // forces toolbar re-eval when session loads

    // MARK: - Owner inline manage mode
    @State private var isManagingTiers = false
    @State private var draftTiers: [DraftTier] = []
    @State private var isSavingTiers = false
    @State private var tierSaveError: String?

    @AppStorage("vesPerUSD") private var vesPerUSD: Double = 179.43
    @State private var fxSource: String = "" // "override" | "bcv" | "cache" | ""

    // MARK: - Discounts state
    @State private var discountCode: String = ""
    @State private var discountMessage: String? = nil
    @State private var lastAppliedCode: String? = nil
    @State private var showDiscounts = false  // ⬅️ sheet for owner-only discount manager

    // Map current tiers to drafts
    private func makeDrafts(from tiers: [TicketTier]) -> [DraftTier] {
        let sorted = tiers.sorted { ($0.tierOrder ?? 0) < ($1.tierOrder ?? 0) }
        return sorted.enumerated().map { idx, t in
            DraftTier(
                id: Int64(t.id),
                name: t.name,
                price: t.price,
                quantity: t.availableQuantity,
                order: t.tierOrder ?? idx,
                hideQuantity: t.hideQuantity ?? false,
                description: t.description ?? "",
                startTime: t.startTime,
                endTime: t.endTime,
                forceOpen: t.forceOpen ?? false
            )
        }
    }
    
    // Simple reflection (no KVC, no generics)
    private func reflectValue(_ root: Any, key: String) -> Any? {
        Mirror(reflecting: root).children.first { $0.label == key }?.value
    }

    // Unwrap Optional<…> to the underlying value
    private func unwrapOptional(_ any: Any) -> Any? {
        let m = Mirror(reflecting: any)
        if m.displayStyle != .optional { return any }
        return m.children.first?.value // .some(...)
    }


    private var effectiveCanEdit: Bool {
        if canEdit { return true }
        if userSession.role.uppercased() == "ADMIN" { return true }
        if userSession.promotedEvents.contains(Int64(event.id)) { return true }

        // ownerUsername (String?)
        if let ownerUsername = reflectValue(event, key: "ownerUsername") as? String,
           ownerUsername == userSession.username { return true }

        // ownerId (Int64? / Int?)
        if let ownerId64 = reflectValue(event, key: "ownerId") as? Int64,
           ownerId64 == userSession.userId { return true }
        if let ownerId32 = reflectValue(event, key: "ownerId") as? Int,
           Int64(ownerId32) == userSession.userId { return true }

        // createdBy { id, username } (often Optional)
        if let createdByAny = reflectValue(event, key: "createdBy"),
           let createdBy = unwrapOptional(createdByAny) {

            let m = Mirror(reflecting: createdBy)

            if let id64 = m.children.first(where: { $0.label == "id" })?.value as? Int64,
               id64 == userSession.userId { return true }

            if let id32 = m.children.first(where: { $0.label == "id" })?.value as? Int,
               Int64(id32) == userSession.userId { return true }

            if let uname = m.children.first(where: { $0.label == "username" })?.value as? String,
               uname == userSession.username { return true }
        }

        return false
    }

    // Where your other helpers live
    private var isInVenezuela: Bool { event.country.lowercased() == "venezuela" }

    private var allowedVzlaMethods: [String] {
        var a: [String] = []
        if isZelleAvailable { a.append("zelle") }
        if event.allowPagoMovil ?? false { a.append("pagoMovil") }
        if event.allowCash ?? false { a.append("cash") }
        return a
    }

    private func enforceVzlaDefaultIfNeeded() {
        guard isInVenezuela else { return }
        // If we're in VE and the selection is card/empty, snap to the first allowed method (if any)
        if selectedPaymentMethod.isEmpty || selectedPaymentMethod == "card" {
            selectedPaymentMethod = allowedVzlaMethods.first ?? ""
        }
    }


    // ⬇️ Fee state
    @State private var fee: FeeBreakdownDTO? = nil

    // MARK: - Owner edit
    @State private var showEditEvent = false

    // MARK: - Tier helpers
    private func isSoldOut(_ t: TicketTier) -> Bool {
        return t.availableQuantity <= 0
    }

    private func hasEnded(_ t: TicketTier, now: Date) -> Bool {
        t.endTime.map { now > $0 } ?? false
    }
    private func hasNotStarted(_ t: TicketTier, now: Date) -> Bool {
        t.startTime.map { now < $0 } ?? false
    }
    private func isLockedByTime(_ t: TicketTier, now: Date) -> Bool {
        // start time lock is skipped if forceOpen; end time is always enforced
        let force = t.forceOpen ?? false
        let startLocked = (!force) && hasNotStarted(t, now: now)
        let endLocked = hasEnded(t, now: now)
        return startLocked || endLocked
    }
    // Safe reflection for Swift structs (no KVC, no crashes)
    private func reflected<T>(_ root: Any, key: String) -> T? {
        Mirror(reflecting: root).children.first { $0.label == key }?.value as? T
    }

    private func isLockedByOrder(_ t: TicketTier, nextId: Int?) -> Bool {
        let force = t.forceOpen ?? false
        guard let nextId = nextId else { return false }   // ← don't lock by order if we couldn't compute nextId
        return (!force) && (t.id != nextId)
    }

    private func isUnavailable(_ t: TicketTier, now: Date, nextId: Int?) -> Bool {
        let orderLocked = isLockedByOrder(t, nextId: nextId)   // ← uses the safe function above
        return isSoldOut(t) || isLockedByTime(t, now: now) || orderLocked
    }

    var selectedTier: TicketTier? {
        let source = loadedTiers.isEmpty ? event.ticketTiers : loadedTiers
        return source.first(where: { $0.id == selectedTierId })
    }

    // MARK: - Precomputed lists (keeps the body simple)
    private var baseTiers_: [TicketTier] { loadedTiers.isEmpty ? event.ticketTiers : loadedTiers }

    private var sortedTiers_: [TicketTier] {
        baseTiers_.sorted { ($0.tierOrder ?? 0) < ($1.tierOrder ?? 0) }
    }

    private var nextId_: Int? { nextAvailableTierId(in: baseTiers_, now: Date()) }

    private var hasAvailableTier_: Bool {
        let now = Date()
        let nextId = nextId_
        return sortedTiers_.contains { !isUnavailable($0, now: now, nextId: nextId) }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // Header (title + Buy/Manage switch)
                    headerSection

                    // Owner-only quick actions
                    if effectiveCanEdit {
                        HStack(spacing: 10) {
                            Button {
                                showDiscounts = true
                            } label: {
                                Label(lang == "es" ? "Descuentos" : "Discounts", systemImage: "tag.fill")
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                            .accessibilityLabel(Text(lang == "es" ? "Administrar descuentos" : "Manage discounts"))
                            Spacer()
                        }
                    }

                    // Main content (either loader / no tickets / Manage / Buy)
                    mainSection

                    // Error banner
                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Spacer()
                }
                .padding()
            }

            // Overlays
            if showPaymentPopup { paymentPopupView }
            if showWaitlistPopup { waitlistPopupView }
            if showWaitlistStatusSheet { miniWaitlistSheet() }
            if isRefreshingEvent { refreshingOverlay }
        }
        // Animations
        .animation(.easeInOut, value: showPaymentPopup)
        .animation(.spring(response: 0.7, dampingFraction: 0.82, blendDuration: 0.21),
                   value: showWaitlistStatusSheet)

        // Lifecycle
        .onAppear {
            isZelleAvailable = !(event.zelleEmail?.isEmpty ?? true) || !(event.zellePhone?.isEmpty ?? true)
            if event.listOnly ?? false { checkWaitlistStatus() }
            fetchUpdatedEventData()
            fetchEventTiers()
            fetchFeeQuote()
            Task { await refreshVESRateIfNeeded(force: false) }
            enforceVzlaDefaultIfNeeded()
        }
        // Recompute fee when selection changes
        .onChange(of: selectedTierId) { _ in
            let maxQ = min(10, selectedTier?.availableQuantity ?? 10)
            if quantity > maxQ { quantity = maxQ }
            fetchFeeQuote()
        }
        .onChange(of: quantity) { _ in fetchFeeQuote() }
        .onChange(of: selectedPaymentMethod) { _ in
            fetchFeeQuote()
            Task { await refreshVESRateIfNeeded(force: false) }  // ← keep rate fresh when switching to VES methods
        }
        .onReceive(
            Timer.publish(every: 30*60, on: .main, in: .common).autoconnect()
        ) { _ in
            Task { await refreshVESRateIfNeeded(force: true) }   // ← periodic refresh
        }
        // Re-evaluate permissions when session loads
        .onReceive(NotificationCenter.default.publisher(for: .userSessionLoaded)) { _ in
            permissionsTick &+= 1
        }
        .id(permissionsTick)

        // Toolbar (keep if you still want the sheet-based editor)
        .toolbar {
            if effectiveCanEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditEvent = true } label: {
                        Label(lang == "es" ? "Editar" : "Edit", systemImage: "pencil")
                    }
                }
            }
        }

        // Optional: old sheet editor (non-tier stuff)
        .sheet(isPresented: $showEditEvent) {
            EditEventView(
                event: event,
                onSave: { updated in
                    self.event = updated
                    self.isZelleAvailable = !(updated.zelleEmail?.isEmpty ?? true) || !(updated.zellePhone?.isEmpty ?? true)
                    self.fetchEventTiers()
                    self.fetchFeeQuote()
                },
                onDelete: { self.dismiss() }
            )
        }

        // Owner-only Discount Manager sheet
        .sheet(isPresented: $showDiscounts) {
            NavigationView {
                DiscountManagerView(eventId: Int(event.id))
                    .environmentObject(userSession)
                    .navigationTitle(lang == "es" ? "Descuentos" : "Discounts")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }

        // Floating pencil (toggle sheet editor)
        .overlay(alignment: .topTrailing) {
            if effectiveCanEdit {
                Button { showEditEvent = true } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.gold)
                        .shadow(radius: 2)
                }
                .padding(.top, 8)
                .padding(.trailing, 14)
                .accessibilityLabel(Text(lang == "es" ? "Editar evento" : "Edit event"))
            }
        }
    }

    @ViewBuilder
    private func paymentOptionButton(_ method: String, icon: String, titleES: String, titleEN: String) -> some View {
        Button { selectedPaymentMethod = method } label: {
            HStack { Image(systemName: icon); Text(lang == "es" ? titleES : titleEN) }
                .foregroundColor(selectedPaymentMethod == method ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedPaymentMethod == method ? Color.gold : Color.white.opacity(0.1))
                .cornerRadius(14)
        }
    }

    // MARK: - Manage Tiers (modern card style)
    @ViewBuilder
    private func ManageTiersSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Label(lang == "es" ? "Gestionar Niveles de Entradas" : "Manage Ticket Tiers",
                      systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: {
                    let nextOrder = (draftTiers.map { $0.order }.max() ?? -1) + 1
                    draftTiers.append(DraftTier(id: nil,
                                                name: lang == "es" ? "Nuevo Nivel" : "New Tier",
                                                price: 0,
                                                quantity: 0,
                                                order: nextOrder,
                                                hideQuantity: false,
                                                description: "",
                                                startTime: nil,
                                                endTime: nil,
                                                forceOpen: false))
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text(lang == "es" ? "Añadir" : "Add")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(Color.gold))
                    .foregroundColor(.black)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .accessibilityLabel(Text(lang == "es" ? "Añadir nivel" : "Add tier"))
            }

            // Cards
            VStack(spacing: 14) {
                ForEach($draftTiers, id: \.self) { $draft in
                    TierEditorCard(
                        draft: $draft,
                        lang: lang,
                        onDelete: {
                            if let idx = draftTiers.firstIndex(of: draft) {
                                draftTiers.remove(at: idx)
                            }
                        }
                    )
                }
            }

            if let err = tierSaveError, !err.isEmpty {
                Text(err).font(.footnote).foregroundColor(.red)
            }

            // Save
            PrimaryActionButton(
                title: isSavingTiers
                    ? (lang == "es" ? "Guardando..." : "Saving...")
                    : (lang == "es" ? "Guardar cambios" : "Save changes"),
                isLoading: isSavingTiers,
                action: saveTiers
            )
            .disabled(isSavingTiers || draftTiers.contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }

    // MARK: - Money helpers
    private func formatMoney(usd amount: Double, currency: String?) -> String {
        let useVES = (currency?.uppercased() == "VES") || (selectedPaymentMethod == "pagoMovil")
        let value  = useVES ? (amount * max(vesPerUSD, 0)) : amount

        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        if useVES {
            f.currencyCode = "VES"
            f.locale = Locale(identifier: "es_VE")
            return f.string(from: NSNumber(value: value)) ?? String(format: "Bs. %.2f", value)
        } else {
            f.currencyCode = "USD"
            f.locale = Locale(identifier: "en_US")
            return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
        }
    }

    private func formatCents(_ cents: Int, currency: String?) -> String {
        let usd = Double(cents) / 100.0
        return formatMoney(usd: usd, currency: currency)
    }

    @MainActor
    private func refreshVESRateIfNeeded(force: Bool = false) async {
        if !force, let cached = FXAPI.cachedRate(), !FXAPI.shouldRefresh() {
            vesPerUSD = cached
            fxSource = "cache"
            return
        }
        do {
            let (live, src) = try await FXAPI.fetchVESPerUSD()
            vesPerUSD = live
            fxSource = src         // "override" or "bcv"
            FXAPI.save(rate: live)
        } catch {
            if let cached = FXAPI.cachedRate() {
                vesPerUSD = cached
                fxSource = "cache"
            } else {
                fxSource = ""
            }
        }
    }

    private func saveTiers() {
        guard let token = TokenManager.shared.getAccessToken() else {
            tierSaveError = lang == "es" ? "No autenticado." : "Not authenticated."
            return
        }
        tierSaveError = nil
        isSavingTiers = true

        // server deletes tiers that are not sent; keep only our drafts
        let payload = EventUpdatePayload(
            ticketTiers: draftTiers.enumerated().map { idx, d in
                TicketTierRequestPayload(
                    id: d.id, // nil => create
                    name: d.name.trimmingCharacters(in: .whitespaces),
                    price: max(0, d.price),
                    quantity: max(0, d.quantity),
                    order: idx,                    // keep UI order
                    hideQuantity: d.hideQuantity,
                    description: d.description.isEmpty ? nil : d.description,
                    startTime: d.startTime,
                    endTime: d.endTime,
                    forceOpen: d.forceOpen
                )
            }
        )

        var req = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)")!)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601

        do {
            req.httpBody = try enc.encode(payload)
        } catch {
            isSavingTiers = false
            tierSaveError = "Encode error: \(error.localizedDescription)"
            return
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async { isSavingTiers = false }

            if let err = err {
                DispatchQueue.main.async { tierSaveError = err.localizedDescription }
                return
            }

            guard let http = resp as? HTTPURLResponse else {
                DispatchQueue.main.async { tierSaveError = "No response." }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { tierSaveError = "Server \(http.statusCode): \(body)" }
                return
            }

            // ✅ Refresh from server so quantities/order sync to buyer UI
            DispatchQueue.main.async {
                self.fetchEventTiers()
                self.fetchUpdatedEventData()
                // self.isManagingTiers = false
            }
        }.resume()
    }

    @ViewBuilder
    private func miniWaitlistSheet() -> some View {
        let isPending = waitlistSheetType == "pending"
        let isDenied = waitlistSheetType == "denied"
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                if isPending {
                    Text("⏳").font(.system(size: 46))
                        .scaleEffect(showWaitlistStatusSheet ? 1.1 : 1)
                        .animation(.spring(), value: showWaitlistStatusSheet)
                }
                if isDenied {
                    Text("❌").font(.system(size: 46))
                        .scaleEffect(showWaitlistStatusSheet ? 1.1 : 1)
                        .animation(.spring(), value: showWaitlistStatusSheet)
                }
                Text(isPending ?
                     (lang == "es" ? "Solicitud Enviada" : "Request Sent") :
                     (lang == "es" ? "Acceso Denegado" : "Access Denied"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isDenied ? .red : .white)
                    .padding(.bottom, -4)

                Text(isPending
                     ? (lang == "es"
                        ? "Ya solicitaste acceso. Espera la aprobación del organizador."
                        : "You've already requested access. Please wait for approval.")
                     : (lang == "es"
                        ? "El organizador ha denegado tu acceso a este evento."
                        : "The organizer denied your access to this event.")
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)

                Button(action: { dismissWaitlistSheet() }) {
                    Text(lang == "es" ? "Cerrar" : "Close")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isDenied ? Color.red : Color.gold))
                        .foregroundColor(.black)
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 28)
            .background(
                MaterialBlurView(style: .systemUltraThinMaterialDark)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 10)
            )
            .frame(maxWidth: 380)
            .padding(.bottom, 24)
            .offset(y: waitlistShouldHide ? 600 : waitlistDragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 { waitlistDragOffset = value.translation.height }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            dismissWaitlistSheet()
                        } else {
                            withAnimation(.spring()) { waitlistDragOffset = 0 }
                        }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.7, dampingFraction: 0.82, blendDuration: 0.25), value: waitlistShouldHide)
        }
        .ignoresSafeArea()
    }

    private func dismissWaitlistSheet() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82, blendDuration: 0.25)) {
            waitlistShouldHide = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            waitlistShouldHide = false
            showWaitlistStatusSheet = false
            waitlistDragOffset = 0
        }
    }

    @ViewBuilder
    private func paymentDetailsView() -> some View {
        let needsProof = (selectedPaymentMethod == "zelle" || selectedPaymentMethod == "pagoMovil")

        VStack(spacing: 10) {
            switch selectedPaymentMethod {
            case "zelle":
                VStack(spacing: 4) {
                    if let email = event.zelleEmail, !email.isEmpty {
                        HStack { Image(systemName: "envelope"); Text(email) }.foregroundColor(.white)
                    }
                    if let phone = event.zellePhone, !phone.isEmpty {
                        HStack { Image(systemName: "phone"); Text(phone) }.foregroundColor(.white)
                    }
                    Text(lang == "es"
                         ? "Después de pagar por Zelle, sube una foto del comprobante y toca Pagar."
                         : "After sending your Zelle payment, upload a photo of the confirmation and tap Pay.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                }

            case "pagoMovil":
                VStack(spacing: 6) {
                    if let phone = event.pagoMovilPhone { Text("📱 \(phone)").foregroundColor(.white) }
                    if let ci = event.pagoMovilCi { Text("🪪 C.I.: \(ci)").foregroundColor(.white) }
                    if let bank = event.pagoMovilBank { Text("🏦 \(bank)").foregroundColor(.white) }
                    Text(lang == "es"
                         ? "Después de pagar por Pago Móvil, sube una foto del comprobante y toca Pagar."
                         : "After sending your Pago Móvil payment, upload a photo of the confirmation and tap Pay.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                }

            case "cash":
                if let note = event.cashNote {
                    VStack(spacing: 6) {
                        Text("📝 " + note)
                            .font(.footnote)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(lang == "es"
                             ? "Toca Pagar para notificar al organizador."
                             : "Tap Pay to notify the organizer.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.6))
                    }
                }

            default:
                EmptyView()
            }

            // Receipt attachment UI (Zelle/Pago Móvil)
            if needsProof {
                VStack(spacing: 10) {
                    if let proofImage {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: proofImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button {
                                withAnimation { self.proofImage = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .padding(6)
                        }
                    } else {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label(lang == "es" ? "Adjuntar comprobante" : "Attach receipt",
                                  systemImage: "photo.on.rectangle")
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.gold, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    if let err = proofUploadError, !err.isEmpty {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            // A minimal UIKit picker
            ImagePickerr(image: $proofImage)
                .ignoresSafeArea()
        }
    }


    private func showWaitlistSheet(type: String) {
        waitlistSheetType = type
        withAnimation(.spring(response: 0.7, dampingFraction: 0.80, blendDuration: 0.32)) {
            showWaitlistStatusSheet = true
        }
        if type == "pending" {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else if type == "denied" {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        autoDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { dismissWaitlistSheet() }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func fetchEventTiers() {
        // start loader
        DispatchQueue.main.async {
            self.isLoadingTiers = true
            self.tiersError = nil
        }

        guard let token = TokenManager.shared.getAccessToken() else {
            DispatchQueue.main.async {
                self.message = lang == "es"
                    ? "❌ No autenticado. Inicia sesión nuevamente."
                    : "❌ Not authenticated. Please log in again."
                self.isLoadingTiers = false
            }
            return
        }

        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/tiers")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer {
                DispatchQueue.main.async { self.isLoadingTiers = false }
            }

            guard let data = data else {
                DispatchQueue.main.async { self.tiersError = "No data" }
                return
            }

            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601

            guard let tiers = try? dec.decode([TicketTier].self, from: data) else {
                DispatchQueue.main.async { self.tiersError = "Failed to decode tiers" }
                return
            }

            DispatchQueue.main.async {
                self.loadedTiers = tiers
                if self.selectedTierId == nil {
                    self.selectedTierId = self.nextAvailableTierId(in: tiers, now: Date())
                }
            }
        }.resume()
    }
    
    // ✅ Build the form body but DO NOT set request.httpBody when using uploadTask(from:)
    private func makeMultipartRequest(url: URL, token: String, image: UIImage) -> (URLRequest, Data)? {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let jpeg = image.jpegData(compressionQuality: 0.65) else { return nil }

        var body = Data()
        let filename = "proof-\(Int(Date().timeIntervalSince1970)).jpg"

        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")

        return (request, body)
    }

    /// Upload same proof image to many ticket IDs in parallel.
    /// Calls `done(successCount, total, firstErrorMessage?)` on completion.
    private func uploadProofs(ticketIds: [Int], image: UIImage, done: @escaping (Int, Int, String?) -> Void) {
        guard !ticketIds.isEmpty else { done(0, 0, nil); return }
        let group = DispatchGroup()
        var success = 0
        var firstError: String?

        for tid in ticketIds {
            group.enter()
            self.uploadProof(ticketId: tid, image: image) { ok, err in
                if ok { success += 1 } else if firstError == nil { firstError = err }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            done(success, ticketIds.count, firstError)
        }
    }

    private func uploadProof(ticketId: Int, image: UIImage, _ completion: @escaping (Bool, String?) -> Void) {
        guard let token = TokenManager.shared.getAccessToken() else { completion(false, "Auth missing"); return }
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/\(ticketId)/proof") else {
            completion(false, "Bad URL"); return
        }
        guard let (request0, body) = makeMultipartRequest(url: url, token: token, image: image) else {
            completion(false, "Failed to build request"); return
        }

        var request = request0
        request.setValue("application/json", forHTTPHeaderField: "Accept")   // 👈

        URLSession.shared.uploadTask(with: request, from: body) { data, resp, err in
            if let err = err { completion(false, err.localizedDescription); return }
            guard let http = resp as? HTTPURLResponse else { completion(false, "No response"); return }
            guard (200...299).contains(http.statusCode) else {
                let server = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Server \(http.statusCode)"
                completion(false, server)
                return
            }
            completion(true, nil)
        }.resume()
    }



    private func fetchFeeQuote() {
        guard !isInVenezuela || selectedPaymentMethod != "card" else {
            self.fee = nil
            return
        }
        guard let tier = selectedTier, quantity >= 1 else { fee = nil; return }
        guard let t = TokenManager.shared.getAccessToken() else {
            DispatchQueue.main.async {
                self.message = lang == "es" ? "❌ No autenticado. Inicia sesión nuevamente." : "❌ Not authenticated. Please log in again."
                self.fee = nil
            }
            return
        }

        var comps = URLComponents(string: "https://backendevent-etce.onrender.com/api/tickets/quote")!

        // 👇 IMPORTANT: send unitPriceCents
        let unitPriceCents = Int((tier.price * 100).rounded())

        var q: [URLQueryItem] = [
            URLQueryItem(name: "eventId", value: "\(event.id)"),
            URLQueryItem(name: "ticketTierId", value: "\(tier.id)"),
            URLQueryItem(name: "quantity", value: "\(quantity)"),
            URLQueryItem(name: "paymentMethod", value: selectedPaymentMethod),
            URLQueryItem(name: "unitPriceCents", value: "\(unitPriceCents)")
        ]
        if !discountCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q.append(URLQueryItem(name: "discountCode", value: discountCode.uppercased()))
        }
        comps.queryItems = q

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { self.fee = nil }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Server \(http.statusCode)"
                DispatchQueue.main.async {
                    self.fee = nil
                    self.discountMessage = msg
                    self.lastAppliedCode = nil
                }
                return
            }
            if let dto = try? isoDecoder.decode(FeeBreakdownDTO.self, from: data) {
                DispatchQueue.main.async {
                    self.fee = dto
                    self.discountMessage = dto.discountMessage
                    self.lastAppliedCode = dto.discountCodeApplied
                }
            } else {
                DispatchQueue.main.async { self.fee = nil }
            }
        }.resume()
    }



    func checkWaitlistStatus() {
        guard event.listOnly ?? false else { return }
        guard let token = TokenManager.shared.getAccessToken() else {
            print("❌ No token found in TokenManager! User must re-authenticate.")
            DispatchQueue.main.async {
                self.message = lang == "es"
                    ? "❌ Tu sesión expiró. Inicia sesión nuevamente."
                    : "❌ Your session expired. Please log in again."
            }
            return
        }

        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let raw = String(data: data, encoding: .utf8),
               raw == "null" || raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async { self.showWaitlistPopup = true }
                return
            }
            do {
                let entry = try JSONDecoder().decode(WaitlistEntry.self, from: data)
                DispatchQueue.main.async { self.waitlistStatus = entry.status.lowercased() }
            } catch {
                print("❌ Failed to decode waitlist entry: \(error)")
                DispatchQueue.main.async { self.showWaitlistPopup = true }
            }
        }.resume()
    }

    private func decodeFeeBreakdown(from any: Any) -> FeeBreakdownDTO? {
        guard JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any),
              let dto = try? JSONDecoder().decode(FeeBreakdownDTO.self, from: data) else { return nil }
        return dto
    }

    @ViewBuilder private var headerSection: some View {
        VStack(spacing: 6) {
            Text(lang == "es" ? "🎟️ Registrarse para" : "🎟️ Register for")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Text(event.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            if effectiveCanEdit {
                Picker("", selection: $isManagingTiers) {
                    Text(lang == "es" ? "Comprar" : "Buy").tag(false)
                    Text(lang == "es" ? "Gestionar" : "Manage").tag(true)
                }
                .pickerStyle(.segmented)
                .segmentedWhiteText()
                .onChange(of: isManagingTiers) { active in
                    if active {
                        let base = baseTiers_
                        draftTiers = makeDrafts(from: base)
                        tierSaveError = nil
                    }
                }
            }
        }
    }

    @ViewBuilder private var mainSection: some View {
        if isLoadingTiers || isRefreshingEvent {
            TiersLoadingView(lang: lang)
        } else if sortedTiers_.isEmpty || !hasAvailableTier_ {
            NoTicketsView(lang: lang)
        } else {
            Group {
                if isManagingTiers {
                    AnyView(ManageTiersSection())
                } else {
                    AnyView(buyerSection(sortedTiers: sortedTiers_, nextId: nextId_))
                }
            }
        }
    }

    @ViewBuilder
    private func buyerSection(sortedTiers: [TicketTier], nextId: Int?) -> some View {
        let now = Date()

        // Ticket list
        VStack(alignment: .leading, spacing: 14) {
            Text(lang == "es" ? "Selecciona un Nivel de Entrada" : "Select a Ticket Tier")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(sortedTiers, id: \.id) { tier in
                let tierIsUnavailable = isUnavailable(tier, now: now, nextId: nextId)
                let tierIsSelected = selectedTierId == tier.id
                let tierIsSoldOut = isSoldOut(tier)
                let tierStartLocked = !((tier.forceOpen) ?? false) && hasNotStarted(tier, now: now)
                let tierHasWindow = (tier.startTime != nil) && (tier.endTime != nil)

                TierRowCard(
                    tier: tier,
                    lang: lang,
                    isUnavailable: tierIsUnavailable,
                    isSelected: tierIsSelected,
                    isSoldOut: tierIsSoldOut,
                    startLocked: tierStartLocked,
                    hasWindow: tierHasWindow,
                    start: tier.startTime,
                    end: tier.endTime
                ) {
                    let isListOnly = event.listOnly ?? false
                    if !tierIsUnavailable && isListOnly && waitlistStatus == "pending" {
                        showWaitlistSheet(type: "pending")
                    } else if !tierIsUnavailable && isListOnly && waitlistStatus == "denied" {
                        showWaitlistSheet(type: "denied")
                    } else if !tierIsUnavailable && (!isListOnly || waitlistStatus == "approved") {
                        selectedTierId = tier.id
                    }
                }
            }
        }

        // Qty + Discount + fee
        VStack(spacing: 8) {
            // Quantity
            let maxQ = min(10, selectedTier?.availableQuantity ?? 10)
            Stepper(
                lang == "es" ? "Cantidad: \(quantity)" : "Quantity: \(quantity)",
                value: $quantity,
                in: 1...maxQ
            )
            .foregroundColor(.white)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)

            // 🔻 Discount code entry
            VStack(alignment: .leading, spacing: 8) {
                Text(lang == "es" ? "Código de descuento (opcional)" : "Discount code (optional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))

                HStack {
                    TextField(lang == "es" ? "CÓDIGO" : "CODE", text: $discountCode)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        discountCode = discountCode.uppercased().trimmingCharacters(in: .whitespaces)
                        fetchFeeQuote()
                    } label: {
                        Text(lang == "es" ? "Aplicar" : "Apply")
                            .fontWeight(.semibold)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.gold, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundColor(.black)
                    }
                    if !discountCode.isEmpty {
                        Button {
                            discountCode = ""
                            lastAppliedCode = nil
                            discountMessage = nil
                            fetchFeeQuote()
                        } label: {
                            Text(lang == "es" ? "Quitar" : "Clear")
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                if let msg = discountMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.top, 2)

            // Fee block
            if let tier = selectedTier {
                if let fee = fee {
                    VStack(spacing: 8) {
                        let displayCurrency = fee.currency.isEmpty ? (selectedPaymentMethod == "pagoMovil" ? "VES" : "USD")
                                                                   : fee.currency

                        // If discount applied, show original subtotal + discount lines
                        if let original = fee.originalSubtotalCents, original > 0,
                           let disc = fee.discountCentsApplied, disc > 0 {
                            HStack {
                                Text("\(tier.name) x\(quantity) (subtotal)")
                                Spacer()
                                Text(formatCents(original, currency: displayCurrency))
                            }.foregroundStyle(.white)

                            HStack {
                                let code = fee.discountCodeApplied ?? discountCode
                                Text(lang == "es" ? "Descuento" : "Discount")
                                    .overlay(
                                        Text(code.isEmpty ? "" : " (\(code))")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7)),
                                        alignment: .trailing
                                    )
                                Spacer()
                                Text("− " + formatCents(disc, currency: displayCurrency))
                            }.foregroundStyle(.white)

                            Divider().background(Color.white.opacity(0.15))

                            HStack {
                                Text(lang == "es" ? "Subtotal nuevo" : "New subtotal")
                                Spacer()
                                Text(formatCents(fee.subtotalCents, currency: displayCurrency))
                            }.foregroundStyle(.white)
                        } else {
                            // No discount; regular subtotal line
                            HStack { Text("\(tier.name) x\(quantity)"); Spacer(); Text(formatCents(fee.subtotalCents, currency: displayCurrency)) }
                                .foregroundStyle(.white)
                        }

                        HStack { Text(lang == "es" ? "Tarifa de servicio" : "Service fee"); Spacer(); Text(formatCents(fee.serviceFeeCents, currency: displayCurrency)) }
                            .foregroundStyle(.white)
                        Divider().background(Color.white.opacity(0.2))
                        HStack { Text(lang == "es" ? "Total" : "Total").bold(); Spacer(); Text(formatCents(fee.totalCents, currency: displayCurrency)).bold() }
                            .foregroundStyle(.white)

                    }
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(14)
                } else {
                    Text(lang == "es" ? "Calculando total..." : "Calculating total...")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                        .padding(.top, 4)
                }
            }
        }

        // Pay button
        let hasNonCardPayments: Bool = {
            let venezuela = event.country.lowercased() == "venezuela"
            let altPayments = (event.allowPagoMovil ?? false) || (event.allowCash ?? false)
            return isZelleAvailable || (venezuela && altPayments)
        }()
        
        let mustUsePopup = isInVenezuela
        let anyAlt = isZelleAvailable || (event.allowPagoMovil ?? false) || (event.allowCash ?? false)


        Button {
            if mustUsePopup || anyAlt {
                withAnimation { showPaymentPopup = true }
                //selectedPaymentMethod = "card"
            } else {
                startCheckout()
            }
        } label: {
            HStack {
                Spacer()
                Text(isLoading
                     ? (lang == "es" ? "Procesando..." : "Processing...")
                     : (lang == "es" ? "Pagar Ahora" : "Pay Now"))
                .fontWeight(.bold)
                .padding(.vertical, 12)
                .foregroundColor(.black)
                Spacer()
            }
            .background(isLoading ? Color.gray : Color.gold)
            .cornerRadius(16)
        }
        .disabled(isLoading || selectedTier == nil || (isInVenezuela && allowedVzlaMethods.isEmpty))
        
        if isInVenezuela && allowedVzlaMethods.isEmpty {
            Text(lang == "es"
                 ? "El organizador no ha configurado métodos de pago para Venezuela."
                 : "The organizer hasn’t configured Venezuela payment methods yet.")
            .font(.footnote)
            .foregroundColor(.white.opacity(0.7))
        }
    }

    @ViewBuilder private var paymentPopupView: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showPaymentPopup = false }

            VStack(spacing: 18) {
                Text("💰 " + (lang == "es" ? "Total a Pagar" : "Total to Pay"))
                    .font(.title3.bold())
                    .foregroundColor(.white)

                let displayCurrencyForPopup = fee?.currency ?? (selectedPaymentMethod == "pagoMovil" ? "VES" : "USD")

                let displayTotal: String = {
                    if let fee = fee { return formatCents(fee.totalCents, currency: displayCurrencyForPopup) }
                    if let tier = selectedTier { return formatMoney(usd: Double(quantity) * tier.price, currency: displayCurrencyForPopup) }
                    return formatMoney(usd: 0, currency: displayCurrencyForPopup)
                }()
                Text(displayTotal)
                    .font(.largeTitle.bold())
                    .foregroundColor(.gold)

                VStack(spacing: 12) {
                    if isZelleAvailable {
                        paymentOptionButton("zelle", icon: "banknote.fill",
                                            titleES: "Contribuir con Zelle", titleEN: "Pay with Zelle")
                    }
                    if isInVenezuela && (event.allowPagoMovil ?? false) {
                        paymentOptionButton("pagoMovil", icon: "iphone.gen3",
                                            titleES: "Pago Móvil", titleEN: "Pago Móvil")
                    }
                    if isInVenezuela && (event.allowCash ?? false) {
                        paymentOptionButton("cash", icon: "banknote",
                                            titleES: "Pagar en Efectivo", titleEN: "Pay with Cash")
                    }

                    // ⛔️ Hide Card when in VE
                    if !isInVenezuela {
                        paymentOptionButton("card", icon: "creditcard.fill",
                                            titleES: "Pagar con Tarjeta", titleEN: "Pay with Card")
                    }
                }

                // Small policy note
                if isInVenezuela {
                    Text(lang == "es"
                         ? "En Venezuela solo se aceptan Pago Móvil, Zelle o efectivo."
                         : "In Venezuela, only Pago Móvil, Zelle, or cash are accepted.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                }
                paymentDetailsView()

                let needsProof = (selectedPaymentMethod == "zelle" || selectedPaymentMethod == "pagoMovil")
                let canManualPay = !needsProof || (needsProof && proofImage != nil)

                Button {
                    guard canManualPay else {
                        proofUploadError = lang == "es" ? "Adjunta la foto del comprobante." : "Please attach the receipt photo."
                        return
                    }
                    showPaymentPopup = false
                    startCheckout()
                } label: {
                    Text(lang == "es" ? (needsProof ? "Pagar y Enviar Comprobante" : "Pagar")
                                      : (needsProof ? "Pay & Send Receipt" : "Pay"))
                        .fontWeight(.bold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(canManualPay ? Color.gold : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(16)
                }
                .disabled(!canManualPay)


                Button(action: { showPaymentPopup = false }) {
                    Text(lang == "es" ? "Cancelar" : "Cancel")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(22)
            .padding(.horizontal)
            .frame(maxWidth: 350)
        }
        .transition(.scale)
        .zIndex(10)
    }

    @ViewBuilder private var waitlistPopupView: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showWaitlistPopup = false }

            VStack(spacing: 16) {
                Text("📝 " + (lang == "es" ? "Este evento es con lista" : "This event uses a list"))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                Text(lang == "es"
                     ? "Debes solicitar acceso antes de poder registrarte. Notificaremos al organizador."
                     : "You must request access before registering. We’ll notify the organizer.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))

                if waitlistStatus == nil {
                    Button {
                        sendWaitlistRequest()
                    } label: {
                        if waitlistLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(lang == "es" ? "Solicitar Acceso" : "Request Access")
                                .bold()
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gold)
                                .foregroundColor(.black)
                                .cornerRadius(14)
                        }
                    }
                } else {
                    let msg = waitlistStatus == "pending"
                        ? (lang == "es" ? "⏳ Solicitud Enviada" : "⏳ Request Sent")
                        : waitlistStatus == "denied"
                            ? (lang == "es" ? "❌ Acceso Denegado" : "❌ Access Denied")
                            : (lang == "es" ? "✅ Acceso Aprobado" : "✅ Access Approved")
                    Text(msg)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Button(lang == "es" ? "Cerrar" : "Close") {
                    showWaitlistPopup = false
                }
                .foregroundColor(.white.opacity(0.6))
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal, 24)
        }
        .transition(.scale)
        .zIndex(20)
    }

    @ViewBuilder private var refreshingOverlay: some View {
        Color.black.opacity(0.3).ignoresSafeArea()
        ProgressView(lang == "es" ? "Actualizando..." : "Updating...")
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(1.5)
    }

    private func startCheckout() {
        paymentSheet = nil
        isPaymentSheetPresented = false
        guard let tier = selectedTier else { return }
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "❌ Not authenticated. Please log in again."
            return
        }
        
        if isInVenezuela && selectedPaymentMethod == "card" {
            DispatchQueue.main.async {
                self.message = lang == "es"
                ? "En Venezuela solo se aceptan Pago Móvil, Zelle o efectivo."
                : "In Venezuela, only Pago Móvil, Zelle, or cash are accepted."
                self.showPaymentPopup = true
            }
            return
        }

        isLoading = true
        message = ""

        let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/checkout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [
            "eventId": event.id,
            "ticketTierId": tier.id,
            "quantity": quantity,
            "email": userEmail,
            "paymentMethod": selectedPaymentMethod
        ]
        // NEW: include discountCode if present
        if !discountCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["discountCode"] = discountCode.uppercased()
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async { isLoading = false }

            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { self.message = "Failed to get response." }
                return
            }

            if let bd = json["breakdown"], let dto = decodeFeeBreakdown(from: bd) {
                DispatchQueue.main.async {
                    self.fee = dto
                    self.discountMessage = dto.discountMessage
                    self.lastAppliedCode = dto.discountCodeApplied
                }
            }

            if let isFree = json["free"] as? Bool, isFree {
                DispatchQueue.main.async {
                    withAnimation { self.showFreeTicketSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.fetchTickets()
                        self.fetchUpdatedEventData()
                    }
                }
                return
            }

            if let isManual = json["manual"] as? Bool, isManual {
                // One receipt → many tickets
                let ids: [Int] = (json["ticketIds"] as? [NSNumber])?.map { $0.intValue }
                                ?? (json["ticketId"] as? NSNumber).map { [$0.intValue] }
                                ?? []

                // If we have a proof image, upload to ALL tickets that were created.
                if let image = self.proofImage, !ids.isEmpty {
                    self.uploadProofs(ticketIds: ids, image: image) { okCount, total, errMsg in
                        DispatchQueue.main.async {
                            if okCount == total {
                                self.message = lang == "es"
                                  ? "📸 Comprobante enviado para \(total) entrada(s)."
                                  : "📸 Receipt uploaded for \(total) ticket(s)."
                            } else if okCount > 0 {
                                self.message = lang == "es"
                                  ? "📸 Enviados \(okCount)/\(total). \(errMsg ?? "")"
                                  : "📸 Uploaded \(okCount)/\(total). \(errMsg ?? "")"
                            } else {
                                self.message = errMsg ?? (lang == "es" ? "No se pudo subir el comprobante." : "Failed to upload receipt.")
                            }
                            self.fetchTickets()
                            self.fetchUpdatedEventData()
                        }
                    }
                } else {
                    // No proof attached; still created tickets in PENDING for owner to review
                    DispatchQueue.main.async {
                        self.message = lang == "es"
                          ? "✅ Compra registrada. Puedes adjuntar el comprobante desde tu perfil."
                          : "✅ Purchase recorded. You can attach the receipt from your profile."
                        self.fetchTickets()
                        self.fetchUpdatedEventData()
                    }
                }
                return
            }

            guard let clientSecret = json["clientSecret"] as? String,
                  let paymentIntentId = extractPaymentIntentId(from: clientSecret) else {
                DispatchQueue.main.async { self.message = "Failed to get client secret." }
                return
            }

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "WKND Events"
            config.applePay = .init(merchantId: "merchant.com.wknd.events", merchantCountryCode: "US")

            DispatchQueue.main.async {
                self.paymentSheet = PaymentSheet(
                    paymentIntentClientSecret: clientSecret,
                    configuration: config
                )
                self.presentPaymentSheet(paymentIntentId: paymentIntentId)
            }
        }.resume()
    }
    
    


    private func fetchUpdatedEventData() {
        guard let token = TokenManager.shared.getAccessToken() else {
            DispatchQueue.main.async {
                self.message = lang == "es"
                    ? "❌ No autenticado. Inicia sesión nuevamente."
                    : "❌ Not authenticated. Please log in again."
            }
            return
        }

        isRefreshingEvent = true
        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async { isRefreshingEvent = false }
            guard let data = data else { return }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            if let updatedEvent = try? decoder.decode(Event.self, from: data) {
                DispatchQueue.main.async { self.event = updatedEvent }
            }
        }.resume()
    }

    func sendWaitlistRequest() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        waitlistLoading = true

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist/request")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let fullName = userSession.fullName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "AnonymousUser"
        let ref = (UserDefaults.standard.string(forKey: "wknd_ref") ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let body = ref.isEmpty ? "fullName=\(fullName)" : "fullName=\(fullName)&ref=\(ref)"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                waitlistLoading = false
                waitlistStatus = "pending"
            }
        }.resume()
    }


    private func presentPaymentSheet(paymentIntentId: String) {
        guard let sheet = paymentSheet else {
            message = "Payment sheet not ready."
            return
        }

        if isPaymentSheetPresented { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let topVC = topViewController() {
                if topVC.presentedViewController != nil {
                    if retryCount < 3 {
                        retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.presentPaymentSheet(paymentIntentId: paymentIntentId)
                        }
                        return
                    } else {
                        message = "Couldn't open payment screen. Try again later."
                        retryCount = 0
                        return
                    }
                }

                retryCount = 0
                isPaymentSheetPresented = true

                sheet.present(from: topVC) { result in
                    isPaymentSheetPresented = false
                    paymentSheet = nil

                    switch result {
                    case .completed:
                        confirmBackend(paymentIntentId: paymentIntentId)
                        fetchUpdatedEventData()
                    case .canceled:
                        message = "❌ Payment canceled."
                        fetchUpdatedEventData()
                    case .failed(let error):
                        message = "❌ Payment failed: \(error.localizedDescription)"
                        fetchUpdatedEventData()
                    }
                }
            } else {
                message = "❌ Couldn't find view controller"
            }
        }
    }

    private func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let controller = controller ?? UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController

        if let nav = controller as? UINavigationController {
            return topViewController(controller: nav.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return topViewController(controller: tab.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }

    private func confirmBackend(paymentIntentId: String) {
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "Missing token for confirmation."
            return
        }

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/tickets/confirm?paymentIntentId=\(paymentIntentId)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchTickets()
            fetchUpdatedEventData()
        }.resume()
    }

    private func fetchTickets() {
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "Token missing."
            return
        }
        let emailParam = userEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userEmail
        let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my?email=\(emailParam)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data {
                    let dec = JSONDecoder()
                    dec.keyDecodingStrategy = .convertFromSnakeCase      // 👈 important
                    if let tickets = try? dec.decode([TicketDTO].self, from: data) {
                        self.onComplete(tickets)
                        self.selectedTierId = nil
                        self.quantity = 1
                        self.dismiss()
                    } else {
                        self.message = "Failed to load tickets."
                    }
                }
            }
        }.resume()
    }

    private func extractPaymentIntentId(from clientSecret: String) -> String? {
        clientSecret.components(separatedBy: "_secret").first
    }

    // ✅ Next available tier (use the provided array)
    private func nextAvailableTierId(in tiers: [TicketTier], now: Date) -> Int? {
        let sorted = tiers.sorted { ($0.tierOrder ?? 0) < ($1.tierOrder ?? 0) }
        for tier in sorted {
            let notSoldOut = tier.availableQuantity > 0
            let hasStarted = tier.startTime.map { now >= $0 } ?? true
            let notEnded   = tier.endTime.map   { now <= $0 } ?? true
            if notSoldOut && hasStarted && notEnded {
                return tier.id
            }
        }
        return nil
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Helper for all tiers
extension TicketTier {
    func availabilityText(lang: String) -> String {
        if availableQuantity <= 0 {
            return lang == "es" ? "Agotado" : "Sold out"
        }
        if hideQuantity == true {
            return lang == "es" ? "Disponible" : "Available"
        }
        return lang == "es"
            ? "\(availableQuantity) disponibles"
            : "\(availableQuantity) left"
    }
}

// MARK: - Tier Row
private struct TierRowCard: View {
    let tier: TicketTier
    let lang: String
    let isUnavailable: Bool
    let isSelected: Bool
    let isSoldOut: Bool
    let startLocked: Bool
    let hasWindow: Bool
    let start: Date?
    let end: Date?
    let onTap: () -> Void

    var body: some View {
        let cardFill: Color = isUnavailable ? Color.white.opacity(0.02) : Color.white.opacity(0.05)
        let cardStroke: Color = (isSelected && !isUnavailable) ? Color.gold : Color.clear

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // 🔹 Tier name
                    Text(tier.name)
                        .font(.headline)
                        .foregroundColor(isUnavailable ? .gray : .white)

                    // 🔹 Price + availability (uses helper)
                    Text("\(String(format: "$%.2f", tier.price)) • \(tier.availabilityText(lang: lang))")
                        .font(.caption)
                        .foregroundColor(isUnavailable ? .gray.opacity(0.6) : .white.opacity(0.7))

                    // 🔹 Description (optional)
                    if let desc = tier.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(2)
                    }

                    // 🔹 Status chips
                    if isSoldOut {
                        Text(lang == "es" ? "❌ Agotado" : "❌ Sold Out")
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else if startLocked {
                        Text(lang == "es" ? "⏰ Aún no disponible" : "⏰ Not yet available")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else if hasWindow, let s = start, let e = end {
                        Text("⏰ \(format(s)) - \(format(e))")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()

                // 🔹 Right-side icons
                if isSelected && !isUnavailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.gold)
                        .font(.title3)
                } else if startLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(cardStroke, lineWidth: 1.5))
        .opacity(isUnavailable ? 0.4 : 1.0)
        .onTapGesture { onTap() }
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Helpers

struct MaterialBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

private struct NoTicketsView: View {
    let lang: String
    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 100)
            VStack(spacing: 12) {
                Image(systemName: "nosign")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                Text(lang == "es"
                     ? "Este evento no tiene entradas disponibles"
                     : "This event has no available tickets")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(.horizontal)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TiersLoadingView: View {
    let lang: String
    var body: some View {
        VStack(spacing: 18) {
            ProgressView(lang == "es" ? "Cargando entradas..." : "Loading tickets...")
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .foregroundColor(.white)

            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 80)
                    .overlay(
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.18)).frame(height: 14)
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)).frame(height: 12)
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)).frame(height: 12)
                        }
                        .padding()
                        .redacted(reason: .placeholder)
                    )
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Backend payloads (Encodable)
private struct TicketTierRequestPayload: Encodable {
    var id: Int64?
    var name: String
    var price: Double
    var quantity: Int
    var order: Int
    var hideQuantity: Bool?
    var description: String?
    var startTime: Date?
    var endTime: Date?
    var forceOpen: Bool
}

private struct EventUpdatePayload: Encodable {
    var ticketTiers: [TicketTierRequestPayload]
    // all other EventRequest fields omitted => unchanged server-side
}

// MARK: - Tier Editor Card
private struct TierEditorCard: View {
    @Binding var draft: DraftTier
    let lang: String
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Title row
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField(lang == "es" ? "Nombre del nivel" : "Tier name", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .fieldBox()

                // Reorder hint
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.45))
                    .accessibilityHidden(true)
            }

            // Price + Qty
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(lang == "es" ? "Precio" : "Price", systemImage: "dollarsign.circle.fill")
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                    TextField("0.00", value: $draft.price, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .foregroundColor(.white)
                        .fieldBox()
                        .font(.system(.body, design: .rounded))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(lang == "es" ? "Cantidad" : "Qty", systemImage: "number.circle.fill")
                        .font(.caption).foregroundColor(.white.opacity(0.7))

                    QuantityControl(value: $draft.quantity)
                }
            }

            // Toggles
            VStack(spacing: 10) {
                ToggleRow(
                    title: lang == "es" ? "Forzar apertura ahora" : "Force open now",
                    systemImage: "bolt.fill",
                    isOn: $draft.forceOpen
                )
                ToggleRow(
                    title: lang == "es" ? "Ocultar cantidad" : "Hide quantity",
                    systemImage: "eye.slash.fill",
                    isOn: $draft.hideQuantity
                )
            }

            // Sale window
            DisclosureGroup {
                VStack(spacing: 10) {
                    DateRow(
                        title: lang == "es" ? "Inicio" : "Start",
                        date: Binding(
                            get: { draft.startTime ?? Date() },
                            set: { draft.startTime = $0 }
                        ),
                        clearAction: { draft.startTime = nil }
                    )
                    DateRow(
                        title: lang == "es" ? "Fin" : "End",
                        date: Binding(
                            get: { draft.endTime ?? Date() },
                            set: { draft.endTime = $0 }
                        ),
                        clearAction: { draft.endTime = nil }
                    )
                }
                .padding(.top, 6)
            } label: {
                Label(lang == "es" ? "Ventana de venta (opcional)" : "Sale window (optional)",
                      systemImage: "alarm.waves.left.and.right.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            }
            .tint(.gold)
            .disclosureBox()

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text(lang == "es" ? "Descripción (opcional)" : "Description (optional)")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
                TextField("", text: $draft.description, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .foregroundColor(.white)
                    .fieldBox()
            }

            // Footer
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label(lang == "es" ? "Eliminar nivel" : "Delete tier", systemImage: "trash")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// Primary CTA
private struct PrimaryActionButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading { ProgressView().tint(.black) }
                Text(title).bold()
                Spacer()
            }
            .padding(.vertical, 12)
            .background(isLoading ? Color.gray : Color.gold)
            .foregroundColor(.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// Qty control: minus / textfield / plus
private struct QuantityControl: View {
    @Binding var value: Int
    var min: Int = 0
    var max: Int = 100_000

    @State private var text: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconCircleButton(systemName: "minus") {
                value = Swift.max(min, value - 1)
                text = "\(value)"
            }

            TextField("", text: $text)
                .keyboardType(.numberPad)
                .focused($isEditing)
                .multilineTextAlignment(.center)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 36)
                .onChange(of: text) { new in
                    let digits = new.filter(\.isNumber)
                    if digits != new { text = digits }
                    if let n = Int(digits) {
                        value = Swift.max(min, Swift.min(max, n))
                    }
                }
                .onChange(of: value) { v in
                    if text != "\(v)" { text = "\(v)" }
                }
                .onAppear { text = "\(value)" }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isEditing = false }
                    }
                }

            IconCircleButton(systemName: "plus") {
                value = Swift.min(max, value + 1)
                text = "\(value)"
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct IconCircleButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundColor(.black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.gold))
        }
        .buttonStyle(.plain)
    }
}

// Toggle row with icon
private struct ToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(.gold)
            Toggle(title, isOn: $isOn)
                .tint(.gold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
    }
}

// Date row with clear button
private struct DateRow: View {
    let title: String
    @Binding var date: Date
    var clearAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DatePicker(title, selection: $date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .foregroundColor(.white)

            Spacer()

            Button(action: clearAction) {
                Label("Clear", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.white.opacity(0.6))
            }
            .accessibilityLabel(Text("Clear"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .fieldBox()
    }
}

// Nice field background + disclosure styling
private struct FieldBoxModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
private extension View {
    func fieldBox() -> some View { modifier(FieldBoxModifier()) }
    func disclosureBox() -> some View {
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// Editable local copy of a tier (id nil = new)
struct DraftTier: Identifiable, Hashable {
    var id: Int64?
    var name: String
    var price: Double
    var quantity: Int
    var order: Int
    var hideQuantity: Bool
    var description: String
    var startTime: Date?
    var endTime: Date?
    var forceOpen: Bool
}

private struct SegmentedWhiteText: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
            let ap = UISegmentedControl.appearance()
            ap.setTitleTextAttributes(attrs, for: .normal)
            ap.setTitleTextAttributes(attrs, for: .selected)
        }
    }
}
private extension View {
    func segmentedWhiteText() -> some View { modifier(SegmentedWhiteText()) }
}

// MARK: - Discount models & Manager

// Replace your Swift DiscountDTO with this:

// MARK: - Discount models
struct DiscountDTO: Codable, Identifiable, Hashable {
    enum DiscountType: String, Codable { case PERCENT, AMOUNT }

    var id: Int64?
    var eventId: Int64
    var code: String
    var type: DiscountType
    var value: Double
    var appliesToTicketTierId: Int64?
    var maxUses: Int?
    var usedCount: Int?
    var minQty: Int?
    var maxQty: Int?
    var startsAt: Date?
    var endsAt: Date?
    var active: Bool? = true

    // NEW (global discounted-ticket cap across redemptions)
    var ticketLimit: Int?
    var ticketsRedeemed: Int?
}


struct DiscountResultDTO: Codable {
    let valid: Bool
    let message: String
    let codeApplied: String?
    let discountCents: Int
    let remainingTickets: Int   // NEW
}



// MARK: - Discount Manager (owner-only)
struct DiscountManagerView: View {
    @EnvironmentObject var userSession: UserSession
    let eventId: Int

    // Owner + data
    @State private var ownerId: Int?
    @State private var items: [DiscountDTO] = []
    @State private var isLoading = false
    @State private var error: String?

    // Create form state
    @State private var creating = DiscountDTO(
        id: nil, eventId: 0, code: "",
        type: .PERCENT, value: 10.0,
        appliesToTicketTierId: nil, maxUses: nil, usedCount: nil,
        minQty: nil, maxQty: nil, startsAt: nil, endsAt: nil, active: true
    )

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Label("Discount Codes", systemImage: "tag.fill")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.gold)
                                .padding(8)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .accessibilityLabel(Text("Refresh"))
                    }

                    if !isOwner() {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill").foregroundColor(.gold)
                            Text("Only the event owner can manage discounts.")
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                    }

                    // Create card
                    CreateDiscountCard(
                        creating: $creating,
                        isOwner: isOwner(),
                        onCreate: { Task { await create() } }
                    )

                    // Existing list
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    } else if items.isEmpty {
                        Text("No discount codes yet.")
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(items, id: \.self) { d in
                                DiscountRowCard(
                                    d: d,
                                    isOwner: isOwner(),
                                    onToggleActive: { newVal in
                                        Task { await update(d, key: "active", value: newVal) }
                                    },
                                    onDelete: {
                                        Task { await remove(d) }
                                    }
                                )
                            }
                        }
                    }

                    if let err = error, !err.isEmpty {
                        Text(err)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
            }
        }
        .onAppear { Task { await load() } }
    }

    // MARK: - Networking

    private func authedRequest(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = TokenManager.shared.getAccessToken() {
            r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        r.httpBody = body
        return r
    }

    private func loadURL(_ path: String) -> URL {
        URL(string: "https://backendevent-etce.onrender.com\(path)")!
    }

    private func load() async {
        if ownerId == nil { ownerId = await fetchOwnerId() }
        guard isOwner() else {
            await MainActor.run { error = "Only event owner can manage discounts."; items = [] }
            return
        }

        await MainActor.run { isLoading = true; error = nil }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            let url = loadURL("/api/discounts?eventId=\(eventId)")
            let (data, resp) = try await URLSession.shared.data(for: authedRequest(url))
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Server \(http.statusCode)"
                throw NSError(domain: "Discounts", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            let list = try isoDecoder.decode([DiscountDTO].self, from: data)
            await MainActor.run { items = list }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func create() async {
        guard isOwner() else { return }

        // Local validation (mirror backend)
        guard !creating.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { self.error = "Code required." }; return
        }
        guard creating.value > 0 else {
            await MainActor.run { self.error = "Value must be greater than 0." }; return
        }

        do {
            var dto = creating
            dto.eventId = Int64(eventId)

            let data = try isoEncoder.encode(dto)
            let (respData, resp) = try await URLSession.shared.data(
                for: authedRequest(loadURL("/api/discounts"), method: "POST", body: data)
            )
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: respData, encoding: .utf8) ?? "Server \(http.statusCode)"
                throw NSError(domain: "Discounts", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            _ = try isoDecoder.decode(DiscountDTO.self, from: respData) // shape check
            await load()
            await MainActor.run {
                creating.code = ""
                creating.value = dto.type == .PERCENT ? 10 : 1
                error = nil
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func update(_ d: DiscountDTO, key: String, value: Any) async {
        do {
            var patch = d
            if key == "active", let v = value as? Bool { patch.active = v }

            let data = try isoEncoder.encode(patch)
            let (respData, resp) = try await URLSession.shared.data(
                for: authedRequest(loadURL("/api/discounts/\(d.id ?? 0)"), method: "PUT", body: data)
            )
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let msg = String(data: respData, encoding: .utf8) ?? "Update failed"
                throw NSError(domain: "Discounts", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            _ = try isoDecoder.decode(DiscountDTO.self, from: respData)
            await load()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func remove(_ d: DiscountDTO) async {
        do {
            _ = try await URLSession.shared.data(
                for: authedRequest(loadURL("/api/discounts/\(d.id ?? 0)"), method: "DELETE")
            )
            await load()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func isOwner() -> Bool {
        if userSession.role.uppercased() == "ADMIN" { return true }
        guard let ownerId = ownerId else { return false }
        return userSession.userId == ownerId
    }

    // Event owner lookup (to gate UI)
    private struct OwnerEnvelope: Decodable { let createdBy: OwnerUser? }
    private struct OwnerUser: Decodable { let id: Int? }

    private func fetchOwnerId() async -> Int? {
        guard let t = TokenManager.shared.getAccessToken() else { return nil }
        var req = URLRequest(url: loadURL("/events/\(eventId)"))
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let env = try? JSONDecoder().decode(OwnerEnvelope.self, from: data),
               let id = env.createdBy?.id { return id }
        } catch {}
        return nil
    }
}

// MARK: - Row & Create Cards

private struct DiscountRowCard: View {
    let d: DiscountDTO
    let isOwner: Bool
    var onToggleActive: (Bool) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(d.code)
                        .font(.headline)
                        .foregroundColor(.white)

                    if (d.active ?? true) {
                        Text("Active")
                            .font(.caption2)
                            .foregroundColor(.black)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(Color.gold))
                    } else {
                        Text("Inactive")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    Spacer()
                }

                Text(d.type == .PERCENT ? "\(Int(d.value))%" : String(format: "$%.2f", d.value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))

                if let used = d.usedCount, let max = d.maxUses {
                    Text("Uses \(used)/\(max)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                // NEW: show global ticket cap progress (or unlimited)
                if let cap = d.ticketLimit {
                    let redeemed = d.ticketsRedeemed ?? 0
                    Text("Cap: \(redeemed)/\(cap) tickets")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("Cap: Unlimited")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            Spacer()

            if isOwner {
                VStack(spacing: 8) {
                    Toggle("",
                           isOn: Binding(
                               get: { d.active ?? true },
                               set: { onToggleActive($0) }
                           )
                    )
                    .labelsHidden()
                    .tint(.gold)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash.fill")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct CreateDiscountCard: View {
    @Binding var creating: DiscountDTO
    let isOwner: Bool
    var onCreate: () -> Void

    // NEW: local text field for optional ticket cap
    @State private var ticketLimitText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create")
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 10) {
                TextField("CODE", text: Binding(
                    get: { creating.code },
                    set: { creating.code = $0.uppercased() }
                ))
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .foregroundColor(.white)
                .fieldBox()

                Picker("",
                       selection: Binding(
                           get: { creating.type },
                           set: { creating.type = $0 }
                       )
                ) {
                    Text("Percent").tag(DiscountDTO.DiscountType.PERCENT)
                    Text("Amount").tag(DiscountDTO.DiscountType.AMOUNT)
                }
                .pickerStyle(.segmented)
                .segmentedWhiteText()
                .frame(width: 170)
            }

            TextField(
                creating.type == .PERCENT ? "Percent (e.g. 10)" : "Amount in USD (e.g. 5.00)",
                value: $creating.value,
                formatter: plainNumberFormatter
            )
            .keyboardType(.decimalPad)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundColor(.white)
            .fieldBox()

            // NEW: Optional global ticket cap across redemptions
            TextField("Ticket cap (optional)", text: $ticketLimitText)
                .keyboardType(.numberPad)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .foregroundColor(.white)
                .fieldBox()
                .onChange(of: ticketLimitText) { new in
                    // keep only digits
                    let digits = new.filter(\.isNumber)
                    if digits != new { ticketLimitText = digits }
                }
                .onAppear {
                    // prefill from existing value if editing draft
                    if let cap = creating.ticketLimit, ticketLimitText.isEmpty {
                        ticketLimitText = String(cap)
                    }
                }

            ToggleRow(
                title: "Active",
                systemImage: "bolt.fill",
                isOn: Binding(
                    get: { creating.active ?? true },
                    set: { creating.active = $0 }
                )
            )

            HStack {
                Spacer()
                Button(action: {
                    // push optional cap into the DTO
                    if ticketLimitText.trimmingCharacters(in: .whitespaces).isEmpty {
                        creating.ticketLimit = nil
                    } else {
                        creating.ticketLimit = Int(ticketLimitText)
                    }
                    onCreate()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create").bold()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.gold))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .disabled(!isOwner ||
                          creating.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          creating.value <= 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(
                LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.03)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}



struct ImagePickerr: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> some UIViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerr
        init(_ p: ImagePickerr) { self.parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.parent.image = object as? UIImage
                }
            }
        }
    }
}
