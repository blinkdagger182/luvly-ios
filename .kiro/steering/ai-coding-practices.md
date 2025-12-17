# AI Coding Practices - LockInNote Project
## Scope: Always included for all code development

---

### 🎯 Project Context

**LockInNote** is a multi-platform Swift/SwiftUI memo widget app supporting:
- iOS, iPadOS, visionOS (shared codebase)
- macOS (separate implementation)
- watchOS (separate implementation)
- WidgetKit extensions for all platforms

**Core Architecture:**
- SwiftUI declarative UI
- ObservableObject pattern for state management
- iCloud sync via NSUbiquitousKeyValueStore
- WidgetKit for home screen/lock screen widgets
- Emoji prefixes for file organization (📝, 🎚️, 💾, etc.)

---

### 📁 Project Structure (MUST FOLLOW)

```
LockInNote/
├── Shared/                          # Cross-platform shared code
│   ├── 🌐Localization/             # Localized strings
│   ├── 🎚️Customize/               # Customization enums/types
│   ├── 💾ICloud.swift              # iCloud storage layer
│   ├── 📝NoteModel.swift           # Core note data model
│   ├── 📝NoteProperty.swift        # Property definitions
│   ├── 📝NoteFamily.swift          # Note family types
│   ├── 🗄️Rest/                    # Supporting utilities
│   ├── 🧰SupportingFiles/          # Assets, entitlements
│   └── 🪧WidgetView/               # Shared widget views
│
├── iOS, visionOS/                   # iOS/visionOS specific
│   ├── App.swift                   # App entry point
│   ├── ContentView.swift           # Main view
│   ├── 📱AppModel.swift            # App state model
│   ├── 📝NoteTab.swift             # Note editing tab
│   ├── 🔖Tab.swift                 # Tab definitions
│   ├── 👆Buttons.swift             # Button components
│   ├── 💬Sheet.swift               # Sheet presentations
│   ├── 🎚️CustomizeMenu/           # Customization UI
│   ├── 🔗URLSchemeActionMenu.swift # URL scheme handling
│   ├── 🛠️OptionTab.swift          # Settings tab
│   ├── 🗄️Rest/                    # Platform utilities
│   └── 🧰SupportingFiles/          # Platform assets
│
├── macOS/                           # macOS specific
│   ├── App.swift                   # App entry point
│   ├── ContentView.swift           # Main view
│   ├── 📱AppModel.swift            # App delegate model
│   ├── 📝NoteWindow.swift          # Note window scene
│   ├── 📝NoteEditor.swift          # Note editor view
│   ├── 🎚️CustomizeWindow.swift    # Customization window
│   ├── 🎚️CustomizeMenu.swift      # Customization menu
│   ├── 🪄Commands.swift            # Menu bar commands
│   ├── 🗄️Rest/                    # Platform utilities
│   └── 🧰SupportingFiles/          # Platform assets
│
├── watchOS/                         # watchOS specific
│   ├── App.swift                   # App entry point
│   ├── ContentView.swift           # Main view
│   ├── 📱AppModel.swift            # App state model
│   ├── 📝NoteTab.swift             # Note tab
│   ├── 🔖Tab.swift                 # Tab definitions
│   ├── 📖NoteDetailView.swift      # Detail view
│   ├── 💬Sheet.swift               # Sheet presentations
│   ├── 🎚️CustomizeMenu.swift      # Customization menu
│   ├── ℹ️AboutApp.swift           # About view
│   ├── ℹ️InfoTab.swift            # Info tab
│   └── 🧰SupportingFiles/          # Platform assets
│
└── Widget/                          # WidgetKit extensions
    ├── Widget.swift                # Widget entry point
    ├── WidgetBundle.swift          # Widget bundle
    ├── iOS, visionOS/              # iOS widget views
    ├── macOS/                      # macOS widget views
    └── watchOS/                    # watchOS complications
```

---

### 🔧 Swift/SwiftUI Coding Standards

#### Naming Conventions
- **Emoji prefixes**: Maintain existing emoji naming (📝 for notes, 🎚️ for customization, 💾 for storage, etc.)
- **Hungarian notation with emoji**: `ⓝoteFamily`, `ⓟroperty`, `ⓥalue`, `ⓒhangedKeys`
- **Clear descriptive names**: No abbreviations like `mgr`, `util`, `tmp`
- **Type names**: PascalCase with emoji prefix (e.g., `📝NoteModel`)
- **Properties/methods**: camelCase with emoji prefix where appropriate

#### Architecture Patterns
- **ObservableObject**: Use `@Published` for reactive state
- **@StateObject**: For owned model instances
- **@EnvironmentObject**: For shared app-wide state
- **Dependency Injection**: Pass models through environment or initializers
- **Protocol-oriented**: Define protocols for testability and abstraction
- **Value types preferred**: Use structs for data, classes only when reference semantics needed

#### SwiftUI Best Practices
- **View composition**: Break large views into smaller, reusable components
- **View modifiers**: Extract common styling into custom view modifiers
- **PreferenceKey**: Use for child-to-parent communication
- **@ViewBuilder**: For flexible view composition
- **Avoid massive views**: Keep view bodies under 50 lines
- **Platform conditionals**: Use `#if os(iOS)` / `#if os(macOS)` etc. for platform-specific code

#### State Management
- **Single source of truth**: Models own their state
- **Unidirectional data flow**: Views read state, send actions to models
- **iCloud sync**: All persistent state goes through `💾ICloud` layer
- **Widget updates**: Call `WidgetCenter.shared.reloadTimelines()` after state changes
- **Observation**: Use `NotificationCenter` for external changes (iCloud sync)

#### Error Handling
- **Typed errors**: Define custom error enums
- **Do-catch**: Handle errors explicitly, don't silently fail
- **Optional unwrapping**: Use guard/if-let, avoid force unwrapping
- **Assertions**: Use `assertionFailure()` for programmer errors in debug builds

---

### 🚫 Forbidden Practices

1. **NO auto-generated markdown files** - Never create README, CHANGELOG, or documentation files unless explicitly requested
2. **NO test files** - Don't generate tests unless user explicitly asks
3. **NO boilerplate scaffolding** - Only create files that are immediately needed
4. **NO utility/helper catch-alls** - Each file must have clear single responsibility
5. **NO force unwrapping** - Use safe optional handling (`guard`, `if let`, `??`)
6. **NO massive view files** - Break down into smaller components
7. **NO global state** - Use proper dependency injection
8. **NO commented-out code** - Remove dead code immediately
9. **NO abbreviations** - Use full descriptive names
10. **NO breaking emoji naming** - Maintain existing emoji prefix conventions

---

### ✅ Required Practices

1. **Ask before creating new files**: "Do you want to create `<filename>`?"
2. **Update architecture.md**: Document all architectural changes
3. **Update patch_notes.md**: Log all changes with date and description
4. **Maintain platform separation**: Keep iOS/macOS/watchOS code in respective folders
5. **Share common code**: Put cross-platform code in `Shared/`
6. **Follow emoji conventions**: Use existing emoji prefixes consistently
7. **iCloud sync**: All persistent data must go through `💾ICloud`
8. **Widget reload**: Always reload widgets after data changes
9. **Platform conditionals**: Use `#if os()` for platform-specific code
10. **SwiftUI lifecycle**: Use proper lifecycle methods and state management

---

### 📝 Code Review Checklist

Before completing any code change, verify:

- [ ] No new markdown files created (except architecture.md, patch_notes.md)
- [ ] No test files created (unless explicitly requested)
- [ ] All new files have clear single responsibility
- [ ] Emoji naming conventions maintained
- [ ] Platform-specific code in correct folders
- [ ] Shared code properly placed in `Shared/`
- [ ] iCloud sync properly implemented for persistent state
- [ ] Widget reload called after state changes
- [ ] No force unwrapping or unsafe optional handling
- [ ] No commented-out or dead code
- [ ] architecture.md updated with structural changes
- [ ] patch_notes.md updated with change description
- [ ] User explicitly approved any new file creation

---

### 🔄 Change Documentation Process

**Every code change MUST:**

1. **Update architecture.md** if:
   - New files/folders created
   - Architecture patterns changed
   - New dependencies added
   - Data flow modified

2. **Update patch_notes.md** with:
   - Date (YYYY-MM-DD format)
   - Brief description of change
   - Files affected
   - Reason for change

**Format for patch_notes.md:**
```
## YYYY-MM-DD - [Brief Title]
- **Changed**: [What was modified]
- **Files**: [List of affected files]
- **Reason**: [Why this change was made]
```

---

### 🎯 Platform-Specific Guidelines

#### iOS/visionOS
- Use `WindowGroup` for main scene
- Support both iPhone and iPad layouts
- Implement share sheets for text sharing
- Handle URL schemes for inter-app communication
- Support StandBy mode and Lock Screen widgets

#### macOS
- Use `NSApplicationDelegateAdaptor` for app delegate
- Implement multiple window scenes
- Add menu bar commands (`🪄Commands.swift`)
- Support notification center widgets
- Handle desktop widgets

#### watchOS
- Keep UI minimal and glanceable
- Support complications
- Implement Smart Stack widgets
- Optimize for small screen
- Handle Digital Crown input

#### Widgets (All Platforms)
- Use `WidgetKit` framework
- Implement timeline provider
- Support multiple widget families
- Handle empty states gracefully
- Sync with main app via iCloud

---

### 🧪 When Tests ARE Requested

If user explicitly asks for tests:

- Use XCTest framework
- Create separate test targets
- Test business logic, not UI
- Mock iCloud layer for unit tests
- Test widget timeline generation
- Test data model serialization
- Place tests in appropriate test folders

---

### 📚 Reference Files

When implementing features, always reference:
- `#[[file:architecture.md]]` - Overall system architecture
- `#[[file:patch_notes.md]]` - Recent changes and patterns
- Existing code in `Shared/` for patterns and conventions
- Platform-specific `App.swift` files for entry point patterns
- `📝NoteModel.swift` for state management patterns
- `💾ICloud.swift` for persistence patterns

---

### 🎨 UI/UX Principles

- **Consistency**: Match existing UI patterns across platforms
- **Native feel**: Use platform-appropriate controls and patterns
- **Accessibility**: Support Dynamic Type, VoiceOver, high contrast
- **Performance**: Minimize widget update frequency
- **Simplicity**: Keep UI focused on core memo functionality
- **Customization**: Expose styling options through `🎚️Customize` types

---

### 🔐 Security & Privacy

- **No data collection**: App doesn't collect user information
- **iCloud only**: All sync via user's iCloud account
- **Local storage**: Use UserDefaults/iCloud only, no external servers
- **Privacy manifest**: Maintain accurate privacy declarations
- **Entitlements**: Only request necessary capabilities

---

### 📦 Dependencies & Frameworks

**Allowed:**
- SwiftUI (UI framework)
- WidgetKit (widgets)
- Foundation (core utilities)
- Combine (reactive programming)
- CloudKit (iCloud sync via NSUbiquitousKeyValueStore)

**Forbidden:**
- Third-party networking libraries
- Analytics/tracking SDKs
- External storage services
- Heavy UI frameworks

---

### 🚀 Deployment Considerations

- Support minimum OS versions as defined in project
- Test on all target platforms before release
- Verify widget functionality on all platforms
- Test iCloud sync between devices
- Validate App Store requirements
- Check privacy policy compliance

---

**Remember**: This is a lean, focused memo widget app. Every line of code should serve the core functionality. When in doubt, ask the user before adding complexity.
