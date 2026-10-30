import Foundation

// MARK: - Mac Tweaks: the Settings catalog
//
// Every tweak the Settings section offers, as data: its group, what it changes, the processes
// that read it only at launch, its presets and the first macOS that has it. Ported from
// RemoveMacAI's Tweaks.swift (MIT), with Lightspot's changes: the `.DS_Store` tweak covers USB
// drives too, as Lightspot's quick action does; the Dock-removal tweak is one list; the
// long-standing Finder, Dock, save-dialog, screenshot and typing keys go back to macOS 13
// (RemoveMacAI's floor is 14.0, its own minimum); every row has its own symbol. IDs are
// permanent: the profile's marker and the undo journal record them.

enum MacTweaksSettings {
    /// A header in the section, in display order.
    enum Group: String, CaseIterable, Sendable {
        case privacy, annoyances, apps, finder, windows, typing

        var title: String {
            switch self {
            case .privacy: return "Privacy"
            case .annoyances: return "Annoyances"
            case .apps: return "Apple apps"
            case .finder: return "Finder"
            case .windows: return "Dock and windows"
            case .typing: return "Typing"
            }
        }
    }

    /// A named starting selection: its row ticks its tweaks. Maximum privacy adds to Recommended.
    enum Preset: String, CaseIterable, Sendable {
        case recommended
        case maximumPrivacy = "maximum-privacy"

        var id: String { "preset-" + rawValue }

        var title: String {
            switch self {
            case .recommended: return "Recommended"
            case .maximumPrivacy: return "Maximum privacy"
            }
        }

        var detail: String {
            switch self {
            case .recommended:
                return "No analytics or ads, fewer pop-ups, and Finder and the Dock set up the way most people want. Nothing you rely on stops working. Apple Intelligence has its own section."
            case .maximumPrivacy:
                return "Everything in Recommended, plus Game Center and Safari's search suggestions off."
            }
        }

        var symbol: String {
            switch self {
            case .recommended: return "star"
            case .maximumPrivacy: return "lock.shield"
            }
        }
    }

    /// One setting a tweak changes.
    enum Change: Sendable, Equatable {
        /// A restriction the profile sets to false (`com.apple.applicationaccess`).
        case restriction(String)
        /// A preference the profile forces, so it can't be changed back by hand.
        case forced(domain: String, key: String, value: PreferenceValue)
        /// This user's own preference, written through cfprefsd.
        case pref(domain: String, key: String, value: PreferenceValue)
        /// A launchd job in this user's session: disabled, then booted out.
        case service(String)
        /// Music's application job, whose label holds the inodes of Music.app and its executable.
        case musicLaunches
        /// Dock tiles, by bundle identifier.
        case dockRemove([String])
        /// `~/Library`'s hidden flag cleared.
        case showLibrary

        var inProfile: Bool {
            switch self {
            case .restriction, .forced: return true
            default: return false
            }
        }

        /// The key its journal entry (or, for Music, entries) goes under; no two tweaks change the
        /// same one.
        var key: String {
            switch self {
            case .restriction(let key): return "restriction:\(key)"
            case .forced(let domain, let key, _): return "forced:\(domain):\(key)"
            case .pref(let domain, let key, _): return "pref:\(domain):\(key)"
            case .service(let label): return "service:\(label)"
            case .musicLaunches: return "application:com.apple.Music"
            case .dockRemove(let ids): return "dock:" + ids.joined(separator: ",")
            case .showLibrary: return "library"
            }
        }
    }

    struct Tweak: Sendable {
        let id: String
        let group: Group
        let symbol: String
        let title: String
        /// Lightspot's voice: what it does, what comes back, what stops working (rule 6).
        let detail: String
        var caveat: String? = nil
        let changes: [Change]
        /// Processes that read the setting only at launch, restarted once per apply.
        var restart: [String] = []
        var presets: Set<Preset> = []
        /// The first macOS (major, minor) that has the setting.
        var since: (Int, Int) = (14, 0)

        var inProfile: Bool { changes.contains { $0.inProfile } }
        func isSupported(on os: (Int, Int)) -> Bool { os >= since }
    }

    static let restriction = "com.apple.applicationaccess"
    static let global = "NSGlobalDomain"
    static let finder = "com.apple.finder"
    static let dock = "com.apple.dock"
    static let windowManager = "com.apple.WindowManager"
    static let rcdLabel = "com.apple.rcd"
    /// The bundle IDs the Dock-removal tweak takes out.
    static let unusedDockApps = [
        "com.apple.news", "com.apple.TV", "com.apple.Music", "com.apple.podcasts", "com.apple.iBooksX",
        "com.apple.freeform", "com.apple.GenerativePlaygroundApp", "com.apple.journal", "com.apple.Maps", "com.apple.stocks",
    ]

    /// The tweaks, in display order.
    static let catalog: [Tweak] = [
        // MARK: Privacy
        Tweak(id: "analytics", group: .privacy, symbol: "chart.bar", title: "Turn off Mac Analytics",
              detail: "Stops your Mac sending diagnostic and usage data to Apple and to app developers.",
              changes: [.restriction("allowDiagnosticSubmission")], presets: [.recommended]),
        Tweak(id: "personalized-ads", group: .privacy, symbol: "megaphone", title: "Turn off personalized ads",
              detail: "Stops Apple using what you do in its apps to target ads in the App Store, News and Stocks.",
              changes: [.restriction("allowApplePersonalizedAdvertising")], presets: [.recommended]),
        Tweak(id: "improve-siri", group: .privacy, symbol: "mic.slash", title: "Turn off Improve Siri and Dictation",
              detail: "Stops Apple storing and reviewing recordings of your Siri and dictation requests.",
              changes: [.forced(domain: "com.apple.assistant.support", key: "Siri Data Sharing Opt-In Status", value: .int(2))],
              presets: [.recommended]),
        Tweak(id: "improve-search", group: .privacy, symbol: "magnifyingglass", title: "Turn off Improve Search",
              detail: "Stops Apple keeping your Spotlight, Safari and Look Up searches to improve search.",
              changes: [.forced(domain: "com.apple.assistant.support", key: "Search Queries Data Sharing Status", value: .int(2))],
              presets: [.recommended]),
        Tweak(id: "spotlight-web", group: .privacy, symbol: "globe", title: "Turn off Spotlight internet results",
              detail: "Keeps Spotlight searches on your Mac instead of sending them to Apple for web suggestions.",
              changes: [.restriction("allowSpotlightInternetResults")], presets: [.recommended]),
        Tweak(id: "lookup-suggestions", group: .privacy, symbol: "text.book.closed", title: "Turn off Look Up suggestions",
              detail: "Stops Look Up sending the words you select to Apple for web results.",
              changes: [.forced(domain: "com.apple.lookup.shared", key: "LookupSuggestionsDisabled", value: .bool(true))],
              presets: [.recommended]),
        Tweak(id: "safari-suggestions", group: .privacy, symbol: "safari", title: "Turn off Safari search suggestions",
              detail: "Stops Safari sending what you type in the address bar to your search engine and to Apple.",
              caveat: "The address bar no longer suggests searches as you type.",
              changes: [
                  .forced(domain: "com.apple.Safari", key: "UniversalSearchEnabled", value: .bool(false)),
                  .forced(domain: "com.apple.Safari", key: "SuppressSearchSuggestions", value: .bool(true)),
              ], presets: [.maximumPrivacy]),
        Tweak(id: "game-center", group: .privacy, symbol: "gamecontroller", title: "Turn off Game Center",
              detail: "Turns Game Center off, with its sign-in prompts, friend requests and notifications.",
              caveat: "Games that need Game Center to save progress or play online lose that.",
              changes: [.restriction("allowGameCenter")], presets: [.maximumPrivacy]),

        // MARK: Annoyances
        Tweak(id: "click-to-desktop", group: .annoyances, symbol: "cursorarrow.click", title: "Stop clicks on the wallpaper hiding windows",
              detail: "Stops every window sliding away when you click the wallpaper by mistake.",
              changes: [.pref(domain: windowManager, key: "EnableStandardClickToShowDesktop", value: .bool(false))],
              presets: [.recommended]),
        Tweak(id: "desktop-widgets", group: .annoyances, symbol: "rectangle.grid.2x2", title: "Hide desktop widgets",
              detail: "Hides widgets on the desktop, including in Stage Manager.",
              changes: [
                  .pref(domain: windowManager, key: "StandardHideWidgets", value: .bool(true)),
                  .pref(domain: windowManager, key: "StageManagerHideWidgets", value: .bool(true)),
              ]),
        Tweak(id: "music-launches", group: .annoyances, symbol: "music.note", title: "Stop Music from opening, even by hand",
              detail: "Switches off the entry macOS uses to start Music, so an AirPods press or the play key can't open it. Nothing is installed.",
              caveat: "Music won't open at all, not even when you click it, until you undo this. After a macOS update replaces Music, it can open again: tick it again.",
              changes: [.musicLaunches]),
        Tweak(id: "media-keys", group: .annoyances, symbol: "playpause", title: "Turn off the play, pause and skip keys",
              detail: "Turns off the service behind the media keys, so the play key can't open Music.",
              caveat: "The keys stop working in every app, including VLC and Spotify. To keep them and only stop Music opening, use Stop Music from opening instead.",
              changes: [.service(rcdLabel)]),
        Tweak(id: "iphone-mirroring", group: .annoyances, symbol: "iphone.slash", title: "Turn off iPhone Mirroring",
              detail: "Turns iPhone Mirroring off, so the app and its prompts go away.",
              changes: [.restriction("allowiPhoneMirroring")], since: (15, 0)),

        // MARK: Apple apps
        Tweak(id: "music-classic", group: .apps, symbol: "music.note.list", title: "Turn off Apple Music in the Music app",
              detail: "Turns the Music app back into a plain player for your own library, without the store and subscription prompts.",
              caveat: "Apple Music subscribers lose streaming.",
              changes: [.restriction("allowMusicService")]),
        Tweak(id: "book-store", group: .apps, symbol: "books.vertical", title: "Turn off the Book Store",
              detail: "Removes the store from the Books app and keeps your own books.",
              changes: [.restriction("allowBookstore")], since: (15, 0)),
        Tweak(id: "dock-apple-apps", group: .apps, symbol: "dock.arrow.down.rectangle", title: "Remove unused Apple apps from the Dock",
              detail: "Removes News, TV, Music, Podcasts, Books, Freeform, Image Playground, Journal, Maps and Stocks from the Dock. The apps stay installed.",
              changes: [.dockRemove(unusedDockApps)], restart: ["Dock"]),

        // MARK: Finder
        Tweak(id: "file-extensions", group: .finder, symbol: "doc.text.magnifyingglass", title: "Show file extensions",
              detail: "Shows the full name of every file, so a file pretending to be a document is easier to spot.",
              changes: [.pref(domain: global, key: "AppleShowAllExtensions", value: .bool(true))], restart: ["Finder"],
              presets: [.recommended], since: (13, 0)),
        Tweak(id: "hidden-files", group: .finder, symbol: "eye", title: "Show hidden files",
              detail: "Shows the files macOS hides, such as .gitignore and .zshrc. Press Command-Shift-Period to toggle it too.",
              changes: [.pref(domain: finder, key: "AppleShowAllFiles", value: .bool(true))], restart: ["Finder"], since: (13, 0)),
        Tweak(id: "path-bar", group: .finder, symbol: "folder.badge.gearshape", title: "Show the path bar",
              detail: "Shows where the current folder is at the bottom of every Finder window.",
              changes: [.pref(domain: finder, key: "ShowPathbar", value: .bool(true))], restart: ["Finder"],
              presets: [.recommended], since: (13, 0)),
        Tweak(id: "status-bar", group: .finder, symbol: "rectangle.bottomthird.inset.filled", title: "Show the status bar",
              detail: "Shows the number of items and the free space at the bottom of Finder windows.",
              changes: [.pref(domain: finder, key: "ShowStatusBar", value: .bool(true))], restart: ["Finder"], since: (13, 0)),
        Tweak(id: "folders-first", group: .finder, symbol: "folder.fill", title: "Keep folders above files",
              detail: "Keeps folders above files when sorting by name.",
              changes: [.pref(domain: finder, key: "_FXSortFoldersFirst", value: .bool(true))], restart: ["Finder"],
              presets: [.recommended], since: (13, 0)),
        Tweak(id: "search-this-folder", group: .finder, symbol: "magnifyingglass.circle", title: "Search the current folder",
              detail: "Makes Finder search the folder you're in, not the whole Mac.",
              changes: [.pref(domain: finder, key: "FXDefaultSearchScope", value: .string("SCcf"))], restart: ["Finder"], since: (13, 0)),
        Tweak(id: "extension-warning", group: .finder, symbol: "exclamationmark.triangle", title: "Skip the extension change warning",
              detail: "Stops Finder asking for confirmation each time you change a file's extension.",
              changes: [.pref(domain: finder, key: "FXEnableExtensionChangeWarning", value: .bool(false))], restart: ["Finder"], since: (13, 0)),
        Tweak(id: "path-in-title", group: .finder, symbol: "text.alignleft", title: "Show the full path in the title bar",
              detail: "Shows the full folder path at the top of Finder windows.",
              changes: [.pref(domain: finder, key: "_FXShowPosixPathInTitle", value: .bool(true))], restart: ["Finder"], since: (13, 0)),
        Tweak(id: "ds-store", group: .finder, symbol: "externaldrive.badge.xmark", title: "Stop .DS_Store files on network and USB drives",
              detail: "Stops Finder leaving .DS_Store files in shared folders and on USB drives.",
              caveat: "Finder stops remembering window layouts in folders on those drives.",
              changes: [
                  .pref(domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", value: .bool(true)),
                  .pref(domain: "com.apple.desktopservices", key: "DSDontWriteUSBStores", value: .bool(true)),
              ], restart: ["Finder"], presets: [.recommended], since: (13, 0)),
        Tweak(id: "trash-30-days", group: .finder, symbol: "trash", title: "Empty the Trash after 30 days",
              detail: "Deletes items that have been in the Trash for 30 days, so it stops filling the disk.",
              changes: [.pref(domain: finder, key: "FXRemoveOldTrashItems", value: .bool(true))], restart: ["Finder"], since: (13, 0)),
        Tweak(id: "save-locally", group: .finder, symbol: "internaldrive", title: "Save new documents on this Mac",
              detail: "Makes Save dialogs start on your Mac instead of iCloud Drive.",
              changes: [.pref(domain: global, key: "NSDocumentSaveNewDocumentsToCloud", value: .bool(false))], since: (13, 0)),
        Tweak(id: "expanded-save", group: .finder, symbol: "arrow.up.left.and.arrow.down.right", title: "Expand Save dialogs",
              detail: "Opens Save dialogs with the full folder browser instead of the small version.",
              changes: [.pref(domain: global, key: "NSNavPanelExpandedStateForSaveMode", value: .bool(true))], since: (13, 0)),
        Tweak(id: "show-library", group: .finder, symbol: "building.columns", title: "Show the Library folder",
              detail: "Shows the hidden Library folder in your home folder.",
              changes: [.showLibrary]),

        // MARK: Dock and windows
        Tweak(id: "dock-recents", group: .windows, symbol: "clock.arrow.circlepath", title: "Hide recent apps in the Dock",
              detail: "Stops the Dock adding apps you opened recently.",
              changes: [.pref(domain: dock, key: "show-recents", value: .bool(false))], restart: ["Dock"],
              presets: [.recommended], since: (13, 0)),
        Tweak(id: "dock-delay", group: .windows, symbol: "hare", title: "Remove the Dock auto-hide delay",
              detail: "Shows a hidden Dock straight away instead of after half a second.",
              changes: [.pref(domain: dock, key: "autohide-delay", value: .double(0))], restart: ["Dock"], since: (13, 0)),
        Tweak(id: "dock-bounce", group: .windows, symbol: "arrow.up.arrow.down", title: "Stop Dock icons bouncing",
              detail: "Stops Dock icons bouncing while apps open.",
              changes: [.pref(domain: dock, key: "launchanim", value: .bool(false))], restart: ["Dock"], since: (13, 0)),
        Tweak(id: "minimize-to-app", group: .windows, symbol: "rectangle.compress.vertical", title: "Minimize windows into their app icon",
              detail: "Keeps minimized windows inside their app's icon instead of filling the Dock.",
              changes: [.pref(domain: dock, key: "minimize-to-application", value: .bool(true))], restart: ["Dock"], since: (13, 0)),
        Tweak(id: "window-animations", group: .windows, symbol: "macwindow", title: "Turn off window opening animations",
              detail: "Opens new windows instantly instead of zooming them in.",
              changes: [.pref(domain: global, key: "NSAutomaticWindowAnimationsEnabled", value: .bool(false))], since: (13, 0)),
        Tweak(id: "tile-margins", group: .windows, symbol: "rectangle.split.2x1", title: "Remove gaps between tiled windows",
              detail: "Removes the margins around windows you tile to the sides of the screen.",
              changes: [.pref(domain: windowManager, key: "EnableTiledWindowMargins", value: .bool(false))], since: (15, 0)),
        Tweak(id: "screenshot-shadow", group: .windows, symbol: "camera.on.rectangle", title: "Remove shadows from window screenshots",
              detail: "Takes window screenshots without the large drop shadow around them.",
              changes: [.pref(domain: "com.apple.screencapture", key: "disable-shadow", value: .bool(true))], restart: ["SystemUIServer"],
              since: (13, 0)),

        // MARK: Typing
        Tweak(id: "autocorrect", group: .typing, symbol: "textformat.abc", title: "Turn off autocorrect",
              detail: "Stops macOS correcting words as you type.",
              changes: [.pref(domain: global, key: "NSAutomaticSpellingCorrectionEnabled", value: .bool(false))], since: (13, 0)),
        Tweak(id: "smart-punctuation", group: .typing, symbol: "quote.opening", title: "Turn off smart quotes and dashes",
              detail: "Keeps straight quotes and double hyphens as you typed them, which code and terminals need.",
              changes: [
                  .pref(domain: global, key: "NSAutomaticQuoteSubstitutionEnabled", value: .bool(false)),
                  .pref(domain: global, key: "NSAutomaticDashSubstitutionEnabled", value: .bool(false)),
              ], since: (13, 0)),
        Tweak(id: "double-space-period", group: .typing, symbol: "space", title: "Turn off period on double space",
              detail: "Stops two spaces turning into a period.",
              changes: [.pref(domain: global, key: "NSAutomaticPeriodSubstitutionEnabled", value: .bool(false))], since: (13, 0)),
        Tweak(id: "auto-capitalize", group: .typing, symbol: "textformat.size", title: "Turn off automatic capitals",
              detail: "Stops macOS capitalizing the first word of each sentence.",
              changes: [.pref(domain: global, key: "NSAutomaticCapitalizationEnabled", value: .bool(false))], since: (13, 0)),
        Tweak(id: "key-repeat", group: .typing, symbol: "keyboard", title: "Repeat held keys instead of showing accents",
              detail: "Repeats a key while you hold it, instead of opening the accent menu.",
              caveat: "Type accents with Option shortcuts or the Character Viewer instead.",
              changes: [.pref(domain: global, key: "ApplePressAndHoldEnabled", value: .bool(false))], since: (13, 0)),
    ]

    static func tweak(_ id: String) -> Tweak? { catalog.first { $0.id == id } }

    /// A preset's tweaks; Maximum privacy builds on Recommended.
    static func tweaks(in preset: Preset) -> [Tweak] {
        let names: Set<Preset> = preset == .maximumPrivacy ? [.recommended, .maximumPrivacy] : [preset]
        return catalog.filter { !$0.presets.isDisjoint(with: names) }
    }

    /// The profile-backed tweaks among `ids` that this version knows, in catalog order: the ones a
    /// profile can be built with, and the only ones a profile target may name (otherwise its
    /// marker could never match).
    static func profileTweaks(_ ids: Set<String>) -> [Tweak] {
        catalog.filter { $0.inProfile && ids.contains($0.id) }
    }

    static func profileTweakIDs(_ ids: Set<String>) -> Set<String> { Set(profileTweaks(ids).map(\.id)) }

    /// The profile tweaks Lightspot's installed profile holds and this version can rebuild.
    static func heldTweaks(_ installed: MacTweaksProfile.Installed) -> Set<String> {
        installed.on ? profileTweakIDs(installed.tweaks) : []
    }

    /// The order processes restart in, each once.
    static let restartOrder = ["Finder", "Dock", "SystemUIServer"]

    /// A word for a shell command shown in the plan: as it is when it needs no quoting.
    static func shellWord(_ text: String) -> String {
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/:@%+=,-"))
        return !text.isEmpty && text.unicodeScalars.allSatisfy(plain.contains) ? text : MacTweaksStorage.shellQuote(text)
    }
}
