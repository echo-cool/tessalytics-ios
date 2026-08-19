# Tessalytics design system

Tessalytics uses a restrained, automotive-inspired visual system built around the Tesla Motors palette referenced during the initial redesign. It is an independent product identity and must not copy Tesla artwork, vehicle controls, logos, typography, or proprietary interface layouts.

## Core palette

| Token | Hex | Role |
| --- | --- | --- |
| Accent | `#CC0000` | Primary actions, selected navigation, forecast emphasis |
| Graphite | `#212121` | Hero surfaces and high-contrast structure |
| Steel | `#818181` | Secondary neutral data series and metadata |
| Mist | `#F2F2F2` | Subtle separation and grouped controls |
| Snow | `#FAFAFA` | Light-mode canvas |

Dark mode uses near-black derived surfaces. Neutral content uses adaptive `Color.primary` so it remains visible in both appearances.

## Semantic colors

Green is reserved for healthy, online, charged, verified, or improving states. Amber is reserved for caution, reduced confidence, or attention. Red remains both the brand accent and the critical-state color; context and iconography must make the meaning clear without relying on color alone.

## Components

- `TessalyticsScreen` supplies the adaptive canvas and restrained red edge accent.
- `TessalyticsHeroSurface` is the dark graphite-to-black summary surface used for primary dashboard context.
- `SurfaceCard` is a neutral elevated content container with a short semantic accent rail.
- `MetricCard` presents one metric with a Dynamic Type-aware symbol, value, label, and optional comparison.
- `SectionCard` groups charts and detail content with consistent spacing and hierarchy.
- `tessalyticsChartStyle()` supplies shared plot-area chrome without replacing each chart's accessible semantic labels.

## Usage rules

- Prefer one emphasized red element per local section.
- Keep general surfaces neutral; do not tint entire cards for decoration.
- Use green and amber only for state or meaning.
- Keep chart categories distinguishable with red, adaptive neutral, steel, green, and amber.
- Use system text styles, SF Symbols, and semantic labels so Dynamic Type and VoiceOver remain supported.
- Verify new screens in both light and dark appearances before merging.

## Navigation and density

- Keep four persistent top-level destinations: Status, Activity, Analysis, and Settings.
- Activity switches directly between Drives and Charging. Analysis switches directly between Overview, Drive, Charge, Forecast, and Battery.
- Reserve pushed navigation for a selected drive or charging-session detail. Present settings, support, and explanatory content as dismissible sheets.
- Put methodology and interpretation guidance behind the contextual Help button. Keep chart titles and in-place labels concise.
- Metric cards use a compact 96-point minimum height, 10-point internal padding, and two-column adaptive grids on iPhone.
- Use the system tab bar, navigation title behavior, sheets, menus, and SF Symbols rather than custom navigation chrome.

## App icon

The app icon is an original road-and-telemetry mark using graphite, red, gray, and white. It must remain independent: no Tesla wordmark, Tesla T, manufacturer badge, or vehicle silhouette.
