# Turn

The user chose Turn from the page-corner studies, then approved its native
light, dark and tinted appearances. The squircle itself is the page, with a
single rising fold and a dark underside. No crease lines or ornamental detail.

The studies are preserved on `prototype-app-icon-logo-1-svg` at `67cf356`.
The production source is `App/Aujour/AppIcon.icon`. Its Mono (`tinted`)
specialization lets iOS render both light and dark tinted icons in the user's
chosen tint. The artwork is square; the system supplies the icon mask.

`python3 scripts/render-launch-icon.py` exports the light/dark launch images
using Xcode 27's Icon Composer renderer. The 112 pt image is shared by the
system's `LaunchScreen.storyboard` and `JournalLaunchView`. `LaunchBackground`
matches `Palette.background`; the hosted tests check both appearances.

The runtime screen is driven by `Journal.state.opening`. Folder discovery and
file reads run asynchronously off the main actor. The state stays opening
through conflict settlement, template preparation and today's entry read,
then changes immediately to the journal or recovery. There is no minimum
splash duration or exit animation. First-run welcome and later folder-change
transitions keep their existing behavior. The system launch screen follows
system appearance; the runtime screen also respects the app's theme override.

## Visual verification

Capture from the built app on iPhone and iPad, in light and dark:

- System launch storyboard: centred 112 pt Turn, matching paper background.
- Startup with an entry read suspended: the same image while real work waits.
- Completed entry: splash has left and the day is ready to write.
- Unavailable folder: splash has left and recovery is available.

`LaunchPresentationTests` captures these states with a test-only suspended
source. No delays or preview hooks are compiled into the app. Native tinted
appearance remains an OS-rendered icon feature, separate from the in-app
light/dark launch image.
