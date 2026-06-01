//
//  EquipmentProfileViewModel.swift
//  AmakaFlow
//
//  AMA-1995: Equipment Profile state + generated CoachingProfile mapping.
//

import Combine
import Foundation

@MainActor
final class EquipmentProfileViewModel: ObservableObject {
    typealias EquipmentInventory = Components.Schemas.EquipmentInventory
    typealias CoachingProfile = Components.Schemas.CoachingProfile
    typealias CoachingProfileUpsert = Components.Schemas.CoachingProfileUpsert

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction {
        case load
        case save
    }

    enum TrainingLocation: String, CaseIterable, Identifiable, Equatable {
        case home
        case gym
        case outdoor
        case travel

        var id: String { rawValue }

        var label: String {
            switch self {
            case .home: return "Home"
            case .gym: return "Commercial gym"
            case .outdoor: return "Outdoor"
            case .travel: return "Travelling"
            }
        }

        static func value(for label: String) -> String? {
            allCases.first { $0.label == label }?.rawValue
        }
    }

    struct EquipmentItem: Identifiable, Hashable {
        let id: String
        let label: String
    }

    struct Category: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let items: [EquipmentItem]
    }

    static let cardioCategory = Category(
        id: "cardio",
        title: "Cardio",
        subtitle: "Machines and erg options",
        items: [
            EquipmentItem(id: "treadmill", label: "Treadmill"),
            EquipmentItem(id: "bike", label: "Bike"),
            EquipmentItem(id: "rower", label: "Rower"),
            EquipmentItem(id: "assault_bike", label: "Assault bike"),
            EquipmentItem(id: "ski_erg", label: "Ski erg")
        ]
    )

    static let strengthCategory = Category(
        id: "strength",
        title: "Strength",
        subtitle: "Free weights and lifting setup",
        items: [
            EquipmentItem(id: "barbell", label: "Barbell"),
            EquipmentItem(id: "dumbbells", label: "Dumbbells"),
            EquipmentItem(id: "kettlebells", label: "Kettlebells"),
            EquipmentItem(id: "plates", label: "Plates"),
            EquipmentItem(id: "rack", label: "Rack"),
            EquipmentItem(id: "bench", label: "Bench")
        ]
    )

    static let bodyweightCategory = Category(
        id: "bodyweight",
        title: "Bodyweight",
        subtitle: "Pre-checked by default",
        items: [
            EquipmentItem(id: "pull_up_bar", label: "Pull-up bar"),
            EquipmentItem(id: "rings", label: "Rings"),
            EquipmentItem(id: "paralettes", label: "Paralettes")
        ]
    )

    static let mobilityCategory = Category(
        id: "mobility",
        title: "Mobility",
        subtitle: "Recovery and prep tools",
        items: [
            EquipmentItem(id: "foam_roller", label: "Foam roller"),
            EquipmentItem(id: "ball", label: "Ball"),
            EquipmentItem(id: "bands", label: "Bands")
        ]
    )

    static let categories: [Category] = [
        cardioCategory,
        strengthCategory,
        bodyweightCategory,
        mobilityCategory
    ]

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var isSaving = false
    @Published var searchText = ""
    @Published private(set) var collapsedCategoryIDs = Set<String>()
    @Published private(set) var selections: [String: [String: Bool]] = [:]
    @Published private(set) var dumbbellRangeKg = 20
    @Published private(set) var trainingLocation: TrainingLocation = .home

    private let apiService: APIServiceProviding
    private var profile: CoachingProfile?
    private var originalInventory: EquipmentInventory?
    private(set) var lastFailedAction: FailedAction?

    var isDirty: Bool {
        buildInventory() != originalInventory
    }

    var saveEnabled: Bool {
        isDirty && !isSaving && profile != nil
    }

    var selectedCount: Int {
        selections.values.reduce(0) { count, category in
            count + category.values.filter { $0 }.count
        }
    }

    var saveAccessibilityIdentifier: String { "equipment_profile_save" }

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
        applyInventory(Self.defaultInventory())
        originalInventory = buildInventory()
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            let fetched = try await apiService.getCoachingProfile()
            let activeProfile = fetched ?? Self.emptyProfileDraft()
            profile = activeProfile
            let loadedInventory = activeProfile.equipment
            let inventory = loadedInventory ?? Self.defaultInventory()
            applyInventory(inventory)
            originalInventory = buildInventory()
            state = loadedInventory == nil ? .empty : .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load
        }
    }

    func save() async {
        guard let profile, !isSaving else { return }
        isSaving = true
        ctaError = nil
        lastFailedAction = nil

        let inventory = buildInventory()
        let upsert = CoachingProfileUpsert(
            equipment: inventory,
            experienceLevel: profile.experienceLevel,
            goals: profile.goals,
            injuriesLimitations: profile.injuriesLimitations,
            preferredDays: profile.preferredDays,
            primaryGoal: profile.primaryGoal,
            sessionDurationMinutes: profile.sessionDurationMinutes,
            sessionsPerWeek: profile.sessionsPerWeek
        )

        do {
            let saved = try await apiService.upsertCoachingProfile(upsert)
            self.profile = saved
            let savedInventory = saved.equipment ?? inventory
            applyInventory(savedInventory)
            originalInventory = buildInventory()
            state = .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            lastFailedAction = .save
            if case .loading = state {
                state = .error(mapped)
            }
        }

        isSaving = false
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .save:
            await save()
        case .none:
            break
        }
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil

        if lastFailedAction == .load, let currentError {
            state = .error(currentError)
            return
        }

        if case .error = state {
            state = profile == nil ? .empty : .content
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: lastFailedAction == .load ? "equipment_profile_load" : "equipment_profile_save",
            error: ctaError,
            endpoint: "/v1/coaching/profile",
            userId: PairingService.shared.userProfile?.id
        )
    }

    func toggleCategory(_ category: Category) {
        if collapsedCategoryIDs.contains(category.id) {
            collapsedCategoryIDs.remove(category.id)
        } else {
            collapsedCategoryIDs.insert(category.id)
        }
    }

    func isCollapsed(_ category: Category) -> Bool {
        collapsedCategoryIDs.contains(category.id)
    }

    func isSelected(_ item: EquipmentItem, in category: Category) -> Bool {
        selections[category.id]?[item.id] ?? false
    }

    func setSelected(_ isSelected: Bool, item: EquipmentItem, in category: Category) {
        var updatedSelections = selections
        var categorySelections = updatedSelections[category.id] ?? [:]
        categorySelections[item.id] = isSelected
        updatedSelections[category.id] = categorySelections
        selections = updatedSelections
    }

    func toggleItem(_ item: EquipmentItem, in category: Category) {
        setSelected(!isSelected(item, in: category), item: item, in: category)
    }

    func selectLocation(_ location: TrainingLocation) {
        trainingLocation = location
    }

    func setDumbbellRangeKg(_ value: Int) {
        dumbbellRangeKg = Self.clampDumbbellRange(value)
    }

    func filteredCategories() -> [Category] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.categories }

        return Self.categories.compactMap { category in
            if category.title.lowercased().contains(query) {
                return category
            }
            let filteredItems = category.items.filter { item in
                item.label.lowercased().contains(query) || item.id.lowercased().contains(query)
            }
            guard !filteredItems.isEmpty else { return nil }
            return Category(
                id: category.id,
                title: category.title,
                subtitle: category.subtitle,
                items: filteredItems
            )
        }
    }

    func buildInventory() -> EquipmentInventory {
        EquipmentInventory(
            bodyweight: .init(additionalProperties: map(for: Self.bodyweightCategory)),
            cardio: .init(additionalProperties: map(for: Self.cardioCategory)),
            dumbbellRangeKg: isSelected(.init(id: "dumbbells", label: "Dumbbells"), in: Self.strengthCategory) ? dumbbellRangeKg : nil,
            mobility: .init(additionalProperties: map(for: Self.mobilityCategory)),
            strength: .init(additionalProperties: map(for: Self.strengthCategory)),
            trainingLocation: trainingLocation.rawValue
        )
    }

    static func clampDumbbellRange(_ value: Int) -> Int {
        min(max(value, 5), 100)
    }

    static func defaultInventory() -> EquipmentInventory {
        EquipmentInventory(
            bodyweight: .init(additionalProperties: Dictionary(uniqueKeysWithValues: bodyweightCategory.items.map { ($0.id, true) })),
            cardio: .init(additionalProperties: Dictionary(uniqueKeysWithValues: cardioCategory.items.map { ($0.id, false) })),
            dumbbellRangeKg: nil,
            mobility: .init(additionalProperties: Dictionary(uniqueKeysWithValues: mobilityCategory.items.map { ($0.id, false) })),
            strength: .init(additionalProperties: Dictionary(uniqueKeysWithValues: strengthCategory.items.map { ($0.id, false) })),
            trainingLocation: TrainingLocation.home.rawValue
        )
    }

    private static func emptyProfileDraft() -> CoachingProfile {
        CoachingProfile(
            createdAt: "",
            equipment: nil,
            experienceLevel: "intermediate",
            goals: nil,
            primaryGoal: "general_fitness",
            sessionsPerWeek: 3,
            updatedAt: "",
            userId: ""
        )
    }

    private func applyInventory(_ inventory: EquipmentInventory) {
        selections = [
            Self.cardioCategory.id: fillMap(source: inventory.cardio?.additionalProperties, category: Self.cardioCategory, defaultValue: false),
            Self.strengthCategory.id: fillMap(source: inventory.strength?.additionalProperties, category: Self.strengthCategory, defaultValue: false),
            Self.bodyweightCategory.id: fillMap(source: inventory.bodyweight?.additionalProperties, category: Self.bodyweightCategory, defaultValue: true),
            Self.mobilityCategory.id: fillMap(source: inventory.mobility?.additionalProperties, category: Self.mobilityCategory, defaultValue: false)
        ]
        dumbbellRangeKg = Self.clampDumbbellRange(inventory.dumbbellRangeKg ?? dumbbellRangeKg)
        trainingLocation = TrainingLocation(rawValue: inventory.trainingLocation) ?? .home
    }

    private func fillMap(source: [String: Bool]?, category: Category, defaultValue: Bool) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: category.items.map { item in
            (item.id, source?[item.id] ?? defaultValue)
        })
    }

    private func map(for category: Category) -> [String: Bool] {
        let categorySelections = selections[category.id] ?? [:]
        return Dictionary(uniqueKeysWithValues: category.items.map { item in
            (item.id, categorySelections[item.id] ?? false)
        })
    }
}
