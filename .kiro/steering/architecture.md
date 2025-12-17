# LockInNote - System Architecture

**Last Updated**: 2025-12-16 (Drawing Canvas Implementation)

---

## Overview

LockInNote is a multi-platform memo widget application built with Swift and SwiftUI, supporting iOS, iPadOS, visionOS, macOS, and watchOS. The app enables users to create, edit, and customize memo notes that are displayed as widgets across all Apple platforms with iCloud synchronization.

---

## Core Architecture Principles

### Multi-Platform Design
- **Shared Core**: Common business logic and data models in `Shared/` folder
- **Platform-Specific UI**: Separate implementations for iOS/visionOS, macOS, and watchOS
- **Widget Extensions**: WidgetKit implementations for each platform

### State Management
- **ObservableObject Pattern**: `📝NoteModel` and `📱AppModel` manage app state
- **SwiftUI Reactive Bindings**: `@Published` properties trigger UI updates
- **Environment Objects**: Shared state passed through SwiftUI environment

### Data Persistence
- **iCloud Sync**: NSUbiquitousKeyValueStore for cross-device synchronization
- **Abstraction Layer**: `💾ICloud` provides unified storage interface
- **Widget Updates**: Automatic timeline reload on data changes

---

## Project Structure

```
LockInNote/
├── Shared/                          # Cross-platform shared code
│   ├── 🌐Localization/             # Localized strings (multi-language support)
│   ├── 🎚️Customize/               # Customization types and enums
│   ├── 💾ICloud.swift              # iCloud storage abstraction layer
│   ├── 📝NoteModel.swift           # Core note data model (ObservableObject)
│   ├── 📝NoteProperty.swift        # Property definitions for notes
│   ├── 📝NoteFamily.swift          # Note family types (primary/secondary/tertiary)
│   ├── 📝DrawingData.swift         # Drawing data model (Codable wrapper for PKDrawing)
│   ├── 🗄️Rest/                    # Supporting utilities and helpers
│   ├── 🧰SupportingFiles/          # Assets, entitlements, Info.plist
│   └── 🪧WidgetView/               # Shared widget view components
│
├── iOS, visionOS/                   # iOS and visionOS implementation
│   ├── App.swift                   # App entry point (@main)
│   ├── ContentView.swift           # Main container view
│   ├── 📱AppModel.swift            # App-level state management
│   ├── 📝NoteTab.swift             # Note editing interface (with drawing canvas)
│   ├── ✏️DrawingCanvas.swift       # PencilKit drawing canvas (iOS only, types use 🖊)
│   ├── ✏️DrawingToolbar.swift      # Drawing tools UI (iOS only, types use 🖊)
│   ├── 🔖Tab.swift                 # Tab navigation definitions
│   ├── 👆Buttons.swift             # Reusable button components
│   ├── 💬Sheet.swift               # Modal sheet presentations
│   ├── 🎚️CustomizeMenu/           # Customization UI components
│   ├── 🔗URLSchemeActionMenu.swift # URL scheme handling
│   ├── 🛠️OptionTab.swift          # Settings and options
│   ├── 🗄️Rest/                    # Platform-specific utilities
│   └── 🧰SupportingFiles/          # Platform-specific assets
│
├── macOS/                           # macOS implementation
│   ├── App.swift                   # App entry point with NSApplicationDelegateAdaptor
│   ├── ContentView.swift           # Main window content
│   ├── 📱AppModel.swift            # App delegate and state management
│   ├── 📝NoteWindow.swift          # Note editing window scene
│   ├── 📝NoteEditor.swift          # Note editor view
│   ├── 🎚️CustomizeWindow.swift    # Customization window scene
│   ├── 🎚️CustomizeMenu.swift      # Customization menu
│   ├── 🪄Commands.swift            # Menu bar commands
│   ├── 🗄️Rest/                    # Platform-specific utilities
│   └── 🧰SupportingFiles/          # Platform-specific assets
│
├── watchOS/                         # watchOS implementation
│   ├── App.swift                   # App entry point
│   ├── ContentView.swift           # Main watch interface
│   ├── 📱AppModel.swift            # Watch app state management
│   ├── 📝NoteTab.swift             # Note list and editing
│   ├── 🔖Tab.swift                 # Tab navigation
│   ├── 📖NoteDetailView.swift      # Note detail view
│   ├── 💬Sheet.swift               # Modal presentations
│   ├── 🎚️CustomizeMenu.swift      # Customization options
│   ├── ℹ️AboutApp.swift           # About screen
│   ├── ℹ️InfoTab.swift            # Information tab
│   └── 🧰SupportingFiles/          # Platform-specific assets
│
└── Widget/                          # WidgetKit extensions
    ├── Widget.swift                # Widget configuration and timeline
    ├── WidgetBundle.swift          # Widget bundle definition
    ├── iOS, visionOS/              # iOS/visionOS widget views
    ├── macOS/                      # macOS widget views
    └── watchOS/                    # watchOS complications
```

---

## Key Components

### 📝 Note Model (`📝NoteModel.swift`)
**Responsibility**: Core data model for memo notes

**Key Features**:
- ObservableObject with @Published properties
- Manages note content (title, text, drawing data)
- Handles customization settings (font, colors, alignment)
- iCloud synchronization via `💾ICloud` layer
- Widget timeline updates on changes
- External change observation via NotificationCenter

**Properties**:
- `family`: Note family type (primary/secondary/tertiary)
- `title`, `text`: Note content
- `drawingData`: PencilKit drawing data (iOS)
- `fontWeight`, `fontDesign`, `italic`: Typography settings
- `multilineTextAlignment`: Text alignment
- `empty_*`: Empty state configuration
- `system_*`: System widget appearance settings
- `accessory_*`: Accessory widget settings

**Methods**:
- `save(_:_:)`: Persist property changes to iCloud
- `loadICloud(_:)`: Load property from iCloud
- `reloadWidget()`: Trigger widget timeline update

### 🖊 Drawing Canvas (`✏️DrawingCanvas.swift`) - iOS Only
**Responsibility**: PencilKit-based drawing interface

**Key Features**:
- Compact square preview mode (300pt, aspect ratio 1:1)
- Expands to full-screen on tap with spring animation
- Three drawing tools: pen, marker, eraser
- Undo/redo functionality
- Auto-saves drawing data to iCloud on collapse
- UIViewRepresentable wrapper for PKCanvasView

**Components**:
- `🖊DrawingCanvas`: Main view with expand/collapse logic
- `🖊CanvasViewRepresentable`: UIKit bridge for PKCanvasView
- `🖊DrawingToolbar`: Bottom toolbar with tool selection
- `🖊DrawingTool`: Enum for pen/marker/eraser selection

**Interaction Flow**:
1. Compact mode: Square canvas preview, tap to expand
2. Expanded mode: Full-screen drawing with top toolbar (undo/redo/close) and bottom toolbar (tools)
3. Tool selection updates PKCanvasView.tool in real-time
4. Close/done button collapses canvas and saves drawing

**Note**: File uses ✏️ emoji in filename but 🖊 emoji for type names due to Swift parsing compatibility

### 💾 iCloud Storage (`💾ICloud.swift`)
**Responsibility**: Abstraction layer for iCloud persistence

**Key Features**:
- NSUbiquitousKeyValueStore wrapper
- Type-safe Codable serialization
- Key generation for note families and properties
- External change notifications
- Error handling with custom LoadError enum

**API**:
- `save(_:_:_:)`: Save property value to iCloud
- `load(_:_:)`: Load property value from iCloud
- `addObserver(_:_:)`: Register for external change notifications
- `decodeKey(_:_:)`: Parse iCloud key to property

### 📱 App Model (`📱AppModel.swift`)
**Responsibility**: App-level state management

**Platform Variations**:
- **iOS/visionOS**: StateObject managing tab selection and sheet presentation
- **macOS**: NSApplicationDelegate managing window lifecycle
- **watchOS**: StateObject managing navigation and complications

### 🪧 Widget Views
**Responsibility**: Widget UI rendering

**Key Features**:
- Shared widget view components in `Shared/🪧WidgetView/`
- Platform-specific widget entry points
- Timeline provider for widget updates
- Support for multiple widget families
- Empty state handling
- Customizable appearance

---

## Data Flow

### Write Path
1. User edits note in UI
2. View updates @Published property in `📝NoteModel`
3. Model calls `save(_:_:)` method
4. `💾ICloud` serializes and stores to NSUbiquitousKeyValueStore
5. Model calls `reloadWidget()` to update widget timeline
6. WidgetKit refreshes widget display

### Read Path (Initial Load)
1. `📝NoteModel` initializes
2. Calls `loadICloud(_:)` for each property
3. `💾ICloud` deserializes from NSUbiquitousKeyValueStore
4. Properties populate @Published values
5. SwiftUI views react to state changes

### Sync Path (External Changes)
1. iCloud detects external change (from another device)
2. NSUbiquitousKeyValueStore posts notification
3. `📝NoteModel` receives notification via observer
4. Model reloads changed properties
5. Widget timeline updates
6. UI reflects new state

---

## Platform-Specific Implementations

### iOS/visionOS
- **Entry Point**: `iOS_and_visionOS_App` struct with @main
- **Scene**: WindowGroup with ContentView
- **Navigation**: Tab-based interface
- **Features**: Share sheets, URL schemes, StandBy support
- **Widgets**: Home screen, Lock screen, StandBy

### macOS
- **Entry Point**: `macOSApp` struct with NSApplicationDelegateAdaptor
- **Scenes**: Multiple window scenes (Note, Customize, URL Scheme, IAP, Help)
- **Navigation**: Window-based with menu bar commands
- **Features**: Menu bar integration, multiple windows
- **Widgets**: Notification center, Desktop

### watchOS
- **Entry Point**: `watchOSApp` struct with @main
- **Scene**: WindowGroup with ContentView
- **Navigation**: Tab-based with minimal UI
- **Features**: Complications, Smart Stack
- **Widgets**: Watch face complications

---

## Widget Architecture

### Widget Families Supported
- **iOS/iPadOS**: systemSmall, systemMedium, systemLarge, systemExtraLarge, accessoryRectangular, accessoryCircular
- **macOS**: systemSmall, systemMedium, systemLarge
- **watchOS**: accessoryRectangular, accessoryCircular, accessoryInline, accessoryCorner

### Timeline Provider
- Provides widget snapshots at specific times
- Updates triggered by app data changes
- Reads data from shared iCloud storage
- Renders using shared widget views

### Widget Configuration
- Multiple note families (primary, secondary, tertiary)
- Per-family customization settings
- Appearance modes (standard, color, gradient)
- Font customization (size, weight, design)
- Empty state customization

---

## Naming Conventions

### Emoji Prefixes
- 📝 - Note-related (models, views, properties)
- 🖊 - Drawing (canvas, tools, drawing UI types)
- ✏️ - Drawing (file names only, use 🖊 for type names)
- 🎚️ - Customization (settings, enums, types)
- 💾 - Storage/persistence (iCloud layer)
- 📱 - App-level (app models, delegates)
- 🔖 - Navigation (tabs, routing)
- 👆 - Interaction (buttons, gestures)
- 💬 - Presentation (sheets, modals)
- 🗄️ - Utilities (rest, supporting code)
- 🧰 - Resources (assets, supporting files)
- 🪧 - Widgets (widget views)
- 🌐 - Localization (strings, translations)
- 🪄 - Commands (menu bar, shortcuts)
- ℹ️ - Information (about, help)
- 🔗 - Integration (URL schemes, external)
- 🛠️ - Settings (options, preferences)
- 💥 - Feedback (haptics, sounds)

### Hungarian Notation
- ⓝ - Note-related parameters
- ⓟ - Property parameters
- ⓥ - Value parameters
- ⓒ - Changed/collection parameters
- ⓞ - Observer/option parameters

---

## Dependencies

### System Frameworks
- **SwiftUI**: Declarative UI framework
- **WidgetKit**: Widget extension support
- **Foundation**: Core utilities and types
- **Combine**: Reactive programming (implicit via @Published)
- **CloudKit**: iCloud sync (NSUbiquitousKeyValueStore)
- **PencilKit**: Drawing canvas support (iOS)

### Third-Party Dependencies
- **Portal** (iOS 17+): Element transitions for card-to-fullscreen animations
  - Repository: https://github.com/Aeastr/Portal
  - Package Product: Portal (select from package products list)
  - Import: `import Portal`
  - Usage: Smooth morphing transitions from grid cards to fullscreen drawing view

---

## Security & Privacy

### Data Storage
- All data stored in user's iCloud account
- No external servers or databases
- No data collection or analytics

### Entitlements
- iCloud (NSUbiquitousKeyValueStore)
- App Groups (for widget data sharing)
- Platform-specific capabilities as needed

### Privacy Policy
- App doesn't collect user information
- All data remains in user's control
- iCloud sync is optional (controlled by user's iCloud settings)

---

## Build Configuration

### Targets
- LockInNote (iOS/visionOS)
- LockInNote (macOS)
- LockInNote (watchOS)
- Widget Extension (iOS/visionOS)
- Widget Extension (macOS)
- Widget Extension (watchOS)

### Minimum OS Versions
- iOS: (defined in project settings)
- macOS: (defined in project settings)
- watchOS: (defined in project settings)
- visionOS: (defined in project settings)

---

## Future Considerations

### Scalability
- Current architecture supports up to 3 note families
- iCloud storage limited by NSUbiquitousKeyValueStore (1MB total)
- Widget timeline updates optimized for battery life

### Extensibility
- Protocol-based design allows easy feature additions
- Shared code maximizes code reuse across platforms
- Platform-specific folders isolate platform concerns

### Maintenance
- Emoji naming provides visual organization
- Clear separation of concerns
- Minimal dependencies reduce maintenance burden

---

## Migration Notes

### Version 1.1 Migration
- `🗄️MigrationFromVer_1_1` handles legacy data migration
- Executed on iOS and watchOS platforms
- Migrates widget kind identifiers

---

**Note**: This architecture document should be updated whenever:
- New files or folders are added
- Architecture patterns change
- New dependencies are introduced
- Data flow is modified
- Platform support changes
