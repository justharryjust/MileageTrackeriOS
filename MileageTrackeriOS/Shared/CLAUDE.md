# Shared/

Single file: `DesignSystem.swift`. All visual tokens for the app.

---

## Colours (`extension Color`)

### Brand

| Token | Hex | Use |
|-------|-----|-----|
| `Color.mtGreen` | `#2DC873` | Primary brand, buttons, active states |
| `Color.mtGreenDark` | `#1F9955` | Pressed/dark variant |
| `Color.mtGreenLight` | `#B8F2D1` | Tinted backgrounds |

### Semantic

| Token | Maps to |
|-------|---------|
| `Color.mtBackground` | `systemBackground` |
| `Color.mtSurface` | `secondarySystemBackground` |
| `Color.mtBorder` | `separator` |
| `Color.mtTextPrimary` | `label` |
| `Color.mtTextSub` | `secondaryLabel` |

### Status

| Token | Use |
|-------|-----|
| `Color.mtRecording` | Active trip indicator (red-ish) |
| `Color.mtWarning` | Warnings, uncategorised trips (yellow) |
| `Color.mtSuccess` | Alias for `mtGreen` |

---

## Spacing (`enum MTSpacing`)

| Token | Value |
|-------|-------|
| `xs` | 4 pt |
| `sm` | 8 pt |
| `md` | 16 pt |
| `lg` | 24 pt |
| `xl` | 32 pt |
| `xxl` | 48 pt |

---

## Corner Radius (`enum MTRadius`)

| Token | Value |
|-------|-------|
| `sm` | 8 pt |
| `md` | 12 pt |
| `lg` | 16 pt |
| `xl` | 24 pt |
| `full` | 9999 pt (capsule) |

---

## View Modifiers & Button Styles

| API | Effect |
|-----|--------|
| `.mtCard()` | `mtSurface` background + `MTRadius.lg` clip shape |
| `MTPrimaryButtonStyle()` | Full-width, semibold white text, `mtGreen` fill; pass `isDestructive: true` for `mtRecording` fill |
| `MTSecondaryButtonStyle()` | Full-width, `mtGreen` text, `mtGreenLight.opacity(0.3)` background |

---

## Rule

Always use design tokens. Never use raw hex colours, literal `CGFloat` spacing values, or inline corner radii in views.
