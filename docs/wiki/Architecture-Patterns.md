# Architecture Patterns Guide

Complete guide to integrating LuxAnalytics with different app architectures and design patterns.

## Architecture Overview

LuxAnalytics is designed to work seamlessly with any iOS app architecture while maintaining clean separation of concerns and testability.

### Supported Patterns

- **MVVM (Model-View-ViewModel)**
- **MVP (Model-View-Presenter)**
- **VIPER (View-Interactor-Presenter-Entity-Router)**
- **Clean Architecture**
- **MVC (Model-View-Controller)**
- **The Composable Architecture (TCA)**
- **Redux/Flux patterns**

## MVVM Integration

### MVVM with SwiftUI

```swift
import SwiftUI
import LuxAnalytics

// MARK: - Model
struct User {
    let id: String
    let name: String
    let email: String
}

struct UserAction {
    let type: String
    let timestamp: Date
    let metadata: [String: Any]
}

// MARK: - ViewModel
@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userRepository: UserRepositoryProtocol
    private let analyticsService: AnalyticsServiceProtocol
    
    init(
        userRepository: UserRepositoryProtocol = UserRepository(),
        analyticsService: AnalyticsServiceProtocol = AnalyticsService()
    ) {
        self.userRepository = userRepository
        self.analyticsService = analyticsService
    }
    
    func loadUser(_ userId: String) async {
        isLoading = true
        errorMessage = nil
        
        await analyticsService.track("user_profile_load_started", metadata: [
            "user_id": userId
        ])
        
        do {
            user = try await userRepository.fetchUser(userId)
            
            await analyticsService.track("user_profile_loaded", metadata: [
                "user_id": userId,
                "load_success": true
            ])
            
        } catch {
            errorMessage = error.localizedDescription
            
            await analyticsService.track("user_profile_load_failed", metadata: [
                "user_id": userId,
                "error": error.localizedDescription
            ])
        }
        
        isLoading = false
    }
    
    func updateProfile(_ updatedUser: User) async {
        await analyticsService.track("user_profile_update_started")
        
        do {
            try await userRepository.updateUser(updatedUser)
            user = updatedUser
            
            await analyticsService.track("user_profile_updated", metadata: [
                "user_id": updatedUser.id,
                "update_success": true
            ])
            
        } catch {
            errorMessage = error.localizedDescription
            
            await analyticsService.track("user_profile_update_failed", metadata: [
                "user_id": updatedUser.id,
                "error": error.localizedDescription
            ])
        }
    }
    
    func trackUserAction(_ action: UserAction) async {
        await analyticsService.track("user_action_performed", metadata: [
            "action_type": action.type,
            "user_id": user?.id ?? "unknown"
        ])
    }
}

// MARK: - View
struct UserProfileView: View {
    @StateObject private var viewModel = UserProfileViewModel()
    let userId: String
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Loading...")
            } else if let user = viewModel.user {
                UserDetailView(user: user, viewModel: viewModel)
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error)
            }
        }
        .task {
            await viewModel.loadUser(userId)
        }
        .analyticsScreen("user_profile", metadata: [
            "user_id": userId
        ])
    }
}

struct UserDetailView: View {
    let user: User
    let viewModel: UserProfileViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(user.name)
                .font(.title)
            
            Text(user.email)
                .font(.subheadline)
            
            Button("Edit Profile") {
                Task {
                    await viewModel.trackUserAction(UserAction(
                        type: "edit_profile_tapped",
                        timestamp: Date(),
                        metadata: [:]
                    ))
                }
            }
            .analyticsButton("edit_profile_button_tapped")
        }
    }
}

// MARK: - Analytics Service Protocol
protocol AnalyticsServiceProtocol {
    func track(_ eventName: String, metadata: [String: Any]) async
    func setUser(_ userId: String) async
    func flush() async
}

class AnalyticsService: AnalyticsServiceProtocol {
    func track(_ eventName: String, metadata: [String: Any] = [:]) async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track(eventName, metadata: metadata)
    }
    
    func setUser(_ userId: String) async {
        let analytics = await LuxAnalytics.shared
        await analytics.setUser(userId)
    }
    
    func flush() async {
        await LuxAnalytics.flush()
    }
}
```

### MVVM with UIKit

```swift
import UIKit
import LuxAnalytics

// MARK: - ViewModel
class ProductListViewModel {
    
    // MARK: - Properties
    private(set) var products: [Product] = []
    private let productRepository: ProductRepositoryProtocol
    private let analyticsService: AnalyticsServiceProtocol
    
    // Callbacks for view updates
    var onProductsUpdated: (() -> Void)?
    var onLoadingStateChanged: ((Bool) -> Void)?
    var onErrorOccurred: ((String) -> Void)?
    
    // MARK: - Initialization
    init(
        productRepository: ProductRepositoryProtocol = ProductRepository(),
        analyticsService: AnalyticsServiceProtocol = AnalyticsService()
    ) {
        self.productRepository = productRepository
        self.analyticsService = analyticsService
    }
    
    // MARK: - Public Methods
    func loadProducts() async {
        await MainActor.run {
            onLoadingStateChanged?(true)
        }
        
        await analyticsService.track("product_list_load_started")
        
        do {
            let fetchedProducts = try await productRepository.fetchProducts()
            
            await MainActor.run {
                self.products = fetchedProducts
                self.onProductsUpdated?()
                self.onLoadingStateChanged?(false)
            }
            
            await analyticsService.track("product_list_loaded", metadata: [
                "product_count": fetchedProducts.count,
                "load_success": true
            ])
            
        } catch {
            await MainActor.run {
                self.onErrorOccurred?(error.localizedDescription)
                self.onLoadingStateChanged?(false)
            }
            
            await analyticsService.track("product_list_load_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }
    
    func selectProduct(at index: Int) async {
        guard index < products.count else { return }
        
        let product = products[index]
        
        await analyticsService.track("product_selected", metadata: [
            "product_id": product.id,
            "product_name": product.name,
            "selection_index": index,
            "total_products": products.count
        ])
    }
    
    func trackListInteraction(_ interactionType: String) async {
        await analyticsService.track("product_list_interaction", metadata: [
            "interaction_type": interactionType,
            "product_count": products.count
        ])
    }
}

// MARK: - View Controller
class ProductListViewController: UIViewController {
    
    // MARK: - Outlets
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
    
    // MARK: - Properties
    private let viewModel: ProductListViewModel
    
    // MARK: - Initialization
    init(viewModel: ProductListViewModel = ProductListViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        self.viewModel = ProductListViewModel()
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        
        Task {
            await viewModel.loadProducts()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        Task {
            await viewModel.analyticsService.track("product_list_screen_viewed")
        }
    }
    
    // MARK: - Setup
    private func setupUI() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ProductTableViewCell.self, forCellReuseIdentifier: "ProductCell")
    }
    
    private func bindViewModel() {
        viewModel.onProductsUpdated = { [weak self] in
            self?.tableView.reloadData()
        }
        
        viewModel.onLoadingStateChanged = { [weak self] isLoading in
            if isLoading {
                self?.loadingIndicator.startAnimating()
            } else {
                self?.loadingIndicator.stopAnimating()
            }
        }
        
        viewModel.onErrorOccurred = { [weak self] errorMessage in
            let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }
}

// MARK: - Table View Data Source & Delegate
extension ProductListViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.products.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProductCell", for: indexPath) as! ProductTableViewCell
        cell.configure(with: viewModel.products[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        Task {
            await viewModel.selectProduct(at: indexPath.row)
        }
        
        // Navigate to product detail
        let product = viewModel.products[indexPath.row]
        let detailVC = ProductDetailViewController(product: product)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        Task {
            await viewModel.trackListInteraction("scroll")
        }
    }
}
```

## VIPER Architecture

```swift
import Foundation
import LuxAnalytics

// MARK: - Protocols
protocol ProductListViewProtocol: AnyObject {
    func showProducts(_ products: [Product])
    func showLoading()
    func hideLoading()
    func showError(_ message: String)
}

protocol ProductListPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didSelectProduct(at index: Int)
    func didScrollList()
}

protocol ProductListInteractorProtocol: AnyObject {
    func fetchProducts() async
    func trackEvent(_ eventName: String, metadata: [String: Any]) async
}

protocol ProductListRouterProtocol: AnyObject {
    func navigateToProductDetail(_ product: Product)
}

// MARK: - Entity
struct Product {
    let id: String
    let name: String
    let price: Double
    let category: String
}

// MARK: - Interactor
class ProductListInteractor: ProductListInteractorProtocol {
    
    weak var presenter: ProductListPresenterProtocol?
    private let productRepository: ProductRepositoryProtocol
    private let analyticsService: AnalyticsServiceProtocol
    
    init(
        productRepository: ProductRepositoryProtocol = ProductRepository(),
        analyticsService: AnalyticsServiceProtocol = AnalyticsService()
    ) {
        self.productRepository = productRepository
        self.analyticsService = analyticsService
    }
    
    func fetchProducts() async {
        await trackEvent("product_fetch_started")
        
        do {
            let products = try await productRepository.fetchProducts()
            
            await trackEvent("product_fetch_completed", metadata: [
                "product_count": products.count,
                "success": true
            ])
            
            // Notify presenter (would need proper callback mechanism)
            
        } catch {
            await trackEvent("product_fetch_failed", metadata: [
                "error": error.localizedDescription,
                "success": false
            ])
        }
    }
    
    func trackEvent(_ eventName: String, metadata: [String: Any] = [:]) async {
        await analyticsService.track(eventName, metadata: metadata)
    }
}

// MARK: - Presenter
class ProductListPresenter: ProductListPresenterProtocol {
    
    weak var view: ProductListViewProtocol?
    var interactor: ProductListInteractorProtocol?
    var router: ProductListRouterProtocol?
    
    private var products: [Product] = []
    
    func viewDidLoad() {
        view?.showLoading()
        
        Task {
            await interactor?.trackEvent("product_list_view_loaded")
            await interactor?.fetchProducts()
        }
    }
    
    func didSelectProduct(at index: Int) {
        guard index < products.count else { return }
        
        let product = products[index]
        
        Task {
            await interactor?.trackEvent("product_selected", metadata: [
                "product_id": product.id,
                "product_name": product.name,
                "selection_index": index
            ])
        }
        
        router?.navigateToProductDetail(product)
    }
    
    func didScrollList() {
        Task {
            await interactor?.trackEvent("product_list_scrolled")
        }
    }
}

// MARK: - View
class ProductListViewController: UIViewController, ProductListViewProtocol {
    
    var presenter: ProductListPresenterProtocol?
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
    
    private var products: [Product] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter?.viewDidLoad()
    }
    
    private func setupUI() {
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    // MARK: - ProductListViewProtocol
    func showProducts(_ products: [Product]) {
        self.products = products
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func showLoading() {
        DispatchQueue.main.async {
            self.loadingIndicator.startAnimating()
        }
    }
    
    func hideLoading() {
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
        }
    }
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
}

extension ProductListViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return products.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProductCell", for: indexPath)
        cell.textLabel?.text = products[indexPath.row].name
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presenter?.didSelectProduct(at: indexPath.row)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        presenter?.didScrollList()
    }
}

// MARK: - Router
class ProductListRouter: ProductListRouterProtocol {
    
    weak var viewController: UIViewController?
    
    func navigateToProductDetail(_ product: Product) {
        let detailVC = ProductDetailModuleBuilder.build(product: product)
        viewController?.navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Module Builder
class ProductListModuleBuilder {
    
    static func build() -> UIViewController {
        let view = ProductListViewController()
        let presenter = ProductListPresenter()
        let interactor = ProductListInteractor()
        let router = ProductListRouter()
        
        view.presenter = presenter
        presenter.view = view
        presenter.interactor = interactor
        presenter.router = router
        interactor.presenter = presenter
        router.viewController = view
        
        return view
    }
}
```

## Clean Architecture

```swift
import Foundation
import LuxAnalytics

// MARK: - Domain Layer

// Entities
struct User {
    let id: String
    let name: String
    let email: String
}

struct AnalyticsEvent {
    let name: String
    let metadata: [String: Any]
    let timestamp: Date
    let userId: String?
}

// Use Cases
protocol TrackAnalyticsEventUseCase {
    func execute(_ event: AnalyticsEvent) async throws
}

protocol GetUserUseCase {
    func execute(userId: String) async throws -> User
}

// Repository Protocols (Domain)
protocol AnalyticsRepositoryProtocol {
    func track(_ event: AnalyticsEvent) async throws
    func setUser(_ userId: String) async
    func flush() async
}

protocol UserRepositoryProtocol {
    func fetchUser(_ id: String) async throws -> User
}

// MARK: - Data Layer

// Analytics Repository Implementation
class AnalyticsRepository: AnalyticsRepositoryProtocol {
    
    func track(_ event: AnalyticsEvent) async throws {
        let analytics = await LuxAnalytics.shared
        try await analytics.track(event.name, metadata: event.metadata)
    }
    
    func setUser(_ userId: String) async {
        let analytics = await LuxAnalytics.shared
        await analytics.setUser(userId)
    }
    
    func flush() async {
        await LuxAnalytics.flush()
    }
}

// MARK: - Use Case Implementations

class TrackAnalyticsEventUseCaseImpl: TrackAnalyticsEventUseCase {
    
    private let analyticsRepository: AnalyticsRepositoryProtocol
    
    init(analyticsRepository: AnalyticsRepositoryProtocol) {
        self.analyticsRepository = analyticsRepository
    }
    
    func execute(_ event: AnalyticsEvent) async throws {
        try await analyticsRepository.track(event)
    }
}

class GetUserUseCaseImpl: GetUserUseCase {
    
    private let userRepository: UserRepositoryProtocol
    private let trackEventUseCase: TrackAnalyticsEventUseCase
    
    init(
        userRepository: UserRepositoryProtocol,
        trackEventUseCase: TrackAnalyticsEventUseCase
    ) {
        self.userRepository = userRepository
        self.trackEventUseCase = trackEventUseCase
    }
    
    func execute(userId: String) async throws -> User {
        // Track the request
        let event = AnalyticsEvent(
            name: "user_fetch_requested",
            metadata: ["user_id": userId],
            timestamp: Date(),
            userId: userId
        )
        try await trackEventUseCase.execute(event)
        
        do {
            let user = try await userRepository.fetchUser(userId)
            
            // Track success
            let successEvent = AnalyticsEvent(
                name: "user_fetch_completed",
                metadata: [
                    "user_id": userId,
                    "success": true
                ],
                timestamp: Date(),
                userId: userId
            )
            try await trackEventUseCase.execute(successEvent)
            
            return user
            
        } catch {
            // Track failure
            let failureEvent = AnalyticsEvent(
                name: "user_fetch_failed",
                metadata: [
                    "user_id": userId,
                    "error": error.localizedDescription,
                    "success": false
                ],
                timestamp: Date(),
                userId: userId
            )
            try await trackEventUseCase.execute(failureEvent)
            
            throw error
        }
    }
}

// MARK: - Presentation Layer

class UserProfileViewModel: ObservableObject {
    
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let getUserUseCase: GetUserUseCase
    private let trackEventUseCase: TrackAnalyticsEventUseCase
    
    init(
        getUserUseCase: GetUserUseCase,
        trackEventUseCase: TrackAnalyticsEventUseCase
    ) {
        self.getUserUseCase = getUserUseCase
        self.trackEventUseCase = trackEventUseCase
    }
    
    func loadUser(_ userId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            user = try await getUserUseCase.execute(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func trackUserAction(_ actionType: String) async {
        let event = AnalyticsEvent(
            name: "user_action",
            metadata: [
                "action_type": actionType,
                "screen": "user_profile"
            ],
            timestamp: Date(),
            userId: user?.id
        )
        
        try? await trackEventUseCase.execute(event)
    }
}

// MARK: - Dependency Injection

class DIContainer {
    
    // Repositories
    lazy var analyticsRepository: AnalyticsRepositoryProtocol = AnalyticsRepository()
    lazy var userRepository: UserRepositoryProtocol = UserRepository()
    
    // Use Cases
    lazy var trackEventUseCase: TrackAnalyticsEventUseCase = TrackAnalyticsEventUseCaseImpl(
        analyticsRepository: analyticsRepository
    )
    
    lazy var getUserUseCase: GetUserUseCase = GetUserUseCaseImpl(
        userRepository: userRepository,
        trackEventUseCase: trackEventUseCase
    )
    
    // View Models
    func makeUserProfileViewModel() -> UserProfileViewModel {
        return UserProfileViewModel(
            getUserUseCase: getUserUseCase,
            trackEventUseCase: trackEventUseCase
        )
    }
}
```

## The Composable Architecture (TCA)

```swift
import ComposableArchitecture
import LuxAnalytics

// MARK: - Domain

struct Product: Equatable, Identifiable {
    let id: String
    let name: String
    let price: Double
}

// MARK: - State

struct ProductListState: Equatable {
    var products: [Product] = []
    var isLoading = false
    var errorMessage: String?
}

// MARK: - Actions

enum ProductListAction: Equatable {
    case viewDidAppear
    case loadProducts
    case productsLoaded([Product])
    case productLoadingFailed(String)
    case productTapped(Product)
    case listScrolled
}

// MARK: - Analytics Actions

enum AnalyticsAction: Equatable {
    case track(String, [String: String] = [:])
    case setUser(String)
    case flush
}

// MARK: - Environment

struct ProductListEnvironment {
    let productRepository: ProductRepositoryProtocol
    let analyticsClient: AnalyticsClient
    let mainQueue: AnySchedulerOf<DispatchQueue>
}

struct AnalyticsClient {
    let track: (String, [String: Any]) async throws -> Void
    let setUser: (String) async -> Void
    let flush: () async -> Void
}

extension AnalyticsClient {
    static let live = AnalyticsClient(
        track: { eventName, metadata in
            let analytics = await LuxAnalytics.shared
            try await analytics.track(eventName, metadata: metadata)
        },
        setUser: { userId in
            let analytics = await LuxAnalytics.shared
            await analytics.setUser(userId)
        },
        flush: {
            await LuxAnalytics.flush()
        }
    )
}

// MARK: - Reducer

let productListReducer = Reducer<ProductListState, ProductListAction, ProductListEnvironment> { state, action, environment in
    
    switch action {
    case .viewDidAppear:
        return Effect.task {
            try await environment.analyticsClient.track("product_list_viewed", [:])
            return .loadProducts
        }
        
    case .loadProducts:
        state.isLoading = true
        state.errorMessage = nil
        
        return Effect.task {
            try await environment.analyticsClient.track("product_load_started", [:])
            
            do {
                let products = try await environment.productRepository.fetchProducts()
                
                try await environment.analyticsClient.track("product_load_completed", [
                    "product_count": String(products.count),
                    "success": "true"
                ])
                
                return .productsLoaded(products)
                
            } catch {
                try await environment.analyticsClient.track("product_load_failed", [
                    "error": error.localizedDescription,
                    "success": "false"
                ])
                
                return .productLoadingFailed(error.localizedDescription)
            }
        }
        
    case let .productsLoaded(products):
        state.isLoading = false
        state.products = products
        return .none
        
    case let .productLoadingFailed(errorMessage):
        state.isLoading = false
        state.errorMessage = errorMessage
        return .none
        
    case let .productTapped(product):
        return Effect.task {
            try await environment.analyticsClient.track("product_tapped", [
                "product_id": product.id,
                "product_name": product.name,
                "product_price": String(product.price)
            ])
            
            // Navigation would be handled here or in parent reducer
            return .none
        }
        .fireAndForget()
        
    case .listScrolled:
        return Effect.task {
            try await environment.analyticsClient.track("product_list_scrolled", [:])
            return .none
        }
        .fireAndForget()
    }
}

// MARK: - View

struct ProductListView: View {
    let store: Store<ProductListState, ProductListAction>
    
    var body: some View {
        WithViewStore(store) { viewStore in
            NavigationView {
                Group {
                    if viewStore.isLoading {
                        ProgressView("Loading products...")
                    } else if let errorMessage = viewStore.errorMessage {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                    } else {
                        List(viewStore.products) { product in
                            ProductRowView(product: product) {
                                viewStore.send(.productTapped(product))
                            }
                        }
                        .onScrollChanged {
                            viewStore.send(.listScrolled)
                        }
                    }
                }
                .navigationTitle("Products")
                .onAppear {
                    viewStore.send(.viewDidAppear)
                }
            }
        }
    }
}

struct ProductRowView: View {
    let product: Product
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(product.name)
                    .font(.headline)
                Text("$\(product.price, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - App Integration

struct ProductListApp: View {
    let store = Store(
        initialState: ProductListState(),
        reducer: productListReducer,
        environment: ProductListEnvironment(
            productRepository: ProductRepository(),
            analyticsClient: .live,
            mainQueue: .main
        )
    )
    
    var body: some View {
        ProductListView(store: store)
    }
}
```

## Redux/Flux Patterns

```swift
import Foundation
import LuxAnalytics

// MARK: - State

struct AppState {
    var user: User?
    var products: [Product] = []
    var isLoading = false
    var analyticsQueue: [AnalyticsEvent] = []
}

// MARK: - Actions

enum AppAction {
    case user(UserAction)
    case product(ProductAction)
    case analytics(AnalyticsAction)
}

enum UserAction {
    case login(String)
    case logout
    case userLoaded(User)
    case userLoadFailed(String)
}

enum ProductAction {
    case loadProducts
    case productsLoaded([Product])
    case productSelected(Product)
}

enum AnalyticsAction {
    case track(String, [String: Any])
    case setUser(String)
    case flush
    case eventProcessed(AnalyticsEvent)
}

// MARK: - Middleware

typealias Middleware<State, Action> = (State, Action) -> AsyncStream<Action>

class AnalyticsMiddleware {
    
    static func create() -> Middleware<AppState, AppAction> {
        return { state, action in
            return AsyncStream { continuation in
                Task {
                    await handleAnalyticsAction(action, state: state, continuation: continuation)
                }
            }
        }
    }
    
    private static func handleAnalyticsAction(
        _ action: AppAction, 
        state: AppState, 
        continuation: AsyncStream<AppAction>.Continuation
    ) async {
        
        switch action {
        case .user(.login(let userId)):
            await trackUserLogin(userId, continuation: continuation)
            
        case .user(.logout):
            await trackUserLogout(continuation: continuation)
            
        case .product(.productSelected(let product)):
            await trackProductSelection(product, continuation: continuation)
            
        case .analytics(let analyticsAction):
            await handleDirectAnalyticsAction(analyticsAction, continuation: continuation)
            
        default:
            break
        }
    }
    
    private static func trackUserLogin(_ userId: String, continuation: AsyncStream<AppAction>.Continuation) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("user_login", metadata: [
            "user_id": userId,
            "login_method": "app"
        ])
        
        await analytics.setUser(userId)
        
        continuation.yield(.analytics(.setUser(userId)))
    }
    
    private static func trackUserLogout(continuation: AsyncStream<AppAction>.Continuation) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("user_logout")
        await analytics.setUser(nil)
        
        continuation.yield(.analytics(.setUser("")))
    }
    
    private static func trackProductSelection(_ product: Product, continuation: AsyncStream<AppAction>.Continuation) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("product_selected", metadata: [
            "product_id": product.id,
            "product_name": product.name,
            "product_price": product.price
        ])
        
        let event = AnalyticsEvent(
            name: "product_selected",
            metadata: ["product_id": product.id],
            timestamp: Date(),
            userId: nil
        )
        
        continuation.yield(.analytics(.eventProcessed(event)))
    }
    
    private static func handleDirectAnalyticsAction(_ action: AnalyticsAction, continuation: AsyncStream<AppAction>.Continuation) async {
        switch action {
        case .track(let eventName, let metadata):
            let analytics = await LuxAnalytics.shared
            try? await analytics.track(eventName, metadata: metadata)
            
        case .setUser(let userId):
            let analytics = await LuxAnalytics.shared
            await analytics.setUser(userId)
            
        case .flush:
            await LuxAnalytics.flush()
            
        case .eventProcessed:
            break
        }
    }
}

// MARK: - Store

class Store<State, Action>: ObservableObject {
    
    @Published private(set) var state: State
    
    private let reducer: (inout State, Action) -> Void
    private let middlewares: [Middleware<State, Action>]
    
    init(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Void,
        middlewares: [Middleware<State, Action>] = []
    ) {
        self.state = initialState
        self.reducer = reducer
        self.middlewares = middlewares
    }
    
    func dispatch(_ action: Action) {
        // Apply reducer
        reducer(&state, action)
        
        // Run middlewares
        for middleware in middlewares {
            let actionStream = middleware(state, action)
            
            Task {
                for await newAction in actionStream {
                    await MainActor.run {
                        self.dispatch(newAction)
                    }
                }
            }
        }
    }
}

// MARK: - Reducers

func appReducer(state: inout AppState, action: AppAction) {
    switch action {
    case .user(let userAction):
        userReducer(state: &state, action: userAction)
        
    case .product(let productAction):
        productReducer(state: &state, action: productAction)
        
    case .analytics(let analyticsAction):
        analyticsReducer(state: &state, action: analyticsAction)
    }
}

func userReducer(state: inout AppState, action: UserAction) {
    switch action {
    case .login:
        state.isLoading = true
        
    case .userLoaded(let user):
        state.user = user
        state.isLoading = false
        
    case .userLoadFailed:
        state.isLoading = false
        
    case .logout:
        state.user = nil
    }
}

func productReducer(state: inout AppState, action: ProductAction) {
    switch action {
    case .loadProducts:
        state.isLoading = true
        
    case .productsLoaded(let products):
        state.products = products
        state.isLoading = false
        
    case .productSelected:
        break // Handled by analytics middleware
    }
}

func analyticsReducer(state: inout AppState, action: AnalyticsAction) {
    switch action {
    case .eventProcessed(let event):
        state.analyticsQueue.append(event)
        
    default:
        break
    }
}
```

## Testing Architecture Integration

### Dependency Injection for Testing

```swift
protocol AnalyticsServiceProtocol {
    func track(_ eventName: String, metadata: [String: Any]) async
    func setUser(_ userId: String) async
    func flush() async
}

// Production implementation
class ProductionAnalyticsService: AnalyticsServiceProtocol {
    func track(_ eventName: String, metadata: [String: Any] = [:]) async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track(eventName, metadata: metadata)
    }
    
    func setUser(_ userId: String) async {
        let analytics = await LuxAnalytics.shared
        await analytics.setUser(userId)
    }
    
    func flush() async {
        await LuxAnalytics.flush()
    }
}

// Mock implementation for testing
class MockAnalyticsService: AnalyticsServiceProtocol {
    var trackedEvents: [(String, [String: Any])] = []
    var currentUser: String?
    var flushCallCount = 0
    
    func track(_ eventName: String, metadata: [String: Any] = [:]) async {
        trackedEvents.append((eventName, metadata))
    }
    
    func setUser(_ userId: String) async {
        currentUser = userId
    }
    
    func flush() async {
        flushCallCount += 1
    }
}

// Test example
class ViewModelTests: XCTestCase {
    
    func testUserLoadTracking() async {
        // Arrange
        let mockAnalytics = MockAnalyticsService()
        let viewModel = UserProfileViewModel(analyticsService: mockAnalytics)
        
        // Act
        await viewModel.loadUser("user123")
        
        // Assert
        XCTAssertEqual(mockAnalytics.trackedEvents.count, 2)
        XCTAssertEqual(mockAnalytics.trackedEvents.first?.0, "user_profile_load_started")
        XCTAssertEqual(mockAnalytics.currentUser, "user123")
    }
}
```

## Best Practices for Architecture Integration

### ✅ Do

- **Separate concerns**: Keep analytics logic separate from business logic
- **Use dependency injection**: Make analytics services injectable for testing
- **Create abstractions**: Use protocols for analytics services
- **Handle errors gracefully**: Don't let analytics failures affect app functionality
- **Use middleware/interceptors**: For cross-cutting analytics concerns
- **Track meaningful events**: Focus on business value, not technical events
- **Maintain consistency**: Use consistent event naming across architecture layers

### ❌ Don't

- **Tight coupling**: Don't tightly couple business logic with analytics
- **Blocking operations**: Don't block UI with analytics calls
- **Over-tracking**: Don't track every single user interaction
- **Ignore privacy**: Don't track sensitive user data
- **Skip testing**: Don't forget to test analytics integration
- **Mix responsibilities**: Don't put analytics logic in view controllers/views
- **Ignore architecture**: Don't bypass your app's architecture for analytics

## Performance Considerations

### Async Analytics in Different Architectures

```swift
// MVVM - Use async properly
class ViewModel: ObservableObject {
    func handleUserAction() async {
        // Business logic first
        let result = await performBusinessOperation()
        
        // Analytics second (non-blocking)
        Task.detached {
            await analyticsService.track("user_action_completed")
        }
    }
}

// VIPER - Analytics in interactor
class Interactor {
    func performAction() async {
        // Business logic
        let result = await businessOperation()
        
        // Analytics (fire-and-forget)
        Task {
            await analyticsService.track("action_performed")
        }
        
        return result
    }
}

// TCA - Analytics as effect
let reducer = Reducer { state, action, environment in
    switch action {
    case .userAction:
        return Effect.merge(
            // Business effect
            Effect.task { .businessActionCompleted },
            
            // Analytics effect (fire-and-forget)
            Effect.task {
                try await environment.analytics.track("user_action")
                return .none
            }
            .fireAndForget()
        )
    }
}
```

## Next Steps

- [🧪 Testing Guide](Testing.md) - Test your architecture with analytics
- [🛠️ Development Setup](Development-Setup.md) - Setup for different architectures  
- [💡 Best Practices](Best-Practices.md) - Production patterns across architectures
- [🏗️ Custom Extensions](Custom-Extensions.md) - Extend SDK for your architecture