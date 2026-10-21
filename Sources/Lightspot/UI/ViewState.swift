import SwiftUI

/// SwiftUI's `State` property wrapper, under a name no macro claims. Write `@ViewState`
/// where SwiftUI code would write `@State`.
///
/// From the macOS 27 SDK, SwiftUICore declares `State` twice: the property wrapper, and
/// an attached macro that `@State` resolves to. The macro's implementation
/// (`SwiftUIMacros`) ships with Xcode only, so with just the Command Line Tools every
/// `@State` fails with "plugin for module 'SwiftUIMacros' not found". `@SwiftUI.State`
/// still finds the macro, and a module-level `typealias State` does not shadow it (both
/// tried); a different name does. `State(initialValue:)` in an initializer is a type,
/// not an attribute, and needs no change.
typealias ViewState = SwiftUI.State
