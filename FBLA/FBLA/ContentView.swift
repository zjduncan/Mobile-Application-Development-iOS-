//
//  ContentView.swift
//  FBLA
//
//  Created by Zane Duncan on 11/24/25.
//

import SwiftUI
import PhotosUI
import Combine
import WebKit
import UserNotifications
import EventKit
import PDFKit
import MapKit

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var showSplashScreen = true
    
    var body: some View {
        ZStack {
            // Main app content
            Group {
                if appState.isLoggedIn {
                    MainTabView()
                        .environmentObject(appState)
                } else {
                    LoginView()
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(.light)
            
            // Splash screen overlay
            if showSplashScreen {
                Image("Splash")
                    .resizable()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            // Show splash screen for 4 seconds (3-5 second range)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplashScreen = false
                }
            }
        }
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    @Published var showingImagePicker = false
    @Published var selectedImage: UIImage?
    
    func login(user: User) {
        self.currentUser = user
        self.isLoggedIn = true
    }
    
    func logout() {
        self.currentUser = nil
        self.isLoggedIn = false
    }
    
    func updateProfileImage(_ image: UIImage) {
        self.selectedImage = image
        self.currentUser?.profileImage = image
    }
}

// MARK: - Logo Helper
struct FBLAHeaderLogo: View {
    var body: some View {
        HStack {
            Image("FBLA_Logo_Vertical_color-HiRes")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
            
            Spacer()
        }
        .padding(.horizontal, 30)
    }
}

// MARK: - Models
struct User {
    var id: String
    var name: String
    var email: String
    var phoneNumber: String
    var school: String
    var graduationYear: String
    var chapter: String
    var chapterNumber: String
    var role: String
    var membershipID: String
    var profileImage: UIImage?
}

struct Event: Identifiable {
    let id = UUID()
    let title: String
    let dateRange: String
    let time: String
    let location: String
    let type: EventType
    let isAllDay: Bool
    
    enum EventType {
        case virtual
        case inPerson
    }
}

struct Post: Identifiable {
    let id = UUID()
    let author: String
    let title: String
    let content: String
    let imageURL: String?
    let timestamp: String
    let category: PostCategory
    
    enum PostCategory: String, CaseIterable {
        case all = "All Posts"
        case announcements = "National FBLA"
        case social = "Missouri FBLA"
    }
}

struct Resource: Identifiable {
    let id = UUID()
    let title: String
    let fileSize: String
    let type: String
    let url: URL?
}

struct RSSItem: Identifiable {
    let id = UUID()
    let title: String
    let link: String
    let description: String
    let pubDate: String
    let imageURL: String?
}

// MARK: - PDF Viewer (reusable, handles local or remote PDFs)
struct PDFViewer: UIViewRepresentable {
    let pdfURL: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true

        // Load PDF asynchronously
        DispatchQueue.global(qos: .background).async {
            if let data = try? Data(contentsOf: pdfURL),
               let document = PDFDocument(data: data) {
                DispatchQueue.main.async {
                    pdfView.document = document
                }
            } else {
                print("ERROR: Could not load PDF from URL \(pdfURL)")
            }
        }

        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - PDF Detail Screen (the actual PDF display screen)
struct PDFDetailView: View {
    let pdfURL: URL
    let title: String

    var body: some View {
        PDFViewer(pdfURL: pdfURL)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
// MARK: - RSS Feed Parser
class RSSFeedParser: NSObject, XMLParserDelegate, ObservableObject {
    @Published var items: [RSSItem] = []
    @Published var isLoading = false
    
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentImageURL = ""
    private var parsingItem = false
    
    func fetchFeed(urlString: String = "https://rss.app/feeds/pRBbOSgPMEx09OrU.xml") {
        isLoading = true
        items = []
        
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                return
            }
            
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }.resume()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            parsingItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentImageURL = ""
        } else if elementName == "enclosure" || elementName == "media:content" {
            // Extract image from enclosure or media:content tags
            if let url = attributeDict["url"], url.contains("jpg") || url.contains("jpeg") || url.contains("png") {
                currentImageURL = url
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        
        if parsingItem {
            switch currentElement {
            case "title":
                currentTitle += trimmed
            case "link":
                currentLink += trimmed
            case "description", "content:encoded":
                currentDescription += trimmed
            case "pubDate":
                currentPubDate += trimmed
            case "media:thumbnail", "media:content":
                // Some feeds use media:thumbnail
                break
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            // Extract image from description if not found in enclosure
            if currentImageURL.isEmpty {
                currentImageURL = extractImageURL(from: currentDescription)
            }
            
            let cleanDescription = currentDescription
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let item = RSSItem(
                title: currentTitle,
                link: currentLink,
                description: cleanDescription,
                pubDate: currentPubDate,
                imageURL: currentImageURL.isEmpty ? nil : currentImageURL
            )
            
            DispatchQueue.main.async {
                self.items.append(item)
            }
            parsingItem = false
        }
    }
    
    private func extractImageURL(from html: String) -> String {
        // Try to extract image URL from HTML content
        let pattern = "<img[^>]+src=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return ""
    }
}

// MARK: - RSS Feed View
struct RSSFeedView: View {
    @StateObject private var parser = RSSFeedParser()
    @State private var showingDetailView = false
    @State private var selectedItem: RSSItem?
    
    var body: some View {
        VStack(spacing: 15) {
            if parser.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.09, green: 0.25, blue: 0.56)))
                    Spacer()
                }
                .frame(height: 200)
            } else if parser.items.isEmpty {
                HStack {
                    Spacer()
                    Text("No news available")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(height: 200)
            } else {
                ForEach(parser.items.prefix(5)) { item in
                    Button(action: {
                        selectedItem = item
                        showingDetailView = true
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Image if available
                            if let imageURL = item.imageURL, let url = URL(string: imageURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(height: 150)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 150)
                                            .clipped()
                                    case .failure:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(height: 150)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .cornerRadius(12)
                            }
                            
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            
                            Text(item.description)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .onAppear {
            if parser.items.isEmpty {
                parser.fetchFeed()
            }
        }
        .sheet(isPresented: $showingDetailView) {
            if let item = selectedItem {
                NewsDetailView(item: item)
            }
        }
    }
}

// MARK: - Login View
struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false
    @State private var showingGoogle = false
    @State private var showingApple = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer for blue header
                        Color.clear
                            .frame(height: 140)
                        
                        // Logo - Using actual FBLA logo from assets
                        Image("FBLA_Logo_Vertical_color-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .padding(.bottom, 25)
                        
                        Text("Log In")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.bottom, 25)
                        
                        // Input fields
                        VStack(spacing: 15) {
                            TextField("", text: $email, prompt: Text("Email Address").foregroundColor(.gray.opacity(0.7)))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .padding()
                                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                                .cornerRadius(25)
                                .frame(maxWidth: min(geometry.size.width - 40, 400))
                            
                            SecureField("", text: $password, prompt: Text("Password").foregroundColor(.gray.opacity(0.7)))
                                .padding()
                                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                                .cornerRadius(25)
                                .frame(maxWidth: min(geometry.size.width - 40, 400))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        
                        // Login button
                        Button(action: {
                            let user = User(
                                id: "12345678",
                                name: "Zane Duncan",
                                email: "2026zduncan@salisbury.k12.mo.us",
                                phoneNumber: "(660) 855-1029",
                                school: "Salisbury High School",
                                graduationYear: "2026",
                                chapter: "Salisbury FBLA",
                                chapterNumber: "#1084",
                                role: "Chapter President",
                                membershipID: "3491897",
                                profileImage: nil
                            )
                            appState.login(user: user)
                        }) {
                            Text("Log In")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color(red: 0.09, green: 0.25, blue: 0.56))
                                .cornerRadius(25)
                        }
                        .padding(.bottom, 20)
                        
                        // Divider with "or"
                        HStack(spacing: 15) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                            
                            Text("or")
                                .foregroundColor(.gray)
                                .font(.system(size: 15))
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: min(geometry.size.width - 80, 350))
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)
                        
                        // Social login button - Google
                        Button(action: {
                           showingGoogle = true
                             let user = User(
                                id: "12345678",
                                name: "Zane Duncan",
                                email: "2026zduncan@salisbury.k12.mo.us",
                                phoneNumber: "(660) 855-1029",
                                school: "Salisbury High School",
                                graduationYear: "2026",
                                chapter: "Salisbury FBLA",
                                chapterNumber: "#1084",
                                role: "Chapter President",
                                membershipID: "3491897",
                                profileImage: nil
                            )
                            appState.login(user: user)
                        }) {
                            HStack(spacing: 12) {
                                Image("GoogleG_FullColor_White_RGB.original")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                
                                Text("Continue with Google")
                                    .foregroundColor(.black)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(width: 280, height: 52)
                            .background(Color.white)
                            .cornerRadius(25)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.bottom, 10)
                        .font(.system(size: 15))
                        
                        // Social login button - Apple
                        Button(action: {
                           showingApple = true
                             let user = User(
                                id: "12345678",
                                name: "Zane Duncan",
                                email: "2026zduncan@salisbury.k12.mo.us",
                                phoneNumber: "(660) 855-1029",
                                school: "Salisbury High School",
                                graduationYear: "2026",
                                chapter: "Salisbury FBLA",
                                chapterNumber: "#1084",
                                role: "Chapter President",
                                membershipID: "3491897",
                                profileImage: nil
                            )
                            appState.login(user: user)
                        }) {
                            HStack(spacing: 12) {
                                Image("Apple_dark")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                                
                                Text("Sign In with Apple")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(width: 280, height: 52)
                            .background(Color.black)
                            .cornerRadius(25)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.bottom, 30)
                    }
                }
                
                // Blue header bar
                VStack {
                    Color(red: 0.09, green: 0.25, blue: 0.56)
                        .frame(height: 140)
                        .ignoresSafeArea(edges: .top)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            SocialsView()
                .tabItem {
                    Image(systemName: "person.2.fill")
                    Text("Socials")
                }
                .tag(1)
            
            EventsView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Events")
                }
                .tag(2)
            
            ResourcesView()
                .tabItem {
                    Image(systemName: "doc.fill")
                    Text("Resources")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(4)
        }
        .accentColor(Color(red: 0.957, green: 0.671, blue: 0.098))
    }
}

// MARK: - Home View
struct HomeView: View {
    @State private var conferenceCode = ""
    @State private var showingProfile = false
    @State private var showingEventContent = false
    @EnvironmentObject var appState: AppState
    
    let upcomingEvents = [
        Event(title: "State Leadership Conference", dateRange: "April 12-14, Springfield, MO", time: "", location: "Springfield, MO", type: .inPerson, isAllDay: true),
    ]
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        case 17..<22:
            return "Good Evening"
        default:
            return "Good Night"
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer for sticky header
                        Color.clear
                            .frame(height: 5)
                        
                        VStack(alignment: .leading, spacing: 25) {
                            
                            //Spacing to align the page content
                            Spacer(minLength:35)
                            
                            //Yearly theme banner
                            Image("theme")
                                .resizable()
                                .scaledToFit()
                            
                            Text("\(greeting), \(appState.currentUser?.name.components(separatedBy: " ").first ?? "Zane")")
                                .font(.system(size: 36, weight: .bold))
                                .padding(.horizontal)
                                .padding(.top, 20)
                            
                            // Join Event Card
                            VStack(alignment: .leading, spacing: 15) {
                                
                                TextField("Enter Conference Code", text: $conferenceCode)
                                    .padding()
                                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                                    .cornerRadius(12)
                                
                                Button(action: {
                                    if conferenceCode.lowercased() == "slc26" {
                                        showingEventContent = true
                                    }
                                }) {
                                    HStack {
                                        Text("Access Event")
                                            .font(.system(size: 18, weight: .semibold))
                                        Image(systemName: "arrow.right")
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 55)
                                    .background(Color(red: 0.09, green: 0.25, blue: 0.56))
                                    .cornerRadius(12)
                                }
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(15)
                            .padding(.horizontal)
                            
                            // Upcoming Events
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Upcoming Events")
                                    .font(.system(size: 28, weight: .bold))
                                    .padding(.horizontal)
                                
                                ForEach(upcomingEvents) { event in
                                    Button(action: {
                                        showingEventContent = true
                                    }) {
                                        EventRow(event: event)
                                            .padding(.horizontal)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.top, 10)
                            
                            // Latest News
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Latest News")
                                    .font(.system(size: 28, weight: .bold))
                                    .padding(.horizontal)
                                
                                RSSFeedView()
                                    .padding(.horizontal)
                            }
                            .padding(.top, 10)
                            
                            Spacer()
                                .frame(height: 40)
                        }
                    }
                }
                
                // Sticky Header - Fixed on top with logo
                VStack {
                    ZStack {
                        //Blue Sticky Header
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 130)
                        
                        // FBLA Horizontal Logo
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showingEventContent) {
            EventContentView()
        }
    }
}

struct EventRow: View {
    let event: Event
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "calendar")
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                .padding()
                .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(event.dateRange)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
    }
}

//MARK: - Event Content View
struct EventContentView: View {
    @State private var showingWebBrowser = false
    @State private var browserURL: URL?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) var dismiss
    @State private var showingInternalView = false
    @State private var selectedView: AnyView? = nil
    
    enum ContentDestination {
        case url(URL)
        case view(AnyView)
    }

    let contentItems: [(title: String, icon: String, destination: ContentDestination)] = [
        ("Conference Schedule", "calendar", .view(AnyView(ScheduleView()))),
        ("Results", "trophy", .view(AnyView(ResultsView()))),
        ("Maps", "map", .view(AnyView(MapView()))),
        ("Workshops", "hammer", .view(AnyView(WorkshopView()))),
        ("Wallet", "wallet.bifold", .view(AnyView(TicketView()))),
        ("Help", "questionmark.circle", .view(AnyView(HelpView())))
        ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            // Spacer for navigation bar
                            Color.clear
                                .frame(height: 10)
                            
                            //Spacer to line up conference banner image
                            Spacer(minLength: 5)
                            
                            //Conference Banner
                            Image("Conference")
                                .resizable()
                                .scaledToFit()
                            
                            // Quick Access
                            VStack(alignment: .leading, spacing: 15) {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                    ForEach(contentItems, id: \.title) { item in
                                        ContentCard(title: item.title, icon: item.icon) {
                                            switch item.destination {
                                            case .url(let link):
                                                browserURL = link
                                                showingWebBrowser = true

                                            case .view(let view):
                                                selectedView = AnyView(view)   // or another state you use for navigation
                                                showingInternalView = true     // ← you choose the name
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }

                            .padding(.top, 10)
                            
                            NavigationLink(
                                destination: selectedView,
                                isActive: $showingInternalView
                            ) {
                                EmptyView()
                            }
                            .hidden()
                        }
                    }
                }
                
                // Sticky Header - Fixed on top with logo
                VStack {
                    
                    ZStack {
                        //Blue Sticky Header
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 130)
                        
                        HStack {
                            // Back button
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                            }
                            
                            Spacer(minLength:25)
                            
                            // FBLA Horizontal Logo
                            Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 175)
                            
                            Spacer()
                            
                            // Invisible spacer to balance the back button
                            Image(systemName: "chevron.left")
                                .foregroundColor(.clear)
                                .font(.system(size: 20))
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingWebBrowser) {
            if let url = browserURL {
                WebBrowserView(url: url)
            }
        }
    }
}

struct ContentCard: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    .padding()
                    .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(Color.white)
            .cornerRadius(15)
        }
    }
}

// MARK: - ScheduleView
struct ScheduleView: View {
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    
    // All events with their actual dates
    let allEvents: [(date: Date, event: Event)] = [
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Registration Pick-Up Opens", dateRange: "", time: "9:00 AM", location: "University Plaza Hotel", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Workshop Rotations Begin", dateRange: "", time: "12:00 PM", location: "University Plaza Hotel", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Adviser Meeting", dateRange: "", time: "12:30 PM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Competitive Events Begin", dateRange: "", time: "1:30 PM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Opening Session Begins", dateRange: "", time: "8:00 PM", location: "Great Southern Bank Arena", type: .inPerson, isAllDay: false)),
        
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Leadership Development & Team Building", dateRange: "", time: "12:00 PM - 12:50 PM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Business Plan Competition Prep", dateRange: "", time: "12:00 PM - 12:50 PM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Public Speaking & Presentation Skills", dateRange: "", time: "12:00 PM - 12:50 PM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Resume Writing & Interview Techniques", dateRange: "", time: "1:00 PM - 1:50 PM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Social Media Marketing for Business", dateRange: "", time: "1:00 PM - 1:50 PM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Financial Literacy & Entrepreneurship", dateRange: "", time: "1:00 PM - 1:50 PM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),
        
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Competitive Events Begin", dateRange: "", time: "8:30 AM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Workshop Rotations Begin", dateRange: "", time: "9:00 AM", location: "University Plaza Hotel", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Member & Programs Awards", dateRange: "", time: "2:30 PM", location: "Great Southern Bank Arena", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Social", dateRange: "", time: "8:00 PM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Networking Strategies for Success", dateRange: "", time: "9:00 AM - 9:50 AM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Career Pathways in Business", dateRange: "", time: "9:00 AM - 9:50 AM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Digital Marketing & E-Commerce", dateRange: "", time: "9:00 AM - 9:50 AM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Business Ethics & Professional Conduct", dateRange: "", time: "10:00 AM - 10:50 AM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Project Management Essentials", dateRange: "", time: "10:00 AM - 10:50 AM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "College & Scholarship Applications", dateRange: "", time: "10:00 AM - 10:50 AM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),
        
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 14))!,
         Event(title: "Awards of Excellence Ceremony", dateRange: "", time: "8:00 AM", location: "Great Southern Bank Arena", type: .inPerson, isAllDay: false)),
    ]
    
    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
    
    // Get 7 days centered around selected date (3 before, selected, 3 after)
    private var weekDays: [Date] {
        let calendar = Calendar.current
        return (-3...3).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: selectedDate)
        }
    }
    
    // Filter events for the selected date
    private var eventsForSelectedDate: [Event] {
        let calendar = Calendar.current
        return allEvents
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .map { $0.event }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Sticky Header - Fixed on top with logo
                    VStack {
                        ZStack {
                            //Blue Sticky Header
                            Color(red: 0.09, green: 0.25, blue: 0.56)
                                .frame(height: 130)
                            
                            // FBLA Horizontal Logo
                            Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 175)
                                .padding(.top, 40)
                        }
                        .ignoresSafeArea(.all)
                    }
                    
                    Spacer()
                    
                }
                
                // Scrollable content overlay
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        Spacer()
                        // Month Navigation
                        HStack {
                            Button(action: {
                                // Go back one week
                                if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
                                    selectedDate = newDate
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.black)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            
                            Spacer()
                            
                            Text(monthYearText)
                                .font(.system(size: 24, weight: .bold))
                            
                            Spacer()
                            
                            Button(action: {
                                // Go forward one week
                                if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
                                    selectedDate = newDate
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.black)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                        
                        // Week View - Full width, not scrollable
                        HStack(spacing: 12) {
                            ForEach(weekDays, id: \.self) { date in
                                WeekDayCell(
                                    date: date,
                                    isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedDate = date
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Scrollable Events List
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Text("Events for \(formattedSelectedDate)")
                                        .font(.system(size: 20, weight: .bold))
                                }
                                .padding(.horizontal)
                                
                                if eventsForSelectedDate.isEmpty {
                                    // No events message
                                    VStack(spacing: 12) {
                                        Image(systemName: "calendar.badge.exclamationmark")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray.opacity(0.5))
                                        
                                        Text("No events scheduled")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.gray)
                                        
                                        Text("Tap a different date to see other events")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                    .padding(.horizontal)
                                } else {
                                    ForEach(eventsForSelectedDate) { event in
                                        EventDetailCard(event: event)
                                            .padding(.horizontal)
                                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                    }
                                }
                                
                                // Bottom padding
                                Color.clear.frame(height: 20)
                            }
                            .padding(.top, 10)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Initialize with today's date
            selectedDate = Date()
        }
    }
    
    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - Today
struct Today: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var dayOfMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(dayOfWeek)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : (isToday ? Color(red: 0.957, green: 0.671, blue: 0.098) : .gray))
                
                Text(dayOfMonth)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : (isToday ? Color(red: 0.957, green: 0.671, blue: 0.098) : .black))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? Color(red: 0.09, green: 0.25, blue: 0.56) : Color.clear)
            .cornerRadius(35)
            .overlay(
                RoundedRectangle(cornerRadius: 35)
                    .stroke(isToday && !isSelected ? Color(red: 0.957, green: 0.671, blue: 0.098) : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct EventCard: View {
    let event: Event
    @State private var isReminderSet = false
    @State private var showingReminderOptions = false
    @State private var showingCalendarAlert = false
    @State private var calendarAlertMessage = ""
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 15) {
                // Color bar
                Rectangle()
                    .fill(event.isAllDay ? Color(red: 0.09, green: 0.25, blue: 0.56) : Color(red: 0.95, green: 0.60, blue: 0.07))
                    .frame(width: 5)
                    .cornerRadius(2.5)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                    
                    Text(event.time)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Text(event.location)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Button stack on the right
                VStack(spacing: 8) {
                    // Only show bell button for non-all-day events
                    if !event.isAllDay {
                        Button(action: {
                            if isReminderSet {
                                // Cancel the notification
                                NotificationManager.shared.cancelNotification(for: event)
                                isReminderSet = false
                            } else {
                                // Show options to set notification
                                showingReminderOptions = true
                            }
                        }) {
                            Image(systemName: isReminderSet ? "bell.fill" : "bell")
                                .foregroundColor(isReminderSet ? Color(red: 0x5c/255.0, green: 0x5c/255.0, blue: 0x5c/255.0) : .gray)
                                .font(.system(size: 20))
                        }
                    }
                    
                    // Add to Calendar button - now always shown
                    Button(action: {
                        CalendarManager.shared.addEventToCalendar(event: event) { success, message in
                            calendarAlertMessage = message
                            showingCalendarAlert = true
                        }
                    }) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundColor(.gray)
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .confirmationDialog("When would you like to be reminded?", isPresented: $showingReminderOptions) {
            Button("15 minutes before") {
                scheduleNotification(minutesBefore: 15)
            }
            Button("30 minutes before") {
                scheduleNotification(minutesBefore: 30)
            }
            Button("1 hour before") {
                scheduleNotification(minutesBefore: 60)
            }
            Button("1 day before") {
                scheduleNotification(minutesBefore: 1440)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Calendar", isPresented: $showingCalendarAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarAlertMessage)
        }
    }
    
    private func scheduleNotification(minutesBefore: Int) {
        NotificationManager.shared.requestPermission { granted in
            if granted {
                NotificationManager.shared.scheduleEventNotification(
                    for: event,
                    minutesBefore: minutesBefore
                ) { success in
                    if success {
                        isReminderSet = true
                    }
                }
            }
        }
    }
}

// MARK: - City of Springfield View
struct CityView: View {
    @Environment(\.dismiss) var dismiss  // Add this line for custom back button

    // MARK: Data Model
    struct MapLocation: Identifiable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    // MARK: Locations
    let locations: [MapLocation] = [
        .init(id: "arena", name: "Great Southern Bank Arena", latitude: 37.20204, longitude: -93.28312),
        .init(id: "expo", name: "Springfield Expo Center", latitude: 37.20904, longitude: -93.28500),
        .init(id: "plaza", name: "University Plaza Hotel & Convention Center", latitude: 37.20843, longitude: -93.28317),
        .init(id: "courtyard", name: "Courtyard by Marriott Springfield Airport", latitude: 37.24262, longitude: -93.35000),
        .init(id: "homewood", name: "Homewood Suites by Hilton Springfield Medical District", latitude: 37.13408, longitude: -93.27728)
    ]

    // MARK: Map Region
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.204, longitude: -93.285),
        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
    )

    // MARK: Location Manager
    @StateObject private var locationManager = LocationManager()

    // MARK: View
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(coordinateRegion: $region,
                interactionModes: [.all],
                showsUserLocation: true,
                annotationItems: locations) { location in
                MapAnnotation(coordinate: location.coordinate) {
                    VStack {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                        Text(location.name)
                            .font(.caption)
                            .fixedSize()
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            // MARK: Custom Back Button (top-left)
            VStack {
                Spacer()
            }
            
            // MARK: Center on User Button
            Button(action: {
                if let userLocation = locationManager.lastLocation {
                    region.center = userLocation.coordinate
                }
            }) {
                Image(systemName: "location.fill")
                    .padding()
                    .background(.white.opacity(0.8))
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
            .padding()
        }
        .navigationBarHidden(true)  // Add this line to hide default navigation bar
        .onAppear {
            locationManager.requestLocation()
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Expo Center View
struct ExpoCenter: View {
    @Environment(\.dismiss) var dismiss  // Add this line for custom back button
    
    var body: some View {
        ZStack {
            Image("EXPO")
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
            
            // MARK: Custom Back Button (top-left)
            VStack {
                Spacer()
            }
        }
        .navigationBarHidden(true)  // Add this line to hide default navigation bar
    }
}

// MARK: - MapView
struct MapView: View {
    @State private var selectedView: AnyView? = nil
    @State private var showingInternalView = false

    struct QuickAccessItem {
        let title: String
        let icon: String
        let destination: AnyView
    }

    let quickAccessItems: [QuickAccessItem] = [
        QuickAccessItem(title: "City of Springfield", icon: "map", destination: AnyView(CityView())),
        QuickAccessItem(title: "Springfield Expo Center", icon: "map", destination: AnyView(ExpoCenter()))
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Sticky Header - Blue bar with logo
                    VStack {
                        ZStack {
                            Color(red: 0.09, green: 0.25, blue: 0.56)
                                .frame(height: 130)

                            Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 175)
                                .padding(.top, 40)
                        }
                        .ignoresSafeArea(.all)
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                ForEach(quickAccessItems, id: \.title) { item in
                                    QuickCard(title: item.title, icon: item.icon) {
                                        selectedView = item.destination
                                        showingInternalView = true
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 0)
                    Spacer()
                }

                // Hidden navigation link for pushing views
                NavigationLink(destination: selectedView, isActive: $showingInternalView) {
                    EmptyView()
                }
                .hidden()
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)  // Add this line to prevent default back button
        }
    }
}

// Reuse your QuickAccessCard from ResourcesView
struct QuickCard: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    .padding()
                    .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(Color.white)
            .cornerRadius(15)
        }
    }
}

// MARK: - FAQ Item
struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

// MARK: - HelpView
struct HelpView: View {
    @State private var expandedQuestions: Set<UUID> = []
    
    let faqItems = [
        FAQItem(
            question: "What time does registration/check-in begin?",
            answer: "Registration and Check-In begin at 9:00 A.M. in the University Plaza Hotel Lobby."
        ),
        FAQItem(
            question: "Do I need to bring my registration confirmation?",
            answer: ""
        ),
        FAQItem(
            question: "Is there on-site registration available?",
            answer: ""
        ),
        FAQItem(
            question: "What should I do if I lost my badge?",
            answer: "To replace lost badges, please visit the FBLA booth in the expo center."
        ),
        FAQItem(
            question: "When and where is my competitive event?",
            answer: ""
        ),
        FAQItem(
            question: "What materials am I allowed to bring into my event?",
            answer: ""
        ),
        FAQItem(
            question: "Can I bring notes or reference materials?",
            answer: ""
        ),
        FAQItem(
            question: "What's the dress code for competitive events?",
            answer: "https://2026-fbla.s3.us-east-2.amazonaws.com/2023-Dress-Code.pdf"
        ),
        FAQItem(
            question: "When will results be posted?",
            answer: "Results will be posted in the FBLA app at 8:00 P.M. on Sunday."
        ),
        FAQItem(
            question: "What time does the opening session start?",
            answer: ""
        ),
        FAQItem(
            question: "Are workshops mandatory?",
            answer: "Workshops are highly recommended, but not mandatory."
        ),
        FAQItem(
            question: "Can I attend sessions even if I'm competing?",
            answer: ""
        ),
        FAQItem(
            question: "Are there limits on how many workshops I can attend?",
            answer: "There is no limit for how many workshops you can attend"
        ),
        FAQItem(
            question: "What leadership workshops are available?",
            answer: "For a comprehensive list of available workshops, please refer to the Workshops page on the event homepage."
        ),
        FAQItem(
            question: "When does voting for state officers take place?",
            answer: ""
        ),
        FAQItem(
            question: "Do I need to bring anything to vote?",
            answer: ""
        ),
        FAQItem(
            question: "How does the election process work?",
            answer: ""
        ),
        FAQItem(
            question: "What is business attire?",
            answer: "https://2026-fbla.s3.us-east-2.amazonaws.com/2023-Dress-Code.pdf"
        ),
        FAQItem(
            question: "Is there a curfew?",
            answer: "All students must be in their hotel rooms by no later than 10 P.M. Exceptions may be made for emergencies."
        ),
        FAQItem(
            question: "What are the hotel rules for student groups?",
            answer: "Each hotel has its own expectations and rules for students and events. Please check with your hotel for the most accurate information."
        ),
        FAQItem(
            question: "When and where will the awards ceremony be held?",
            answer: "The Awards of Excellence Ceremony will be held at Great Southern Bank Arena at 8:00 A.M. on April 14, 2026."
        ),
        FAQItem(
            question: "Do all team members need to be present to receive awards?",
            answer: ""
        ),
        FAQItem(
            question: "Is there Wi-Fi available?",
            answer: "Yes. Wi-Fi information will be provided to competitors at event check-in."
        ),
        FAQItem(
            question: "What items are prohibited?",
            answer: ""
        ),
        FAQItem(
            question: "Is there a lost and found?",
            answer: ""
        )
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background color
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Blue Header
                    ZStack {
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                        
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .frame(height: 130)
                    
                    // Scrollable Content
                    ScrollView {
                        VStack(spacing: 30) {
                            // Contact Section
                            Text("Contact")
                                .font(.system(size: 32, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            // Contact Cards
                            VStack(spacing: 16) {
                                ContactCard(
                                    icon: "envelope.fill",
                                    title: "Email",
                                    detail: "larry.anders@dese.mo.gov",
                                    action: "mailto:larry.anders@dese.mo.gov"
                                )
                                
                                ContactCard(
                                    icon: "phone.fill",
                                    title: "Phone",
                                    detail: "(573) 751-8679",
                                    action: "tel:5737518679"
                                )
                                
                                ContactCard(
                                    icon: "globe",
                                    title: "Website",
                                    detail: "www.mofbla.org",
                                    action: "https://www.mofbla.org"
                                )
                            }
                            .padding(.horizontal, 20)
                            
                            // FAQ Section
                            Text("FAQ")
                                .font(.system(size: 32, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                            
                            VStack(spacing: 12) {
                                ForEach(faqItems) { item in
                                    DisclosureGroup(
                                        isExpanded: Binding(
                                            get: { expandedQuestions.contains(item.id) },
                                            set: { isExpanding in
                                                if isExpanding {
                                                    expandedQuestions.insert(item.id)
                                                } else {
                                                    expandedQuestions.remove(item.id)
                                                }
                                            }
                                        )
                                    ) {
                                        Text(item.answer)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(UIColor.systemBackground))
                                    } label: {
                                        Text(item.question)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .padding(.vertical, 8)
                                    }
                                    .padding()
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 30)
                        .padding(.bottom, 30)
                    }
                    
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}

struct ContactCard: View {
    let icon: String
    let title: String
    let detail: String
    let action: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: action) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    .frame(width: 50, height: 50)
                    .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

// MARK: - TicketView
struct TicketView: View {
    @State private var selectedTicketIndex: Int? = nil
    
    let tickets = [
        TicketItem(imageName: "fblaid", title: "FBLA Member ID"),
        TicketItem(imageName: "hotelkey", title: "University Plaza Hotel")
    ]
    
    var body: some View {
            
        ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                // Sticky Header - Fixed on top with logo
                VStack {
                    ZStack {
                        //Blue Sticky Header
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 130)
                        
                        // FBLA Horizontal Logo
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    Spacer()
                }
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header spacing
                        Color.clear
                            .frame(height: 20)
                        
                        //Spacer to move cards down from header
                        Spacer(minLength: 15)
                        
                        // Stacked tickets
                        ZStack {
                            ForEach(Array(tickets.enumerated()), id: \.offset) { index, ticket in
                                TicketCard(ticket: ticket, index: index, totalCount: tickets.count)
                                    .offset(y: selectedTicketIndex == nil ? CGFloat(index * 25) : (selectedTicketIndex == index ? 0 : CGFloat((index - (selectedTicketIndex ?? 0)) * 25)))
                                    .scaleEffect(selectedTicketIndex == nil ? 1.0 : (selectedTicketIndex == index ? 1.0 : 0.95))
                                    .zIndex(selectedTicketIndex == index ? Double(tickets.count) : Double(tickets.count - index))
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            if selectedTicketIndex == index {
                                                selectedTicketIndex = nil
                                            } else {
                                                selectedTicketIndex = index
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        Spacer()
                            .frame(height: 100)
                    }
                }
            }
    }
}

struct TicketCard: View {
    let ticket: TicketItem
    let index: Int
    let totalCount: Int
    
    var body: some View {
        VStack(spacing: 0) {
            // Ticket/Pass Image
            Image(ticket.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipped()
                .cornerRadius(12)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct TicketItem: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
}

// MARK: - WorkshopView
struct WorkshopView: View {
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                // Scrollable content overlay - positioned to start right below header
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0) // Height of header
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer()
                            // Page Title
                            Text("Workshops")
                                .font(.system(size: 34, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.top, 20)
                            
                            // April 12th Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Saturday, April 12")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                                    .padding(.horizontal)
                                
                                // Rotation 1 - Blue
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Rotation 1 • 12:00 PM - 2:00 PM")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                    
                                    WorkshopCard(
                                        title: "Leadership Development & Team Building",
                                        time: "12:00 PM - 2:00 PM",
                                        location: "Ballroom A",
                                        barColor: Color(red: 0.2, green: 0.4, blue: 0.8)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Business Plan Competition Prep",
                                        time: "12:00 PM - 2:00 PM",
                                        location: "Ballroom B",
                                        barColor: Color(red: 0.2, green: 0.4, blue: 0.8)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Public Speaking & Presentation Skills",
                                        time: "12:00 PM - 2:00 PM",
                                        location: "Conference Room 1",
                                        barColor: Color(red: 0.2, green: 0.4, blue: 0.8)
                                    )
                                }
                                
                                // Rotation 2 - Yellow
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Rotation 2 • 2:15 PM - 4:15 PM")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                        .padding(.top, 8)
                                    
                                    WorkshopCard(
                                        title: "Resume Writing & Interview Techniques",
                                        time: "2:15 PM - 4:15 PM",
                                        location: "Ballroom A",
                                        barColor: Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Social Media Marketing for Business",
                                        time: "2:15 PM - 4:15 PM",
                                        location: "Ballroom B",
                                        barColor: Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Financial Literacy & Entrepreneurship",
                                        time: "2:15 PM - 4:15 PM",
                                        location: "Conference Room 1",
                                        barColor: Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                            
                            // Divider
                            Divider()
                                .padding(.horizontal)
                            
                            // April 13th Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Sunday, April 13")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                                    .padding(.horizontal)
                                
                                // Rotation 1 - Blue
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Rotation 1 • 9:00 AM - 11:00 AM")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                    
                                    WorkshopCard(
                                        title: "Networking Strategies for Success",
                                        time: "9:00 AM - 11:00 AM",
                                        location: "Ballroom A",
                                        barColor: Color(red: 0.2, green: 0.4, blue: 0.8)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Career Pathways in Business",
                                        time: "9:00 AM - 11:00 AM",
                                        location: "Ballroom B",
                                        barColor: Color(red: 0.2, green: 0.4, blue: 0.8)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Digital Marketing & E-Commerce",
                                        time: "9:00 AM - 11:00 AM",
                                        location: "Conference Room 1",
                                        barColor: Color(red: 0.2, green: 0.4, blue: 0.8)
                                    )
                                }
                                
                                // Rotation 2 - Yellow
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Rotation 2 • 11:15 AM - 1:15 PM")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                        .padding(.top, 8)
                                    
                                    WorkshopCard(
                                        title: "Business Ethics & Professional Conduct",
                                        time: "11:15 AM - 1:15 PM",
                                        location: "Ballroom A",
                                        barColor: Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                    
                                    WorkshopCard(
                                        title: "Project Management Essentials",
                                        time: "11:15 AM - 1:15 PM",
                                        location: "Ballroom B",
                                        barColor: Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                    
                                    WorkshopCard(
                                        title: "College & Scholarship Applications",
                                        time: "11:15 AM - 1:15 PM",
                                        location: "Conference Room 1",
                                        barColor: Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                            
                            // Bottom padding
                            Color.clear.frame(height: 20)
                        }
                    }
                }
                VStack(spacing: 0) {
                    // Sticky Header - Fixed on top with logo
                    ZStack {
                        //Blue Sticky Header
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 130)
                        
                        // FBLA Horizontal Logo
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    
                    Spacer()
                    
                }
            }
            .navigationBarHidden(true)
        }
    }

    // Workshop Card Component with colored bar
    struct WorkshopCard: View {
        let title: String
        let time: String
        let location: String
        let barColor: Color
        
        var body: some View {
            HStack(spacing: 0) {
                // Colored bar on the left
                Rectangle()
                    .fill(barColor)
                    .frame(width: 6)
                
                // Workshop Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text(time)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text("University Plaza Hotel - \(location)")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 12)
                .padding(.trailing, 12)
                
                Spacer()
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            .padding(.horizontal)
        }
    }
}

// MARK: - Date Formatter Helper
extension String {
    // Converts RSS pubDate string into formatted dd/MM/yyyy + 12-hour time in device timezone
    func formattedDate() -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"  // Standard RSS format

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale.current
        outputFormatter.timeZone = TimeZone.current
        outputFormatter.dateFormat = "dd/MM/yyyy h:mma"  // desired output

        if let date = inputFormatter.date(from: self) {
            return outputFormatter.string(from: date)
        }
        return self
    }
}

// MARK: - Socials View
struct SocialsView: View {
    @State private var selectedCategory: Post.PostCategory = .all
    @StateObject private var rssParser = RSSFeedParser()

    // Convert RSS items to posts with correct author detection (checks for Instagram handles)
    var rssPosts: [Post] {
        rssParser.items.map { rssItem in

            // Normalize fields we'll check (avoid rssItem.author since it doesn't exist)
            let titleLower = rssItem.title.lowercased()
            let descLower = rssItem.description.lowercased()
            let linkLower = (rssItem.link ?? "").lowercased()

            // Priority checks for known Instagram handles:
            // If any field contains "@fbla_national" or "fbla_national" -> National FBLA
            // If any field contains "@mofbla" or "mofbla" -> Missouri FBLA
            // Fallback: earlier heuristics (title contains 'missouri' etc.), then default to National FBLA
            let isNationalHandle =
                titleLower.contains("@fbla_national") ||
                descLower.contains("@fbla_national") ||
                linkLower.contains("fbla_national") ||
                titleLower.contains("fbla national") ||
                descLower.contains("fbla national")

            let isMissouriHandle =
                titleLower.contains("@mofbla") ||
                descLower.contains("@mofbla") ||
                linkLower.contains("mofbla") ||
                titleLower.contains("mofbla") ||
                descLower.contains("missouri fbla") ||
                titleLower.contains("missouri fbla") ||
                descLower.contains("mofbla")

            let author: String
            if isNationalHandle && !isMissouriHandle {
                author = "National FBLA"
            } else if isMissouriHandle && !isNationalHandle {
                author = "Missouri FBLA"
            } else if isMissouriHandle && isNationalHandle {
                // If both appear, prefer exact handle mention ordering:
                if titleLower.contains("@mofbla") || descLower.contains("@mofbla") || linkLower.contains("mofbla") {
                    author = "Missouri FBLA"
                } else if titleLower.contains("@fbla_national") || descLower.contains("@fbla_national") || linkLower.contains("fbla_national") {
                    author = "National FBLA"
                } else {
                    author = "National FBLA" // default fallback
                }
            } else {
                // Legacy fallback: check for 'missouri' keyword else assume National
                if titleLower.contains("missouri") || titleLower.contains("mo fbla") || titleLower.contains("missouri fbla") || descLower.contains("missouri") {
                    author = "Missouri FBLA"
                } else {
                    author = "National FBLA"
                }
            }

            return Post(
                author: author,
                title: rssItem.title,
                content: rssItem.description,
                imageURL: rssItem.imageURL,
                timestamp: rssItem.pubDate.formattedDate(),
                category: selectedCategory
            )
        }
    }

    // Filter posts (currently no further filtering)
    var filteredPosts: [Post] {
        rssPosts
    }

    // Get correct feed URL
    private func getFeedURL(for category: Post.PostCategory) -> String {
        switch category {
        case .all:
            return "https://rss.app/feeds/pRBbOSgPMEx09OrU.xml"
        case .announcements:
            return "https://rss.app/feeds/tKUevKggHlqWuaQV.xml"
        case .social:
            return "https://rss.app/feeds/EwTo1QTBV0hTb0V2.xml"
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()

                VStack(spacing: 0) {

                    // MARK: Category Tabs
                    GeometryReader { geometry in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 3) {
                                ForEach(Post.PostCategory.allCases, id: \.self) { category in
                                    Button(action: { selectedCategory = category }) {
                                        VStack(spacing: 5) {
                                            Text(category.rawValue)
                                                .font(.system(size: 15, weight: selectedCategory == category ? .semibold : .regular))
                                                .foregroundColor(selectedCategory == category ? Color(red: 0.09, green: 0.25, blue: 0.56) : .gray)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)

                                            Rectangle()
                                                .fill(selectedCategory == category ?
                                                      Color(red: 0.09, green: 0.25, blue: 0.56) :
                                                      Color.clear)
                                                .frame(height: 2)
                                        }
                                        .frame(width: (geometry.size.width - 60) / 3)
                                        .padding(.vertical, 10)
                                    }
                                }
                            }
                            .padding(.horizontal, 3)
                        }
                        .background(Color.white)
                    }
                    .frame(height: 40)
                    .padding(.top, 70)

                    // MARK: Posts
                    ScrollView {
                        VStack(spacing: 15) {

                            if rssParser.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.09, green: 0.25, blue: 0.56)))
                                    .padding()
                            }

                            ForEach(filteredPosts) { post in
                                PostCard(post: post)
                            }
                        }
                        .padding()
                    }
                }

                // MARK: Sticky Header
                VStack {
                    ZStack {
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 130)

                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if rssParser.items.isEmpty {
                rssParser.fetchFeed(urlString: getFeedURL(for: selectedCategory))
            }
        }
        .onChange(of: selectedCategory) { newCategory in
            let feedURL = getFeedURL(for: newCategory)
            rssParser.fetchFeed(urlString: feedURL)
        }
    }
}

// MARK: - Post Card
struct PostCard: View {
    let post: Post
    @State private var showingDetail = false

    var body: some View {
        Button(action: { showingDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {

                // Post Image
                if let imageURL = post.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color(red: 0.20, green: 0.30, blue: 0.40)).frame(height: 200)
                        case .success(let image):
                            image.resizable().scaledToFill().frame(height: 200).clipped()
                        case .failure:
                            Rectangle().fill(Color(red: 0.20, green: 0.30, blue: 0.40)).frame(height: 200)
                        @unknown default:
                            Rectangle().fill(Color(red: 0.20, green: 0.30, blue: 0.40)).frame(height: 200)
                        }
                    }
                    .cornerRadius(15)
                } else {
                    Rectangle()
                        .fill(Color(red: 0.20, green: 0.30, blue: 0.40))
                        .frame(height: 200)
                        .cornerRadius(15)
                }

                VStack(alignment: .leading, spacing: 8) {

                    // Author Badge
                    HStack {
                        Text(post.author)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(
                                post.author == "National FBLA" ?
                                    Color(red: 0.09, green: 0.25, blue: 0.56) :
                                    Color(red: 0.95, green: 0.60, blue: 0.07)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                (post.author == "National FBLA" ?
                                    Color(red: 0.09, green: 0.25, blue: 0.56) :
                                    Color(red: 0.95, green: 0.60, blue: 0.07))
                                    .opacity(0.15)
                            )
                            .cornerRadius(12)

                        Spacer()
                    }

                    Text(post.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)

                    Text(post.content)
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .lineLimit(3)

                    HStack {
                        Text(post.timestamp)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)

                        Spacer()

                        Text("Read More")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 25)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.09, green: 0.25, blue: 0.56))
                            .cornerRadius(20)
                    }
                    .padding(.top, 5)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.white)
            .cornerRadius(15)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            PostDetailView(post: post)
        }
    }
}

// MARK: - Post Detail View
struct PostDetailView: View {
    let post: Post
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Post Image
                    if let imageURL = post.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 250)
                            case .success(let image):
                                image.resizable().scaledToFill().frame(height: 250).clipped()
                            case .failure:
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 250)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 15) {

                        Text(post.author)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)

                        Text(post.title)
                            .font(.system(size: 24, weight: .bold))

                        Text(post.timestamp)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)

                        Divider()

                        Text(post.content)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    }
                }
            }
        }
    }
}

// MARK: - News Detail View
struct NewsDetailView: View {
    let item: RSSItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    if let imageURL = item.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 250)
                            case .success(let image):
                                image.resizable().scaledToFill().frame(height: 250).clipped()
                            case .failure:
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 250)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 15) {

                        Text(item.title)
                            .font(.system(size: 24, weight: .bold))

                        Text(item.pubDate.formattedDate())
                            .font(.system(size: 13))
                            .foregroundColor(.gray)

                        Divider()

                        Text(item.description)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    }
                }
            }
        }
    }
}

// MARK: - Events View
struct EventsView: View {
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    
    // All events with their actual dates
    let allEvents: [(date: Date, event: Event)] = [
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Registration Pick-Up Opens", dateRange: "", time: "9:00 AM", location: "University Plaza Hotel", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Workshop Rotations Begin", dateRange: "", time: "12:00 PM", location: "University Plaza Hotel", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Adviser Meeting", dateRange: "", time: "12:30 PM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Competitive Events Begin", dateRange: "", time: "1:30 PM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Opening Session Begins", dateRange: "", time: "8:00 PM", location: "Great Southern Bank Arena", type: .inPerson, isAllDay: false)),
        
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Leadership Development & Team Building", dateRange: "", time: "12:00 PM - 12:50 PM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Business Plan Competition Prep", dateRange: "", time: "12:00 PM - 12:50 PM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Public Speaking & Presentation Skills", dateRange: "", time: "12:00 PM - 12:50 PM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Resume Writing & Interview Techniques", dateRange: "", time: "1:00 PM - 1:50 PM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Social Media Marketing for Business", dateRange: "", time: "1:00 PM - 1:50 PM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 12))!,
         Event(title: "Financial Literacy & Entrepreneurship", dateRange: "", time: "1:00 PM - 1:50 PM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),
        
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Competitive Events Begin", dateRange: "", time: "8:30 AM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Workshop Rotations Begin", dateRange: "", time: "9:00 AM", location: "University Plaza Hotel", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Member & Programs Awards", dateRange: "", time: "2:30 PM", location: "Great Southern Bank Arena", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Social", dateRange: "", time: "8:00 PM", location: "Springfield Expo Center", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Networking Strategies for Success", dateRange: "", time: "9:00 AM - 9:50 AM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Career Pathways in Business", dateRange: "", time: "9:00 AM - 9:50 AM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Digital Marketing & E-Commerce", dateRange: "", time: "9:00 AM - 9:50 AM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Business Ethics & Professional Conduct", dateRange: "", time: "10:00 AM - 10:50 AM", location: "University Plaza Hotel - Ballroom A", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "Project Management Essentials", dateRange: "", time: "10:00 AM - 10:50 AM", location: "University Plaza Hotel - Ballroom B", type: .inPerson, isAllDay: false)),

        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 13))!,
         Event(title: "College & Scholarship Applications", dateRange: "", time: "10:00 AM - 10:50 AM", location: "University Plaza Hotel - Conference Room 1", type: .inPerson, isAllDay: false)),
        
        (Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 14))!,
         Event(title: "Awards of Excellence Ceremony", dateRange: "", time: "8:00 AM", location: "Great Southern Bank Arena", type: .inPerson, isAllDay: false)),
        
        // June 29, 2026
        (Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 29))!,
         Event(title: "National Leadership Conference", dateRange: "", time: "All Day", location: "San Antonio, TX", type: .inPerson, isAllDay: true)),
    ]
    
    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
    
    // Get 7 days centered around selected date (3 before, selected, 3 after)
    private var weekDays: [Date] {
        let calendar = Calendar.current
        return (-3...3).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: selectedDate)
        }
    }
    
    // Filter events for the selected date
    private var eventsForSelectedDate: [Event] {
        let calendar = Calendar.current
        return allEvents
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .map { $0.event }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Sticky Header - Fixed on top with logo
                    VStack {
                        ZStack {
                            //Blue Sticky Header
                            Color(red: 0.09, green: 0.25, blue: 0.56)
                                .frame(height: 130)
                            
                            // FBLA Horizontal Logo
                            Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 175)
                                .padding(.top, 40)
                        }
                        .ignoresSafeArea(.all)
                    }
                    
                    Spacer()
                    
                }
                
                // Scrollable content overlay
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        Spacer(minLength:50)
                        // Month Navigation
                        HStack {
                            Button(action: {
                                // Go back one week
                                if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
                                    selectedDate = newDate
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.black)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            
                            Spacer()
                            
                            Text(monthYearText)
                                .font(.system(size: 24, weight: .bold))
                            
                            Spacer()
                            
                            Button(action: {
                                // Go forward one week
                                if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
                                    selectedDate = newDate
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.black)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                        
                        // Week View - Full width, not scrollable
                        HStack(spacing: 12) {
                            ForEach(weekDays, id: \.self) { date in
                                WeekDayCell(
                                    date: date,
                                    isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedDate = date
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Scrollable Events List
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Text("Events for \(formattedSelectedDate)")
                                        .font(.system(size: 20, weight: .bold))
                                }
                                .padding(.horizontal)
                                
                                if eventsForSelectedDate.isEmpty {
                                    // No events message
                                    VStack(spacing: 12) {
                                        Image(systemName: "calendar.badge.exclamationmark")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray.opacity(0.5))
                                        
                                        Text("No events scheduled")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.gray)
                                        
                                        Text("Tap a different date to see other events")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                    .padding(.horizontal)
                                } else {
                                    ForEach(eventsForSelectedDate) { event in
                                        EventDetailCard(event: event)
                                            .padding(.horizontal)
                                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                    }
                                }
                                
                                // Bottom padding
                                Color.clear.frame(height: 20)
                            }
                            .padding(.top, 10)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Initialize with today's date
            selectedDate = Date()
        }
    }
    
    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - Week Day Cell
struct WeekDayCell: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var dayOfMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(dayOfWeek)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : (isToday ? Color(red: 0.957, green: 0.671, blue: 0.098) : .gray))
                
                Text(dayOfMonth)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : (isToday ? Color(red: 0.957, green: 0.671, blue: 0.098) : .black))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? Color(red: 0.09, green: 0.25, blue: 0.56) : Color.clear)
            .cornerRadius(35)
            .overlay(
                RoundedRectangle(cornerRadius: 35)
                    .stroke(isToday && !isSelected ? Color(red: 0.957, green: 0.671, blue: 0.098) : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct EventDetailCard: View {
    let event: Event
    @State private var isReminderSet = false
    @State private var showingReminderOptions = false
    @State private var showingCalendarAlert = false
    @State private var calendarAlertMessage = ""
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 15) {
                // Color bar
                Rectangle()
                    .fill(event.isAllDay ? Color(red: 0.09, green: 0.25, blue: 0.56) : Color(red: 0.95, green: 0.60, blue: 0.07))
                    .frame(width: 5)
                    .cornerRadius(2.5)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                    
                    Text(event.time)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Text(event.location)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Button stack on the right
                VStack(spacing: 8) {
                    // Only show bell button for non-all-day events
                    if !event.isAllDay {
                        Button(action: {
                            if isReminderSet {
                                // Cancel the notification
                                NotificationManager.shared.cancelNotification(for: event)
                                isReminderSet = false
                            } else {
                                // Show options to set notification
                                showingReminderOptions = true
                            }
                        }) {
                            Image(systemName: isReminderSet ? "bell.fill" : "bell")
                                .foregroundColor(isReminderSet ? Color(red: 0x5c/255.0, green: 0x5c/255.0, blue: 0x5c/255.0) : .gray)
                                .font(.system(size: 20))
                        }
                    }
                    
                    // Add to Calendar button - now always shown
                    Button(action: {
                        CalendarManager.shared.addEventToCalendar(event: event) { success, message in
                            calendarAlertMessage = message
                            showingCalendarAlert = true
                        }
                    }) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundColor(.gray)
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .confirmationDialog("When would you like to be reminded?", isPresented: $showingReminderOptions) {
            Button("15 minutes before") {
                scheduleNotification(minutesBefore: 15)
            }
            Button("30 minutes before") {
                scheduleNotification(minutesBefore: 30)
            }
            Button("1 hour before") {
                scheduleNotification(minutesBefore: 60)
            }
            Button("1 day before") {
                scheduleNotification(minutesBefore: 1440)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Calendar", isPresented: $showingCalendarAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarAlertMessage)
        }
    }
    
    private func scheduleNotification(minutesBefore: Int) {
        NotificationManager.shared.requestPermission { granted in
            if granted {
                NotificationManager.shared.scheduleEventNotification(
                    for: event,
                    minutesBefore: minutesBefore
                ) { success in
                    if success {
                        isReminderSet = true
                    }
                }
            }
        }
    }
}

// MARK: - Study Materials
struct StudyView: View {
    // URLs to PDFs (hosted on AWS or any server)
        let pdfs: [(title: String, url: String)] = [
            ("Accounting-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Accounting-Sample-Questions.pdf"),
            ("Advertising-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Advertising-Sample-Questions.pdf"),
            ("Agribusiness-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Agribusiness-Sample-Questions.pdf"),
            ("Banking-and-Financial-Systems---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-1.pdf"),
            ("Banking-and-Financial-Systems---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-2.pdf"),
            ("Banking-and-Financial-Systems---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-3.pdf"),
            ("Banking-and-Financial-Systems---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-4.pdf"),
            ("Banking-and-Financial-Systems---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-5.pdf"),
            ("Banking-and-Financial-Systems---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-6.pdf"),
            ("Banking-and-Financial-Systems---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-7.pdf"),
            ("Banking-and-Financial-Systems---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Banking-and-Financial-Systems---Sample-8.pdf"),
            ("Business-Communication-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Communication-Sample-Questions.pdf"),
            ("Business-Management---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-1.pdf"),
            ("Business-Management---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-2.pdf"),
            ("Business-Management---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-3.pdf"),
            ("Business-Management---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-4.pdf"),
            ("Business-Management---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-5.pdf"),
            ("Business-Management---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-6.pdf"),
            ("Business-Management---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-7.pdf"),
            ("Business-Management---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-8.pdf"),
            ("Business-Management---Sample-9", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-9.pdf"),
            ("Business-Management---Sample-10", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Business-Management---Sample-10.pdf"),
            ("Computer-Problem-Solving-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Computer-Problem-Solving-Sample-Questions.pdf"),
            ("Customer-Service---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-1.pdf"),
            ("Customer-Service---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-2.pdf"),
            ("Customer-Service---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-3.pdf"),
            ("Customer-Service---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-4.pdf"),
            ("Customer-Service---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-5.pdf"),
            ("Customer-Service---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-6.pdf"),
            ("Customer-Service---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-7.pdf"),
            ("Customer-Service---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-8.pdf"),
            ("Customer-Service---Sample-9", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-9.pdf"),
            ("Customer-Service---Sample-10", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-10.pdf"),
            ("Customer-Service---Sample-11", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-11.pdf"),
            ("Customer-Service---Sample-12", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Customer-Service---Sample-12.pdf"),
            ("Cybersecurity-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Cybersecurity-Sample-Questions.pdf"),
            ("Economics-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Economics-Sample-Questions.pdf"),
            ("Entrepreneurship---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-1.pdf"),
            ("Entrepreneurship---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-2.pdf"),
            ("Entrepreneurship---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-3.pdf"),
            ("Entrepreneurship---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-4.pdf"),
            ("Entrepreneurship---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-5.pdf"),
            ("Entrepreneurship---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-6.pdf"),
            ("Entrepreneurship---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Entrepreneurship---Sample-7.pdf"),
            ("Healthcare-Administration-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Healthcare-Administration-Sample-Questions.pdf"),
            ("Hospitality--Event-Management---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-1.pdf"),
            ("Hospitality--Event-Management---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-2.pdf"),
            ("Hospitality--Event-Management---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-3.pdf"),
            ("Hospitality--Event-Management---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-4.pdf"),
            ("Hospitality--Event-Management---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-5.pdf"),
            ("Hospitality--Event-Management---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-6.pdf"),
            ("Hospitality--Event-Management---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-7.pdf"),
            ("Hospitality--Event-Management---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-8.pdf"),
            ("Hospitality--Event-Management---Sample-9", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-9.pdf"),
            ("Hospitality--Event-Management---Sample-10", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-10.pdf"),
            ("Hospitality--Event-Management---Sample-11", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-11.pdf"),
            ("Hospitality--Event-Management---Sample-12", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-12.pdf"),
            ("Hospitality--Event-Management---Sample-13", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-13.pdf"),
            ("Hospitality--Event-Management---Sample-14", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-14.pdf"),
            ("Hospitality--Event-Management---Sample-15", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Hospitality--Event-Management---Sample-15.pdf"),
            ("Impromptu-Speaking---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-1.pdf"),
            ("Impromptu-Speaking---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-2.pdf"),
            ("Impromptu-Speaking---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-3.pdf"),
            ("Impromptu-Speaking---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-4.pdf"),
            ("Impromptu-Speaking---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-5.pdf"),
            ("Impromptu-Speaking---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-6.pdf"),
            ("Impromptu-Speaking---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-7.pdf"),
            ("Impromptu-Speaking---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-8.pdf"),
            ("Impromptu-Speaking---Sample-9", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-9.pdf"),
            ("Impromptu-Speaking---Sample-10", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-10.pdf"),
            ("Impromptu-Speaking---Sample-11", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Impromptu-Speaking---Sample-11.pdf"),
            ("International-Business---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-1.pdf"),
            ("International-Business---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-2.pdf"),
            ("International-Business---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-3.pdf"),
            ("International-Business---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-4.pdf"),
            ("International-Business---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-5.pdf"),
            ("International-Business---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-6.pdf"),
            ("International-Business---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-7.pdf"),
            ("International-Business---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/International-Business---Sample-8.pdf"),
            ("Intro-to-Business-Communication-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Intro-to-Business-Communication-Sample-Questions.pdf"),
            ("Intro-to-Business-Concepts-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Intro-to-Business-Concepts-Sample-Questions.pdf"),
            ("Intro-to-FBLA-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Intro-to-FBLA-Sample-Questions.pdf"),
            ("Intro-to-Information-Technology-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Intro-to-Information-Technology-Sample-Questions.pdf"),
            ("Journalism-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Journalism-Sample-Questions.pdf"),
            ("Management-Information-Systems---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-1.pdf"),
            ("Management-Information-Systems---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-2.pdf"),
            ("Management-Information-Systems---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-3.pdf"),
            ("Management-Information-Systems---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-4.pdf"),
            ("Management-Information-Systems---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-5.pdf"),
            ("Management-Information-Systems---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-6.pdf"),
            ("Management-Information-Systems---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Management-Information-Systems---Sample-7.pdf"),
            ("Marketing---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-1.pdf"),
            ("Marketing---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-2.pdf"),
            ("Marketing---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-3.pdf"),
            ("Marketing---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-4.pdf"),
            ("Marketing---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-5.pdf"),
            ("Marketing---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-6.pdf"),
            ("Marketing---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-7.pdf"),
            ("Marketing---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing---Sample-8.pdf"),
            ("Marketing-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Marketing-Sample-Questions.pdf"),
            ("Network-Design---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-2.pdf"),
            ("Network-Design---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-3.pdf"),
            ("Network-Design---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-4.pdf"),
            ("Network-Design---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-5.pdf"),
            ("Network-Design---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-6.pdf"),
            ("Network-Design---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-7.pdf"),
            ("Network-Design---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Network-Design---Sample-8.pdf"),
            ("Parliamentary-Procedure---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-1.pdf"),
            ("Parliamentary-Procedure---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-2.pdf"),
            ("Parliamentary-Procedure---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-3.pdf"),
            ("Parliamentary-Procedure---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-4.pdf"),
            ("Parliamentary-Procedure---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-5.pdf"),
            ("Parliamentary-Procedure---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-6.pdf"),
            ("Parliamentary-Procedure---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-7.pdf"),
            ("Parliamentary-Procedure---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Parliamentary-Procedure---Sample-8.pdf"),
            ("Personal-Finance-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Personal-Finance-Sample-Questions.pdf"),
            ("Real-Estate-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Real-Estate-Sample-Questions.pdf"),
            ("Retail-Management-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Retail-Management-Sample-Questions.pdf"),
            ("Sports--Entertainment-Management-Sample-Questions", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports--Entertainment-Management-Sample-Questions.pdf"),
            ("Sports-and-Entertainment-Management---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-1.pdf"),
            ("Sports-and-Entertainment-Management---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-2.pdf"),
            ("Sports-and-Entertainment-Management---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-3.pdf"),
            ("Sports-and-Entertainment-Management---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-4.pdf"),
            ("Sports-and-Entertainment-Management---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-5.pdf"),
            ("Sports-and-Entertainment-Management---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-6.pdf"),
            ("Sports-and-Entertainment-Management---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Sports-and-Entertainment-Management---Sample-7.pdf"),
            ("Technology-Support--Services---Sample-1", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-1.pdf"),
            ("Technology-Support--Services---Sample-2", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-2.pdf"),
            ("Technology-Support--Services---Sample-3", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-3.pdf"),
            ("Technology-Support--Services---Sample-4", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-4.pdf"),
            ("Technology-Support--Services---Sample-5", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-5.pdf"),
            ("Technology-Support--Services---Sample-6", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-6.pdf"),
            ("Technology-Support--Services---Sample-7", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-7.pdf"),
            ("Technology-Support--Services---Sample-8", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Technology-Support--Services---Sample-8.pdf")
        ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                // Scrollable List
                List(pdfs, id: \.title) { pdf in
                    NavigationLink(pdf.title) {
                        PDFDetailView(pdfURL: URL(string: pdf.url)!, title: pdf.title)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // prevents see-through

                // Sticky Header
                ZStack {
                    Color(red: 0.09, green: 0.25, blue: 0.56)
                        .frame(height: 130) // fixed header height
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: 6) {
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    .frame(maxHeight: 130, alignment: .top) // key fix
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

//MARK: - CompetitiveEventView
struct CompetitiveEventView: View {
    // URLs to PDFs (hosted on AWS or any server)
        let pdfs: [(title: String, url: String)] = [
            ("Accounting", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Accounting.pdf"),
            ("Advanced Accounting", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Advanced-Accounting.pdf"),
            ("Advertising", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Advertising.pdf"),
            ("Agribusiness", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Agribusiness.pdf"),
            ("Banking & Financial Systems", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Banking-and-Financial-Systems.pdf"),
            ("Broadcast Journalism", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Broadcast-Journalism.pdf"),
            ("Business Communication", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Business-Communication.pdf"),
            ("Business Ethics", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Business-Ethics.pdf"),
            ("Business Law", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Business-Law.pdf"),
            ("Business Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Business-Management.pdf"),
            ("Business Plan", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Business-Plan.pdf"),
            ("Career Portfolio", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Career-Portfolio.pdf"),
            ("Coding & Programming", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Coding-and-Programming.pdf"),
            ("Community Service Project", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Community-Service-Project.pdf"),
            ("Computer Applications", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Computer-Applications.pdf"),
            ("Computer Game & Simulation Programming", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Computer-Game-Simulation-Programming.pdf"),
            ("Customer Service", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Customer-Service.pdf"),
            ("Cybersecurity", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Cybersecurity.pdf"),
            ("Data Analysis", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Data-Analysis.pdf"),
            ("Data Science & AI", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Data-Science-and-AI.pdf"),
            ("Digital Animation", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Digital-Animation.pdf"),
            ("Digital Video Production", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Digital-Video-Production.pdf"),
            ("Economics", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Economics.pdf"),
            ("Entrepreneurship", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Entrepreneurship.pdf"),
            ("Event Planning", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Event-Planning.pdf"),
            ("Financial Planning", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Financial-Planning.pdf"),
            ("Financial Statement Analysis", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Financial-Statement-Analysis.pdf"),
            ("Future Business Educator", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Future-Business-Educator.pdf"),
            ("Future Business Leader", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Future-Business-Leader.pdf"),
            ("Graphic Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Graphic-Design.pdf"),
            ("Healthcare Administration", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Healthcare-Administration.pdf"),
            ("Hospitality & Event Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Hospitality-and-Event-Management.pdf"),
            ("Human Resource Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Human-Resource-Management.pdf"),
            ("Impromptu Speaking", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Impromptu-Speaking.pdf"),
            ("Insurance & Risk Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Insurance-and-Risk-Management.pdf"),
            ("International Business", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/International-Business.pdf"),
            ("Introduction to Business Communication", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Business-Communication.pdf"),
            ("Introduction to Business Concepts", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Business-Concepts.pdf"),
            ("Introduction to Business Presentation", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Business-Presentation.pdf"),
            ("Introduction to Business Procedures", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Business-Procedures.pdf"),
            ("Introduction to FBLA", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-FBLA.pdf"),
            ("Introduction to Information Technology", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Information-Technology.pdf"),
            ("Introduction to Marketing Concepts", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Marketing-Concepts.pdf"),
            ("Introduction to Parliamentary Procedure", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Parliamentary-Procedure.pdf"),
            ("Introduction to Programming", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Programming.pdf"),
            ("Introduction to Public Speaking", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Public-Speaking.pdf"),
            ("Introduction to Retail & Merchandising", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Retail-and-Merchandising.pdf"),
            ("Introduction to Social Media Strategy", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Social-Media-Strategy.pdf"),
            ("Introduction to Supply Chain Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Introduction-to-Supply-Chain-Management.pdf"),
            ("Job Interview", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Job-Interview.pdf"),
            ("Journalism", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Journalism.pdf"),
            ("Local Chapter Annual Business Report", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Local-Chapter-Annual-Business-Report.pdf"),
            ("Management Information Systems", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Management-Information-Systems.pdf"),
            ("Marketing", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Marketing.pdf"),
            ("Mobile Application Development", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Mobile-Application-Development.pdf"),
            ("Network Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Network-Design.pdf"),
            ("Networking Infrastructures", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Networking-Infrastructures.pdf"),
            ("Organizational Leadership", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Organizational-Leadership.pdf"),
            ("Parliamentary Procedure", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Parliamentary-Procedure.pdf"),
            ("Personal Finance", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Personal-Finance.pdf"),
            ("Project Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Project-Management.pdf"),
            ("Public Administration & Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Public-Administration-and-Management.pdf"),
            ("Public Service Announcement", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Public-Service-Announcement.pdf"),
            ("Public Speaking", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Public-Speaking.pdf"),
            ("Real Estate", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Real-Estate.pdf"),
            ("Retail Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Retail-Management.pdf"),
            ("Sales Presentation", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Sales-Presentation.pdf"),
            ("Securities & Investments", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Securities-and-Investments.pdf"),
            ("Social Media Strategies", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Social-Media-Strategies.pdf"),
            ("Sports & Entertainment Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Sports-and-Entertainment-Management.pdf"),
            ("Supply Chain Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Supply-Chain-Management.pdf"),
            ("Technology Support & Services", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Technology-Support-and-Services.pdf"),
            ("Visual Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Visual-Design.pdf"),
            ("Website Coding & Development", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Website-Coding-and-Development.pdf"),
            ("Website Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/events/Website-Design.pdf")
        ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                // Scrollable List
                List(pdfs, id: \.title) { pdf in
                    NavigationLink(pdf.title) {
                        PDFDetailView(pdfURL: URL(string: pdf.url)!, title: pdf.title)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // prevents see-through

                // Sticky Header
                ZStack {
                    Color(red: 0.09, green: 0.25, blue: 0.56)
                        .frame(height: 130) // fixed header height
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: 6) {
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    .frame(maxHeight: 130, alignment: .top) // key fix
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Results View
struct ResultsView: View {
    // URLs to PDFs (hosted on AWS or any server)
        let pdfs: [(title: String, url: String)] = [
            ("Accounting", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Advanced Accounting", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Advertising", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Agribusiness", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Banking & Financial Systems", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Broadcast Journalism", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Business Communication", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Business Ethics", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Business Law", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Business Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Business Plan", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Career Portfolio", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Coding & Programming", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Community Service Project", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Computer Applications", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Computer Game & Simulation Programming", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Customer Service", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Cybersecurity", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Data Analysis", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Data Science & AI", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Digital Animation", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Digital Video Production", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Economics", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Entrepreneurship", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Event Planning", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Financial Planning", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Financial Statement Analysis", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Future Business Educator", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Future Business Leader", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Graphic Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Healthcare Administration", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Hospitality & Event Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Human Resource Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Impromptu Speaking", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Insurance & Risk Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("International Business", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Business Communication", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Business Concepts", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Business Presentation", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Business Procedures", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to FBLA", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Information Technology", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Marketing Concepts", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Parliamentary Procedure", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Programming", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Public Speaking", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Retail & Merchandising", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Social Media Strategy", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Introduction to Supply Chain Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Job Interview", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Journalism", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Local Chapter Annual Business Report", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Management Information Systems", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Marketing", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Mobile Application Development", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Network Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Networking Infrastructures", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Organizational Leadership", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Parliamentary Procedure", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Personal Finance", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Project Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Public Administration & Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Public Service Announcement", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Public Speaking", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Real Estate", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Retail Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Sales Presentation", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Securities & Investments", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Social Media Strategies", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Sports & Entertainment Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Supply Chain Management", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Technology Support & Services", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Visual Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Website Coding & Development", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf"),
            ("Website Design", "https://2026-fbla.s3.us-east-2.amazonaws.com/pdf/Results.pdf")
        ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                // Scrollable List
                List(pdfs, id: \.title) { pdf in
                    NavigationLink(pdf.title) {
                        PDFDetailView(pdfURL: URL(string: pdf.url)!, title: pdf.title)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // prevents see-through

                // Sticky Header
                ZStack {
                    Color(red: 0.09, green: 0.25, blue: 0.56)
                        .frame(height: 130) // fixed header height
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: 6) {
                        Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 175)
                            .padding(.top, 40)
                    }
                    .ignoresSafeArea(.all)
                    .frame(maxHeight: 130, alignment: .top) // key fix
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Resources View
struct ResourcesView: View {
    @State private var searchText = ""
    @State private var showingWebBrowser = false
    @State private var browserURL: URL?
    @FocusState private var isSearchFocused: Bool
    @State private var showingInternalView = false
    @State private var selectedView: AnyView? = nil

    enum ContentDestination {
        case url(URL)
        case view(AnyView)
    }

    let quickAccessItems: [(title: String, icon: String, destination: ContentDestination)] = [
        ("Competitive Events", "trophy", .view(AnyView(CompetitiveEventView()))),
        ("Study Materials", "long.text.page.and.pencil", .view(AnyView(StudyView()))),
        ("Magazine", "book.pages", .url(URL(string: "https://www.fbla.org/tomorrows-business-leader/")!)),
        ("Scholarships", "dollarsign", .url(URL(string: "https://www.fbla.org/high-school/hs-scholarships-aid/")!))
    ]

    let documents = [
        Resource(title: "Mobile Application Development", fileSize: "270 KB", type: "PDF", url: URL(string: "https://2026-fbla.s3.us-east-2.amazonaws.com/Mobile-Application-Development.pdf"))
    ]

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let encodedQuery = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let searchURL = URL(string: "https://www.fbla.org/?s=\(encodedQuery)") {
            browserURL = searchURL
            showingWebBrowser = true
            isSearchFocused = false
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Sticky Header
                    VStack {
                        ZStack {
                            Color(red: 0.09, green: 0.25, blue: 0.56)
                                .frame(height: 130)
                            Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 175)
                                .padding(.top, 40)
                        }
                        .ignoresSafeArea(.all)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Search fbla.org", text: $searchText)
                                    .focused($isSearchFocused)
                                    .onSubmit { performSearch() }
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(25)
                            .padding(.horizontal)
                            .padding(.top, 5)

                            // Quick Access
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Quick Access")
                                    .font(.system(size: 24, weight: .bold))
                                    .padding(.horizontal)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                    ForEach(quickAccessItems, id: \.title) { item in
                                        ContentCard(title: item.title, icon: item.icon) {
                                            switch item.destination {
                                            case .url(let link):
                                                browserURL = link
                                                showingWebBrowser = true
                                            case .view(let view):
                                                selectedView = AnyView(view)
                                                showingInternalView = true
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }

                            // All Documents
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Pinned Resources")
                                    .font(.system(size: 24, weight: .bold))
                                    .padding(.horizontal)

                                ForEach(documents) { doc in
                                    DocumentRow(resource: doc) {
                                        if let url = doc.url {
                                            browserURL = url
                                            showingWebBrowser = true
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }

                // Hidden NavigationLink for StudyView
                NavigationLink(destination: selectedView, isActive: $showingInternalView) {
                    EmptyView()
                }
                .hidden()
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingWebBrowser) {
            if let url = browserURL {
                WebBrowserView(url: url)
            }
        }
    }
}


struct QuickAccessCard: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    .padding()
                    .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(Color.white)
            .cornerRadius(15)
        }
    }
}

struct DocumentRow: View {
    let resource: Resource
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: "doc.fill")
                    .resizable()
                    .frame(width: 30, height: 35)
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                    
                    Text("\(resource.type) - \(resource.fileSize)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var pushNotifications = true
    @State private var eventReminders = true
    @State private var showingProfile = false
    @State private var showingWebBrowser = false
    @State private var browserURL: URL?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                
                //Actuall Settings
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        Spacer(minLength: 50)
                        // Account Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Account")
                                .font(.system(size: 28, weight: .bold))
                                .padding(.horizontal)
                                .padding(.bottom, 15)
                            
                            VStack(spacing: 0) {
                                SettingsRow(icon: "person.fill", title: "Edit Profile", showChevron: true) {
                                    showingProfile = true
                                }
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "lock.fill", title: "Change Password", showChevron: true) {}
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "envelope.fill", title: "Manage Email Address", showChevron: true) {}
                            }
                            .background(Color.white)
                            .cornerRadius(15)
                            .padding(.horizontal)
                        }
                        
                        // Notifications Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Notifications")
                                .font(.system(size: 28, weight: .bold))
                                .padding(.horizontal)
                                .padding(.bottom, 15)
                            
                            VStack(spacing: 0) {
                                SettingsToggleRow(icon: "bell.fill", title: "Push Notifications", isOn: $pushNotifications)
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "envelope.badge.fill", title: "Email Notifications", showChevron: true) {}
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsToggleRow(icon: "calendar.badge.clock", title: "Event Reminders", isOn: $eventReminders)
                            }
                            .background(Color.white)
                            .cornerRadius(15)
                            .padding(.horizontal)
                        }
                        
                        // General Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("General")
                                .font(.system(size: 28, weight: .bold))
                                .padding(.horizontal)
                                .padding(.bottom, 15)
                            
                            VStack(spacing: 0) {
                                SettingsRow(icon: "shield.fill", title: "Privacy Settings", showChevron: true) {}
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support", showChevron: true) {
                                    browserURL = URL(string: "https://www.fbla.zendesk.com/hc/en-us/")
                                    showingWebBrowser = true
                                }
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "info.circle.fill", title: "About FBLA", showChevron: true) {
                                    browserURL = URL(string: "https://www.fbla.org/about/")
                                    showingWebBrowser = true
                                }
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "paintbrush.fill", title: "FBLA Brand Center", showChevron: true) {
                                    browserURL = URL(string: "https://www.fbla.org/brand-center/")
                                    showingWebBrowser = true
                                }
                                
                                Divider()
                                    .padding(.leading, 70)
                                
                                SettingsRow(icon: "doc.text.fill", title: "Terms of Service", showChevron: true) {}
                            }
                            .background(Color.white)
                            .cornerRadius(15)
                            .padding(.horizontal)
                        }
                        
                        // Logout Button
                        Button(action: {
                            appState.logout()
                        }) {
                            Text("Logout")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 55)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(15)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                    }
                    .padding(.vertical, 20)
                }
                
                // Sticky Header - Fixed on top with logo
                VStack {
                    ZStack {
                        //Blue Sticky Header
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 130)
                        
                    // FBLA Horizontal Logo
                    Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 175)
                        .padding(.top, 40)   // adjust this ONE number to place it on the bar

                    }
                    .ignoresSafeArea(.all)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingWebBrowser) {
            if let url = browserURL {
                WebBrowserView(url: url)
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let showChevron: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    .frame(width: 45, height: 45)
                    .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                    .cornerRadius(10)
                
                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(.black)
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            .padding()
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                .frame(width: 45, height: 45)
                .background(Color(red: 0.09, green: 0.25, blue: 0.56).opacity(0.1))
                .cornerRadius(10)
            
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(.black)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding()
    }
}

// MARK: - Profile View
struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @State private var showingImagePicker = false
    @State private var showingImageSourcePicker = false
    @State private var showingCropView = false
    @State private var imageToCrop: UIImage?
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    ZStack {
                        Color(red: 0.09, green: 0.25, blue: 0.56)
                            .frame(height: 145)
                        
                        HStack {
                            // FBLA Horizontal Logo
                            Image("FBLA_Logo_Horizontal_color-Reverse-HiRes")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 175)
                                .padding(.top, 40)   // adjust this ONE number to place it on the bar
                            
                            Spacer()
                            
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Profile Image
                            Button(action: {
                                showingImageSourcePicker = true
                            }) {
                                if let image = appState.selectedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 150, height: 150)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                } else {
                                    Image("default")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 150, height: 150)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                }
                            }
                            .padding(.top, 20)
                            
                            // Name and Role
                            VStack(spacing: 5) {
                                Text(appState.currentUser?.name ?? "User Name")
                                    .font(.system(size: 28, weight: .bold))
                                
                                Text(appState.currentUser?.role ?? "Member")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                                
                                Text("Membership ID: \(appState.currentUser?.membershipID ?? "12345678")")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            // Tabs
                            HStack(spacing: 0) {
                                Button(action: { selectedTab = 0 }) {
                                    Text("Details")
                                        .font(.system(size: 16, weight: selectedTab == 0 ? .semibold : .regular))
                                        .foregroundColor(selectedTab == 0 ? Color(red: 0.09, green: 0.25, blue: 0.56) : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 15)
                                        .background(selectedTab == 0 ? Color.white : Color.gray.opacity(0.1))
                                        .cornerRadius(10)
                                }
                                
                                Button(action: { selectedTab = 1 }) {
                                    Text("Achievements")
                                        .font(.system(size: 16, weight: selectedTab == 1 ? .semibold : .regular))
                                        .foregroundColor(selectedTab == 1 ? Color(red: 0.09, green: 0.25, blue: 0.56) : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 15)
                                        .background(selectedTab == 1 ? Color.white : Color.gray.opacity(0.1))
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 10)
                            
                            if selectedTab == 0 {
                                // Personal Information
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Personal Information")
                                        .font(.system(size: 24, weight: .bold))
                                        .padding(.horizontal)
                                    
                                    VStack(spacing: 15) {
                                        ProfileInfoRow(icon: "envelope.fill", title: "Email", value: appState.currentUser?.email ?? "")
                                        
                                        ProfileInfoRow(icon: "phone.fill", title: "Phone Number", value: appState.currentUser?.phoneNumber ?? "")
                                        
                                        ProfileInfoRow(icon: "building.2.fill", title: "School", value: "\(appState.currentUser?.school ?? "")")
       
                                        ProfileInfoRow(icon: "graduationcap.fill", title: "Graduation Year", value: "\(appState.currentUser?.graduationYear ?? "")")
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(15)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                                
                                // FBLA Chapter Details
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("FBLA Chapter Details")
                                        .font(.system(size: 24, weight: .bold))
                                        .padding(.horizontal)
                                    
                                    VStack(spacing: 15) {
                                        ProfileInfoRow(icon: "person.3.fill", title: "Chapter Name / Number", value: "\(appState.currentUser?.chapter ?? "") \(appState.currentUser?.chapterNumber ?? "")")
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(15)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                            } else {
                                //2023
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("2023 (Freshman)")
                                        .font(.system(size: 24, weight: .bold))
                                        .padding(.horizontal)
                                    
                                    VStack(spacing: 15) {
                                        ProfileInfoRow(icon: "trophy", title: "Introduction to Information Technology", value: "1st Place | State")

                                        ProfileInfoRow(icon: "trophy", title: "Introduction to Information Technology", value: "1st Place | District")

                                        ProfileInfoRow(icon: "trophy", title: "Spreadsheet Applications", value: "1st Place | District")
                                        
                                        ProfileInfoRow(icon: "trophy", title: "Computer Problem Solving", value: "2nd Place | District")
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(15)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                                
                                //2024
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("2024 (Sophomore)")
                                        .font(.system(size: 24, weight: .bold))
                                        .padding(.horizontal)
                                    
                                    VStack(spacing: 15) {
                                        ProfileInfoRow(icon: "trophy", title: "Introduction to Information Technology", value: "1st Place | State")

                                        ProfileInfoRow(icon: "trophy", title: "Computer Applications", value: "1st Place | State")
                                        
                                        ProfileInfoRow(icon: "trophy", title: "Introduction to Information Technology", value: "1st Place | District")

                                        ProfileInfoRow(icon: "trophy", title: "Computer Applications", value: "1st Place | District")
                                        
                                        ProfileInfoRow(icon: "trophy", title: "Computer Problem Solving", value: "2nd Place | District")
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(15)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                                
                                //2025
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("2025 (Junior)")
                                        .font(.system(size: 24, weight: .bold))
                                        .padding(.horizontal)
                                    
                                    VStack(spacing: 15) {
                                        ProfileInfoRow(icon: "trophy", title: "Website Coding & Development", value: "5th Place | State")

                                        ProfileInfoRow(icon: "trophy", title: "Compueter Problem Solving", value: "5th Place | State")

                                        ProfileInfoRow(icon: "trophy", title: "Computer Problem Solving", value: "1st Place | District")
                                        
                                        ProfileInfoRow(icon: "trophy", title: "Agribusiness", value: "2nd Place | District")
                                        
                                        ProfileInfoRow(icon: "trophy", title: "Computer Applications", value: "3rd Place | District")
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(15)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                                
                                //2026
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("2026 (Senior)")
                                        .font(.system(size: 24, weight: .bold))
                                        .padding(.horizontal)
                                    
                                    VStack(spacing: 15) {
                                        ProfileInfoRow(icon: "trophy", title: "Agribusiness", value: "1st Place | District")

                                        ProfileInfoRow(icon: "trophy", title: "Cybersecurity", value: "1st Place | District")

                                        ProfileInfoRow(icon: "trophy", title: "Computer Applications", value: "1st Place | District")
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(15)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .confirmationDialog("Choose Image Source", isPresented: $showingImageSourcePicker) {
            Button("Camera") {
                sourceType = .camera
                showingImagePicker = true
            }
            Button("Photo Library") {
                sourceType = .photoLibrary
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                sourceType: sourceType,
                selectedImage: $appState.selectedImage,
                showingCropView: $showingCropView,
                imageToCrop: $imageToCrop
            )
        }
        .sheet(isPresented: $showingCropView) {
            ImageCropView(
                image: $imageToCrop,
                croppedImage: $appState.selectedImage
            )
        }
    }
}

struct ProfileInfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundColor(.black)
                .frame(width: 40, height: 40)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Binding var showingCropView: Bool
    @Binding var imageToCrop: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        
        // Set camera to front-facing (selfie mode) by default
        if sourceType == .camera {
            picker.cameraDevice = .front
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // For camera, use directly; for photo library, show crop view
                if parent.sourceType == .camera {
                    parent.selectedImage = image
                } else {
                    parent.imageToCrop = image
                    parent.showingCropView = true
                }
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Image Crop View
struct ImageCropView: View {
    @Binding var image: UIImage?
    @Binding var croppedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    let cropSize: CGFloat = min(geometry.size.width, geometry.size.height) * 0.8
                    
                    ZStack {
                        // The image that can be moved and scaled
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(offset)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let delta = value / lastScale
                                            lastScale = value
                                            scale *= delta
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                        }
                                )
                                .simultaneousGesture(
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                        }
                        
                        // Overlay with crop circle
                        ZStack {
                            // Dark overlay
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                                .mask(
                                    Rectangle()
                                        .overlay(
                                            Circle()
                                                .frame(width: cropSize, height: cropSize)
                                                .blendMode(.destinationOut)
                                        )
                                )
                            
                            // Circle border
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: cropSize, height: cropSize)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Crop Photo")
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .semibold))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cropImage()
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    private func cropImage() {
        guard let image = image else { return }
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500))
        
        let croppedImage = renderer.image { context in
            // Calculate the crop rect in the original image's coordinate system
            let imageSize = image.size
            let imageAspect = imageSize.width / imageSize.height
            
            // Determine the display size of the image
            var displaySize: CGSize
            if imageAspect > 1 {
                // Landscape
                displaySize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width / imageAspect)
            } else {
                // Portrait or square
                displaySize = CGSize(width: UIScreen.main.bounds.height * imageAspect, height: UIScreen.main.bounds.height)
            }
            
            // Scale factor between display and actual image
            let scaleFactor = imageSize.width / displaySize.width
            
            // Calculate crop area in image coordinates
            let cropDimension = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.8
            let cropSize = cropDimension * scaleFactor / scale
            
            // Calculate position
            let centerX = imageSize.width / 2
            let centerY = imageSize.height / 2
            
            let offsetX = -offset.width * scaleFactor / scale
            let offsetY = -offset.height * scaleFactor / scale
            
            let cropX = centerX + offsetX - (cropSize / 2)
            let cropY = centerY + offsetY - (cropSize / 2)
            
            let cropRect = CGRect(
                x: max(0, min(imageSize.width - cropSize, cropX)),
                y: max(0, min(imageSize.height - cropSize, cropY)),
                width: min(cropSize, imageSize.width),
                height: min(cropSize, imageSize.height)
            )
            
            // Crop and draw
            if let cgImage = image.cgImage?.cropping(to: cropRect) {
                let croppedUIImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
                croppedUIImage.draw(in: CGRect(origin: .zero, size: CGSize(width: 500, height: 500)))
            }
        }
        
        self.croppedImage = croppedImage
    }
}

// MARK: - WebKit Browser View
struct WebBrowserView: View {
    let url: URL
    
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var urlString: String
    
    init(url: URL) {
        self.url = url
        _urlString = State(initialValue: url.absoluteString)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // WEBVIEW
                WebView(
                    url: url,
                    isLoading: $isLoading,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    urlString: $urlString
                )
                
                // BOTTOM BAR
                HStack(spacing: 40) {
                    Button(action: {
                        NotificationCenter.default.post(name: .goBackWebView, object: nil)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(canGoBack ? Color(red: 0.09, green: 0.25, blue: 0.56) : .gray)
                    }
                    .disabled(!canGoBack)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: .goForwardWebView, object: nil)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20))
                            .foregroundColor(canGoForward ? Color(red: 0.09, green: 0.25, blue: 0.56) : .gray)
                    }
                    .disabled(!canGoForward)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.09, green: 0.25, blue: 0.56)))
                    }
                }
                .padding()
                .background(Color.white)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Close Button
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                            .font(.system(size: 18))
                    }
                }
                
                // URL Bar in center
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button(action: {
                            NotificationCenter.default.post(name: .reloadWebView, object: nil)
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                                .font(.system(size: 16, weight: .medium))
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            
                            Text(urlString)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: 220)
                    }
                }
                
                // Open in Safari
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        Image(systemName: "safari")
                            .foregroundColor(Color(red: 0.09, green: 0.25, blue: 0.56))
                            .font(.system(size: 18))
                    }
                }
            }
            .toolbarBackground(.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}


// MARK: - Internal WebView Wrapper
extension Notification.Name {
    static let reloadWebView = Notification.Name("reloadWebView")
    static let goBackWebView = Notification.Name("goBackWebView")
    static let goForwardWebView = Notification.Name("goForwardWebView")
}

struct WebView: UIViewRepresentable {
    let url: URL
    
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var urlString: String
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isUserInteractionEnabled = true
        webView.scrollView.isScrollEnabled = true
        
        // Store the webView reference in the coordinator
        context.coordinator.webView = webView
        
        webView.load(URLRequest(url: url))
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.reload),
            name: .reloadWebView,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.goBack),
            name: .goBackWebView,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.goForward),
            name: .goForwardWebView,
            object: nil
        )
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        weak var webView: WKWebView?
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        @objc func reload() {
            webView?.reload()
        }
        
        @objc func goBack() {
            webView?.goBack()
        }
        
        @objc func goForward() {
            webView?.goForward()
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.urlString = webView.url?.absoluteString ?? parent.url.absoluteString
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Allow all responses
            decisionHandler(.allow)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
// MARK: - Calendar Manager
class CalendarManager {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    func addEventToCalendar(event: Event, completion: @escaping (Bool, String) -> Void) {
        // Request calendar access
        eventStore.requestFullAccessToEvents { granted, error in
            DispatchQueue.main.async {
                guard granted else {
                    completion(false, "Calendar access denied. Please enable in Settings.")
                    return
                }
                
                // Create calendar event
                let calendarEvent = EKEvent(eventStore: self.eventStore)
                calendarEvent.title = event.title
                calendarEvent.location = event.location
                
                // For demo: Set event to tomorrow at the specified time
                // In production, parse event.time properly
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                calendarEvent.startDate = tomorrow
                calendarEvent.endDate = Calendar.current.date(byAdding: .hour, value: 2, to: tomorrow)!
                calendarEvent.isAllDay = event.isAllDay
                calendarEvent.calendar = self.eventStore.defaultCalendarForNewEvents
                
                // Add notes
                calendarEvent.notes = "Event from FBLA App"
                
                // Save event
                do {
                    try self.eventStore.save(calendarEvent, span: .thisEvent)
                    completion(true, "Event successfully added to your calendar!")
                } catch {
                    completion(false, "Failed to save event: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Notification Manager
class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func scheduleEventNotification(for event: Event, minutesBefore: Int, completion: @escaping (Bool) -> Void) {
        // Parse the event time and create notification
        let content = UNMutableNotificationContent()
        content.title = "Event Reminder"
        content.body = "\(event.title) is starting in \(formatTime(minutesBefore)) at \(event.location)"
        content.sound = .default
        
        // For demo purposes, schedule notification after a few seconds
        // In production, you'd calculate the actual event time from event.time
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutesBefore * 60), repeats: false)
        
        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
    
    func cancelNotification(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [event.id.uuidString])
    }
    
    private func formatTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        } else if minutes < 1440 {
            let hours = minutes / 60
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        } else {
            let days = minutes / 1440
            return "\(days) day\(days > 1 ? "s" : "")"
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
