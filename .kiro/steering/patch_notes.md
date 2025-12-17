# LockInNote - Patch Notes

**Purpose**: Track all code changes, implementations, and modifications to the LockInNote project.

---

## 2025-12-17 - Fixed Drawing Save + Zoom Issues with Canvas Manager

- **Changed**: Rewrote canvas architecture to fix both save persistence and zoom coordinate issues
- **Files**:
  - `iOS, visionOS/📝NotesGridView.swift` (modified) - Replaced @State canvasView with @StateObject 🖊CanvasManager
- **Reason**: Two interconnected issues: (1) @State PKCanvasView was recreated on view reappear, losing drawing data; (2) PKCanvasView auto-adjusts zoom when loading drawings, causing coordinate mismatch
- **Root Causes Fixed**:
  - Save Issue: @State creates new PKCanvasView instance each time view appears during Portal transitions
  - Zoom Issue: PKCanvasView (UIScrollView subclass) auto-adjusts zoomScale/contentOffset when drawing is loaded
- **Solution**:
  - Created `🖊CanvasManager` class with @StateObject for stable PKCanvasView reference across view lifecycle
  - Disabled scroll/zoom entirely: `isScrollEnabled = false`, `min/maxZoomScale = 1.0`
  - Set `contentSize` to match view size exactly
  - Added `normalizeDrawing()` to transform out-of-bounds drawings back into canvas coordinate space
  - Force reset zoom/offset after loading via `DispatchQueue.main.async`
  - Added `💾ICloud.synchronize()` on dismiss to ensure immediate persistence
  - Delegate enforces zoom=1.0 and offset=.zero after any drawing change
- **Impact**:
  - Drawings persist correctly across app launches
  - Canvas maintains 1:1 zoom with view coordinate space
  - Preview cards show saved drawings
  - Auto-save every 2 seconds + save on dismiss
  - iCloud sync works reliably

## 2025-12-16 - Portal Transitions with Full-Screen Canvas

- **Changed**: Implemented Portal library with card morphing directly into full-screen drawing canvas
- **Files**:
  - `iOS, visionOS/📝NotesGridView.swift` (modified) - Added Portal transitions with full-screen canvas expansion
  - `iOS, visionOS/ContentView.swift` (reverted) - Removed navigation, kept simple TabView
  - `iOS, visionOS/📱AppModel.swift` (modified) - Removed selectedNoteForEditing property
  - `iOS, visionOS/🔖Tab.swift` (modified) - Added notesList case
  - `iOS, visionOS/📝NoteTab.swift` (modified) - Removed back button navigation
- **Reason**: Use Portal library for seamless card-to-canvas transitions. Grid card morphs directly into full-screen drawing canvas.
- **Impact**:
  - Tap grid card → morphs into full-screen drawing canvas
  - Canvas fills entire screen with colored background matching card
  - Top toolbar with close, title, and customize buttons
  - Drawing tools at bottom
  - X button dismisses back to grid with smooth reverse animation
  - `.portal(item:_:)` on preview (source) and canvas (destination)
  - `.portalTransition(item:layerView:)` manages the morphing transition
  - Drawing auto-saves every 2 seconds
  - Requires Portal package
- **Performance Optimizations**:
  - View identity preservation with `.id()` modifier
  - Only preview image participates in Portal transition
  - Async image generation for drawing previews
  - Cached preview images to prevent regeneration
  - Text labels excluded from transition to prevent morphing
- **User Experience**:
  - Card expands to become the canvas itself
  - Background color preserved from card to canvas
  - Smooth, seamless transition with no intermediate states
  - Immediate drawing capability after expansion
- **Dependencies**: Portal package (select "Portal" product, iOS 17+)

---

## 2025-12-16 - Drawing Canvas Implementation (iOS)

- **Changed**: Replaced text input with PencilKit drawing canvas that expands in-place
- **Files**: 
  - `iOS, visionOS/✏️DrawingCanvas.swift` (created) - Main drawing canvas with expand/collapse animation (uses 🖊 emoji prefix for types)
  - `iOS, visionOS/✏️DrawingToolbar.swift` (created) - Drawing tools UI (pen, marker, eraser)
  - `Shared/📝DrawingData.swift` (created) - Drawing data model for Codable storage
  - `iOS, visionOS/📝NoteTab.swift` (modified) - Replaced TextField with drawing canvas
  - `Shared/📝NoteModel.swift` (modified) - Added drawingData property with iCloud sync
  - `Shared/📝NoteProperty.swift` (modified) - Added drawingData case to enum
  - `Shared/🎚️Customize/🎚️SaveValues.swift` (modified) - Added drawingData case to switch statement
- **Reason**: Transform note-taking from text-based to drawing-based interface. Canvas starts as compact square widget preview and expands to full-screen drawing mode on tap, eliminating navigation complexity.
- **Impact**: 
  - iOS-only implementation (macOS/watchOS/visionOS not affected)
  - Drawing data syncs via iCloud using existing infrastructure
  - Text input temporarily removed (will be re-added later)
  - Undo/redo functionality via PKCanvasView's built-in undo manager
  - Three drawing tools: pen (thin), marker (thick), eraser
  - Uses 🖊 (pen) emoji for type names instead of ✏️ (pencil) due to Swift parsing compatibility
- **Migration**: Files must be added to Xcode project targets manually

---

## 2025-12-16 - Initial Steering Configuration

- **Changed**: Created AI coding practices steering file and documentation structure
- **Files**: 
  - `.kiro/steering/ai-coding-practices.md` (created)
  - `.kiro/steering/architecture.md` (created)
  - `.kiro/steering/patch_notes.md` (created)
- **Reason**: Establish consistent coding standards and documentation practices for AI-assisted development. Ensures all future changes follow project conventions and are properly documented.

---

## Template for Future Entries

```
## YYYY-MM-DD - [Brief Title]

- **Changed**: [Detailed description of what was modified, added, or removed]
- **Files**: 
  - [List of affected files with action: created/modified/deleted]
- **Reason**: [Why this change was necessary and what problem it solves]
- **Impact**: [Optional: How this affects other parts of the system]
- **Migration**: [Optional: Any migration steps needed for existing users/data]
```

---

## Guidelines for Patch Notes

### When to Add an Entry
- New files or folders created
- Existing code modified (bug fixes, refactoring, features)
- Architecture or design pattern changes
- Dependencies added or updated
- Platform support changes
- Data model or storage changes
- UI/UX modifications
- Performance optimizations
- Security or privacy updates

### What NOT to Document
- Typo fixes in comments
- Code formatting changes (unless part of larger refactor)
- Documentation-only updates (unless significant)
- Experimental changes that were reverted

### Entry Format
- **Date**: Use YYYY-MM-DD format for consistency
- **Title**: Brief, descriptive summary (5-10 words)
- **Changed**: Clear description of modifications
- **Files**: Complete list of affected files with paths
- **Reason**: Context for why change was made
- **Impact**: (Optional) Downstream effects on other components
- **Migration**: (Optional) Steps needed for data/code migration

### Best Practices
- Write entries immediately after completing changes
- Be specific about file paths and changes
- Link related entries when changes span multiple sessions
- Use technical language appropriate for developers
- Include version numbers when relevant
- Reference issue/ticket numbers if applicable

---

## Change Categories

### 🆕 New Features
Major functionality additions that provide new capabilities to users.

### 🐛 Bug Fixes
Corrections to existing code that resolve issues or unexpected behavior.

### ♻️ Refactoring
Code restructuring that improves maintainability without changing functionality.

### 🎨 UI/UX
Changes to user interface, visual design, or user experience.

### ⚡ Performance
Optimizations that improve speed, memory usage, or battery life.

### 🔒 Security
Changes related to security, privacy, or data protection.

### 📦 Dependencies
Addition, removal, or updates to external dependencies or frameworks.

### 🏗️ Architecture
Structural changes to project organization or design patterns.

### 🌐 Localization
Changes to translations, language support, or internationalization.

### 📱 Platform
Platform-specific implementations or cross-platform compatibility changes.

---

**Note**: This file is automatically referenced by AI coding assistants to understand recent changes and maintain consistency with project patterns.
