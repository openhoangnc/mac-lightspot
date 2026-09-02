import AppKit

final class SettingsProvider: Sendable {
    static let shared = SettingsProvider()

    let items: [SettingsItem]

    private init() {
        self.items = [
            SettingsItem(
                name: "Wi-Fi",
                keywords: ["wifi", "wi-fi", "wireless", "internet", "network", "wlan", "ssid", "hotspot", "airport", "ip address"],
                sfSymbol: "wifi",
                deepLink: "x-apple.systempreferences:com.apple.wifi-settings-extension",
                subtitle: "System Settings → Wi-Fi"
            ),
            SettingsItem(
                name: "Bluetooth",
                keywords: ["bluetooth", "bt", "wireless", "airpods", "headphones", "devices", "pair", "connect", "magic mouse", "magic keyboard"],
                sfSymbol: "antenna.radiowaves.left.and.right",
                deepLink: "x-apple.systempreferences:com.apple.BluetoothSettings",
                subtitle: "System Settings → Bluetooth"
            ),
            SettingsItem(
                name: "Network",
                keywords: ["network", "ethernet", "vpn", "dns", "tcp/ip", "proxy", "firewall", "ip", "lan", "connection"],
                sfSymbol: "network",
                deepLink: "x-apple.systempreferences:com.apple.Network-Settings.extension",
                subtitle: "System Settings → Network"
            ),
            SettingsItem(
                name: "Notifications",
                keywords: ["notifications", "alerts", "badges", "banners", "sounds", "dnd", "do not disturb"],
                sfSymbol: "bell.badge",
                deepLink: "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                subtitle: "System Settings → Notifications"
            ),
            SettingsItem(
                name: "Sound",
                keywords: ["sound", "audio", "volume", "output", "input", "microphone", "speaker", "alert", "mute"],
                sfSymbol: "speaker.wave.2",
                deepLink: "x-apple.systempreferences:com.apple.Sound-Settings.extension",
                subtitle: "System Settings → Sound"
            ),
            SettingsItem(
                name: "Focus",
                keywords: ["focus", "do not disturb", "dnd", "sleep", "work", "personal", "modes", "notifications", "quiet"],
                sfSymbol: "moon.fill",
                deepLink: "x-apple.systempreferences:com.apple.Focus-Settings.extension",
                subtitle: "System Settings → Focus"
            ),
            SettingsItem(
                name: "Screen Time",
                keywords: ["screen time", "downtime", "app limits", "limits", "restrictions", "parental controls", "usage", "family"],
                sfSymbol: "hourglass",
                deepLink: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension",
                subtitle: "System Settings → Screen Time"
            ),
            SettingsItem(
                name: "General",
                keywords: ["general", "about", "info", "system", "airdrop", "language", "region"],
                sfSymbol: "gearshape",
                deepLink: "x-apple.systempreferences:com.apple.General-Settings.extension",
                subtitle: "System Settings → General"
            ),
            SettingsItem(
                name: "Appearance",
                keywords: ["appearance", "dark mode", "light mode", "theme", "accent color", "highlight color", "auto", "colors"],
                sfSymbol: "circle.lefthalf.filled",
                deepLink: "x-apple.systempreferences:com.apple.Appearance-Settings.extension",
                subtitle: "System Settings → Appearance"
            ),
            SettingsItem(
                name: "Accessibility",
                keywords: ["accessibility", "vision", "hearing", "voiceover", "zoom", "captions", "subtitles", "spoken content", "contrast", "motor"],
                sfSymbol: "figure.walk.circle",
                deepLink: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
                subtitle: "System Settings → Accessibility"
            ),
            SettingsItem(
                name: "Control Center",
                keywords: ["control center", "menu bar", "status bar", "shortcuts", "modules", "clock", "battery percent"],
                sfSymbol: "switch.2",
                deepLink: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
                subtitle: "System Settings → Control Center"
            ),
            SettingsItem(
                name: "Siri",
                keywords: ["siri", "voice", "assistant", "hey siri", "dictation", "talk", "ai", "apple intelligence"],
                sfSymbol: "waveform",
                deepLink: "x-apple.systempreferences:com.apple.Siri-Settings.extension",
                subtitle: "System Settings → Siri"
            ),
            SettingsItem(
                name: "Spotlight",
                keywords: ["spotlight", "search", "indexing", "shortcuts", "privacy", "query"],
                sfSymbol: "magnifyingglass",
                deepLink: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension",
                subtitle: "System Settings → Spotlight"
            ),
            SettingsItem(
                name: "Privacy & Security",
                keywords: ["privacy", "security", "location", "camera", "microphone", "gatekeeper", "filevault", "firewall", "permissions", "analytics"],
                sfSymbol: "hand.raised",
                deepLink: "x-apple.systempreferences:com.apple.Privacy-Settings.extension",
                subtitle: "System Settings → Privacy & Security"
            ),
            SettingsItem(
                name: "Desktop & Dock",
                keywords: ["desktop", "dock", "stage manager", "mission control", "hot corners", "spaces", "widgets", "menu bar"],
                sfSymbol: "menubar.dock.rectangle",
                deepLink: "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
                subtitle: "System Settings → Desktop & Dock"
            ),
            SettingsItem(
                name: "Displays",
                keywords: ["displays", "monitors", "screen", "resolution", "brightness", "true tone", "night shift", "refresh rate", "scaling", "color profile", "arrangement"],
                sfSymbol: "display",
                deepLink: "x-apple.systempreferences:com.apple.Displays-Settings.extension",
                subtitle: "System Settings → Displays"
            ),
            SettingsItem(
                name: "Wallpaper",
                keywords: ["wallpaper", "background", "desktop picture", "photos", "screensaver", "dynamic"],
                sfSymbol: "photo",
                deepLink: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
                subtitle: "System Settings → Wallpaper"
            ),
            SettingsItem(
                name: "Screen Saver",
                keywords: ["screen saver", "screensaver", "aerial", "drift", "hello", "lock screen", "display sleep"],
                sfSymbol: "sparkles",
                deepLink: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
                subtitle: "System Settings → Screen Saver"
            ),
            SettingsItem(
                name: "Battery",
                keywords: ["battery", "power", "energy", "low power mode", "charging", "health", "adapter", "usage"],
                sfSymbol: "battery.100",
                deepLink: "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                subtitle: "System Settings → Battery"
            ),
            SettingsItem(
                name: "Lock Screen",
                keywords: ["lock screen", "sleep", "screen off", "password required", "message", "inactive", "display turn off"],
                sfSymbol: "lock",
                deepLink: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension",
                subtitle: "System Settings → Lock Screen"
            ),
            SettingsItem(
                name: "Touch ID",
                keywords: ["touch id", "touchid", "fingerprint", "password", "unlock", "apple watch unlock", "security", "biometrics"],
                sfSymbol: "touchid",
                deepLink: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension",
                subtitle: "System Settings → Touch ID"
            ),
            SettingsItem(
                name: "Users & Groups",
                keywords: ["users", "groups", "accounts", "admin", "guest user", "login items", "switch user", "profile picture"],
                sfSymbol: "person.2",
                deepLink: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension",
                subtitle: "System Settings → Users & Groups"
            ),
            SettingsItem(
                name: "Passwords",
                keywords: ["passwords", "keychain", "credentials", "login", "autofill", "2fa", "security codes", "passkeys"],
                sfSymbol: "key",
                deepLink: "x-apple.systempreferences:com.apple.Passwords-Settings.extension",
                subtitle: "System Settings → Passwords"
            ),
            SettingsItem(
                name: "Internet Accounts",
                keywords: ["internet accounts", "icloud", "google", "mail", "contacts", "calendar", "exchange", "yahoo", "imap"],
                sfSymbol: "at",
                deepLink: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
                subtitle: "System Settings → Internet Accounts"
            ),
            SettingsItem(
                name: "Keyboard",
                keywords: ["keyboard", "typing", "shortcuts", "text replacement", "input sources", "dictation", "fn key", "backlight"],
                sfSymbol: "keyboard",
                deepLink: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
                subtitle: "System Settings → Keyboard"
            ),
            SettingsItem(
                name: "Trackpad",
                keywords: ["trackpad", "touchpad", "gestures", "tap to click", "scroll", "force click", "pointer speed", "natural scrolling"],
                sfSymbol: "hand.point.up.left",
                deepLink: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension",
                subtitle: "System Settings → Trackpad"
            ),
            SettingsItem(
                name: "Mouse",
                keywords: ["mouse", "magic mouse", "tracking speed", "scrolling speed", "secondary click", "cursor", "pointer"],
                sfSymbol: "computermouse",
                deepLink: "x-apple.systempreferences:com.apple.Mouse-Settings.extension",
                subtitle: "System Settings → Mouse"
            ),
            SettingsItem(
                name: "Printers & Scanners",
                keywords: ["printers", "scanners", "print", "scan", "fax", "airprint", "documents", "cups", "printer"],
                sfSymbol: "printer",
                deepLink: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension",
                subtitle: "System Settings → Printers & Scanners"
            ),
            SettingsItem(
                name: "Software Update",
                keywords: ["software update", "macos update", "system update", "upgrade", "firmware", "os update", "version"],
                sfSymbol: "arrow.triangle.2.circlepath",
                deepLink: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
                subtitle: "System Settings → Software Update"
            ),
            SettingsItem(
                name: "Storage",
                keywords: ["storage", "disk", "hard drive", "ssd", "free space", "manage storage", "clean up", "capacity"],
                sfSymbol: "internaldrive",
                deepLink: "x-apple.systempreferences:com.apple.settings.Storage",
                subtitle: "System Settings → Storage"
            ),
            SettingsItem(
                name: "Date & Time",
                keywords: ["date", "time", "clock", "timezone", "time zone", "24-hour", "automatic time", "calendar"],
                sfSymbol: "clock",
                deepLink: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
                subtitle: "System Settings → Date & Time"
            ),
            SettingsItem(
                name: "Sharing",
                keywords: ["sharing", "file sharing", "screen sharing", "remote login", "airdrop", "remote management", "bluetooth sharing"],
                sfSymbol: "square.and.arrow.up",
                deepLink: "x-apple.systempreferences:com.apple.Sharing-Settings.extension",
                subtitle: "System Settings → Sharing"
            ),
            SettingsItem(
                name: "Time Machine",
                keywords: ["time machine", "backup", "restore", "external drive", "snapshots", "history"],
                sfSymbol: "clock.arrow.circlepath",
                deepLink: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension",
                subtitle: "System Settings → Time Machine"
            ),
            SettingsItem(
                name: "Startup Disk",
                keywords: ["startup disk", "boot", "boot drive", "restart", "target disk mode", "macos volume"],
                sfSymbol: "externaldrive",
                deepLink: "x-apple.systempreferences:com.apple.Startup-Disk-Settings.extension",
                subtitle: "System Settings → Startup Disk"
            ),
            SettingsItem(
                name: "Transfer or Reset",
                keywords: ["transfer", "reset", "erase all content", "factory reset", "migration assistant", "restore"],
                sfSymbol: "arrow.counterclockwise",
                deepLink: "x-apple.systempreferences:com.apple.Transfer-Reset-Settings.extension",
                subtitle: "System Settings → Transfer or Reset"
            )
        ]
    }

    /// Search settings items with fuzzy matching against name and keywords
    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        var results: [SearchResult] = []

        for item in items {
            var highestScore: Double?

            // Match against item name (zero allocation using SearchQuery)
            if let nameScore = FuzzyMatcher.score(query: query, targetLower: item.lowercaseName, targetTokens: [], targetInitials: nil) {
                highestScore = nameScore
            }

            // Match against keywords
            for keyword in item.lowercaseKeywords {
                if let kwScore = FuzzyMatcher.score(query: query, targetLower: keyword, targetTokens: [], targetInitials: nil) {
                    let adjustedScore = kwScore * 0.95
                    if let current = highestScore {
                        highestScore = max(current, adjustedScore)
                    } else {
                        highestScore = adjustedScore
                    }
                }
            }

            guard let score = highestScore else { continue }

            let result = SearchResult(
                id: item.id,
                title: item.name,
                subtitle: item.subtitle,
                iconType: .systemSymbol(name: item.sfSymbol),
                category: .systemSettings,
                score: score,
                action: .openSettings(deepLink: item.deepLink)
            )
            results.append(result)
        }

        return results.sorted { $0.score > $1.score }
    }
}
