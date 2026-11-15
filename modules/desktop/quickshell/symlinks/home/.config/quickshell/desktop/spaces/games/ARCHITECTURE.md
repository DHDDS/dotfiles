# Games implementation

## Scope and presentation

Games uses the retained SpaceHost and shared cinematic
[presentation contract](../movies/ARCHITECTURE.md#presentation-contract). Each
instance owns its catalogue, selection, workers, preferences and artwork cache.
Library is the default so installed games work without IGDB credentials. Local
imports are files, not launcher installations, and never execute automatically.
Torrent/local-library helpers use the Games namespace and `game` kind.

Store actions must distinguish ownership, installation and launch availability.
A native ProtonDB badge follows Steam's platform data, with cached `oslist` as
fallback (it may include discontinued ports). HLTB estimates link to their match;
missing/ambiguous matches require manual correction. Account-only Steam data
such as achievements, cloud-sync state and friends is unavailable.

IGDB, GOG and itch.io marks come from [Simple Icons](https://github.com/simple-icons/simple-icons);
store and ProtonDB badges retain their supplied artwork.

## Provider and worker boundaries

`backend.py` owns UUID records, provider IDs, favorites, store overrides,
IGDB OAuth/pacing, store-description fallbacks and the ProtonDB cache. Credentials stay in Python. QML uses bounded JSON-lines transport
through the existing Movies `Worker`, with a selectable backend directory.
The worker owns a process group; explicit close releases its request threads and
owned subprocesses. User-launched games and launcher actions run independently
through `uwsm app -t service` when available. Steam supplies its own install and
uninstall prompts; Epic uninstall requires the page confirmation first. Launcher
snapshots are reused for 60 seconds, except that any action other than Play marks
them stale and Refresh game rescans snapshots older than five seconds. After an
uninstall, the page rechecks the selected game's store state after 3, 10 and 30
seconds while visible, stopping when its installation changes.

Legendary's `list` always logs in and refreshes Epic assets over the network
(2–9 seconds), so Epic ownership is cached as `epic-owned:v1` for six hours, five
minutes after a failure; rescans run only the local `list-installed`. Library
Refresh and install completion re-read ownership. When Epic is unreachable, the
saved ownership stays in use with a notice. Only Legendary's credential messages
mean signed out; its "Logging in…" log line appears on every run.

### Epic installation progress

Epic installs run a detached `backend.py --epic-install` supervisor through the
same UWSM application lifetime as launcher actions. It drains Legendary's output
and saves only percentage, download speed, ETA and terminal status. Raw output
and account/session data are never stored or sent to QML. Progress is best effort
against Legendary's log format; an unknown format retains the indeterminate
install state until the process exits.

Atomic private JSON snapshots in `epic-installs/` under the Games data directory
retain one attempt per Epic app. A start lock serializes requests and a running
flock identifies the supervisor without trusting reusable PIDs. A UUID rejects
late supervisors from older attempts; launch has a 30-second grace period before
an absent supervisor counts as interrupted. Failed/interrupted attempts can be
retried with Install, allowing Legendary to resume its partial download. These
machine-local snapshots are not part of the portable library backup.

Games reads snapshots when it opens or is shown and after starting an install,
then every 1.5 seconds while one is running. The Epic button disables during installation and shows percentage;
inline status adds speed/ETA and retains failures. The shared Notifications panel
lists Epic jobs across selections, alongside the current game's torrent jobs.
Observed terminal transitions send desktop notifications; the initial snapshot
does not replay old outcomes. Completion
refreshes launcher state and the selected action to Play, deferring visible
catalogue updates while hidden. Closing Games releases its worker but preserves
the independent supervisor; reopening recovers progress from disk.

Install jobs also appear in the shared header activity indicator. Snapshot-only
polls do not create a loading indicator. Content classification uses a separate
two-thread enrichment lane, leaving foreground details, launcher reads and
ordered actions available.

Library listings use only saved and launcher data; there is no background
per-game hydration. Launchers and the Steam CDN supply a poster for every library
row (Steam's portrait `library_600x900` asset; the landscape `appdetails` header
is never a poster). Descriptions, screenshots and the IGDB match load through
`details` for the selected game only. A found IGDB match is reused for 30 days and
Steam descriptions for seven; both stay usable when stale. Selecting a game costs
at most one IGDB search and one `appdetails` read, and nothing once cached.

### GOG through Heroic

`gog.py` reads Heroic's `store_cache/gog_library.json` (`games` array) and
`gog_store/installed.json` (`installed` array). Older `gog_store/library.json`
libraries are accepted when the current cache is absent, not when it is corrupt.
Reads are bounded to 16 MiB. Numeric `app_name`/`appName` identify GOG products;
DLC/redist entries are omitted. Installed paths must be absolute existing
directories. Cache metadata supplies descriptions, genre, developer and artwork
before optional IGDB enrichment. Library union, ownership/installation filters,
favorites and exact-title/edition safeguards apply across all three stores.
IGDB's GOG website slugs are matched to cached store URLs when available, otherwise
unique exact titles; explicit numeric product IDs never fall back to another ID.
Manual GOG overrides accept only numeric IDs and use the existing SQLite table.

Native Heroic uses `$XDG_CONFIG_HOME/heroic` (default `~/.config/heroic`); Flatpak
uses `~/.var/app/com.heroicgameslauncher.hgl/config/heroic`. The adapter chooses one
populated available launcher profile, preferring native when both are populated.
It never combines accounts or uses one launcher's cache with another launcher.
When neither matching launcher is available, cached titles remain visible but
cannot launch. Missing/malformed ownership caches remain unknown, not unowned;
malformed install records disable installation actions. A missing install file
uses Heroic's empty-registry default. Cache contents are not proof of a current
authenticated session; Heroic handles authentication and offline availability.

Heroic already bundles GOGdl; Games adds no Python dependency, credential file or
GOG OAuth implementation. It never reads or backs up Heroic's auth tokens.
GOG matches and copied library metadata reuse the already-declared private
`library.sqlite`; there are no additional Games private paths to provision.
The optional existing `gaming/launchers/heroic` module provisions its Flatpak.
The adapter rechecks launcher, ownership and installation records at action time.
Both Play and Install pass `heroic://launch/gog/PRODUCT_ID` as one argument to
the corresponding native executable or `flatpak run com.heroicgameslauncher.hgl`.
Heroic's [protocol handler](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/blob/main/src/backend/protocol.ts)
launches installed games or asks whether to install an uninstalled game.
Games hides, without destroying its retained instance, for these UI handoffs.
There is no supported uninstall protocol: the menu opens Heroic for management
instead of invoking GOGdl directly or deleting files. Existing Steam/Epic actions
and runner/prefix handling remain unchanged. Refreshing Games rereads the cache;
new purchases require refreshing Heroic's own library first.

### Launch settings

`SettingsDialog.qml` is a retained lightbox with Performance,
Steam, Epic, GOG, itch.io and Tools sections. Every section exposes actions or
editable preferences. Its surfaces and controls use the immersive `MovieStyle`
palette: the same black background, border and rounded corners as the Spaces
image gallery and library matching dialog. The dialog fills the Space's content
area; preference rows switch to stacked controls in narrow layouts. The page remains below the
host hide control; a dimmed scrim prevents interaction with its background.
Narrow layouts replace the sidebar with a section picker. Escape dismisses a
nested picker before the
lightbox; hiding closes both and returns focus. Library entries expose a Settings
detail tab. Find is restricted to discovery/favorites entries outside the library;
becoming a library entry or switching to My Library restores Overview.

The Notifications popup anchors to the Games page independently of the hidden
Find tab. Its job list scrolls within the available height; hiding Games closes it.

The private SQLite database holds sparse `launch_settings(scope, value)` rows:
`global` defaults, `STORE:EXTERNAL_ID` per-copy overrides, and `game:UUID` preferred
store choices. Overlay, position, font-size preset and FPS limit inherit
independently. Proton selection applies to Epic only. `games.json`'s `proton_path`
supplies the global runner until explicitly replaced through settings. An empty
runner selects UMU's automatic default. Overrides follow launcher identities,
not merged catalogue UUIDs; runner paths remain machine-specific after restore.
Reset removes overrides and the preferred copy, retaining global preferences,
prefixes and payloads. Successful Play remembers its store; search/card launches
try that installed copy first, then another available installed copy.

`launch.py` discovers executable `proton` entry points in Steam libraries/custom
tools, UMU and Heroic directories, deduplicated by resolved path. Saves and launches
validate the selected runner. Selecting it never changes or deletes the existing
Epic prefix. Performance presets generate MangoHud configuration with explicit
position, font size and FPS limit. Off with a nonzero cap loads MangoHud hidden
(`no_display`); Off with no cap avoids injecting it on direct launch paths.
There is no live overlay control or new Gamescope/Mangoapp management.

Epic composes one shell-quoted Legendary `--wrapper` from MangoHud and UMU, with
`--no-wine` only for UMU. `PROTONPATH` selects the runner; Automatic removes an
inherited value. Connect Epic opens `legendary auth` in `xdg-terminal-exec`; no
terminal output, authentication code or session data enters QML. Provider refresh
actions update just that provider instead of logging into every store.

Steam performance setup requires the client to be stopped. `launcher_setup.py`
parses localconfig VDF token spans, inserting the stable user-config `launch.py
steam APPID --` wrapper at `%command%` for the currently known Steam library.
Existing arguments, environment prefixes, unrelated fields and comments survive
byte-for-byte. Missing nodes are inserted; duplicate/unsupported structures are
refused. Atomic publication rechecks the source contents and client state. Setup
is idempotent and repeats for new library entries. The wrapper reads preferences
on each launch and execs the original command, optionally through MangoHud.
Steam remains responsible for Proton selection and compatibility mappings.
The wrapper bypasses itself when `STEAM_USE_MANGOAPP=1`, preserving the existing
Gamescope gaming session's performance controls.

Heroic caches game configuration in memory. Initial GOG setup therefore requires
Heroic to be stopped and preserves the selected native/Flatpak profile. It sets
`showMangohud`, merging only managed environment keys into each installed GOG
entry's `GamesConfig/ID.json`, retaining runners, prefixes, cloud-save settings
and other environment variables. A constant `MANGOHUD_CONFIGFILE` points to
`GamesConfig/quickshell-performance/ID.conf` inside that profile, readable from
its Flatpak. `MANGOHUD_CONFIG=read_cfg` loads that file. Later Games launches
update only its contents, so a running Heroic client uses current preferences
without reloading its cached configuration. Missing/unconfigured profiles require
setup before applying performance controls. Flatpak setup checks the MangoHud
extension against Heroic's actual runtime branch and offers its interactive
installation in a terminal. These generated performance files are launcher-local
runtime state; Games regenerates them from its own preferences.

Global Tools opens native or Flatpak ProtonPlus. Per-game settings expose real
performance overrides, Epic's runner, preferred-copy selection and checked
installation-folder access, without generic launcher-management shortcuts.
Launched tools use the same detached UWSM lifetime as games.

### itch.io cached library

`itch.py` reads `$XDG_CONFIG_HOME/itch/db/butler.db` (default
`~/.config/itch/db/butler.db`) with read-only SQLite connections. `caves` joins
`games` and `install_locations`; an absolute `custom_install_folder` takes
precedence. Normal folders require an absolute install location and relative
folder without parent traversal. Missing folders are omitted, duplicate installs
collapse to one game, and non-game classifications are excluded. Optional metadata
columns supply descriptions and covers. WAL updates remain visible.

Cached purchases come from `download_keys.game_id/owner_id`; cached bundle games
join `bundle_keys` and `bundle_games`. The adapter selects only `id` and `user_id`
from `profiles`, never `api_key` or any authentication field. Ownership is read
only for a sole local profile; multiple profiles leave purchases unknown rather
than mixing accounts. Viewed games are not purchases. Positive cached ownership
is marked `ownershipCached` with explicit `ownedIds`; absence from a partial cache
never proves non-ownership. Library union/filters accept positive cached purchases
while other providers retain their complete-ownership checks. Missing/unsupported
databases stay unknown. Flatpak itch profiles and website-wide discovery are
outside this adapter's scope.

Numeric IDs identify records. IGDB/manual URLs match a unique canonical
creator/game URL; explicit numeric IDs never fall back to title matching. Only
HTTPS creator subdomains with one game path are accepted, without credentials,
download keys or query strings. Store metadata fills missing description/artwork
before optional IGDB enrichment. itch-only games have no supported NSFW labels.

The launcher prefers updater-stable `~/.itch/itch-setup`, then PATH's `itch` or
`itch-setup`. A bounded `--help` capability check, cached against executable mtime,
detects `--run-game`. Supported versions launch installed games directly through
`itch-setup --appname itch --run-game ID`, retaining itch's target selection and
sandbox behavior while inheriting Games' MangoHud preferences. Older launchers
use `itch://install?game_id=ID&launch` without promising performance controls.
Owned uninstalled games use `itch://install?game_id=ID`; Manage opens
`itch://library/installed`. Actions recheck the current cache and launcher before
handoff. Games never modifies Butler's DB or invokes downloaded payloads itself.

No extra Games credential or private backup path is required. itch's database,
account state, payloads and saves remain launcher-owned. The
`gaming/launchers/itch` module declares AUR's `itch-setup-bin`; opening the installer
initializes the app. See itch's [protocol contract](https://itch.io/docs/itch/integrating/protocol-urls.html)
and Butler's [cave model](https://github.com/itchio/butler/blob/master/database/models/cave.go).

### Native content filtering

`content.py` reads only native classifications: Steam `content_descriptors` 3
(Adult Only Sexual Content) and 4 (Frequent Nudity or Sexual Content), as defined by
[Valve](https://partner.steamgames.com/doc/api/ISteamUGC#EUGCContentDescriptorID),
and GOG's [NSFW store tag](https://www.gog.com/en/games?tags=nsfw).
Missing/malformed labels and unknown descriptor IDs remain unknown; titles,
descriptions, maturity/age ratings, and third-party classifications never
substitute for them. These storefront endpoints are not versioned contracts for
third-party clients and may change independently.

Steam labels come first from the installed client's PICS cache,
`appcache/appinfo.vdf` under each Steam root. It holds `common/content_descriptors`
for owned and viewed apps, and omits the section when an app declares none, as the
store does. Only format v29 (magic
`0x07564429`, string-table keys) is read, bounded to 128 MiB. The app index is
rebuilt when the file's mtime or size changes, and each app's key/values are
parsed on first use. Other apps, an app without `common` data, another format or a
malformed file use `IStoreBrowseService/GetItems` on `api.steampowered.com`:
`content_descriptorids` and `platforms` for up to 100 apps per request, without a
key. Items must identify the requested app; other `success` values (unknown or
region-restricted) stay unknown. Descriptions still come from `appdetails` on
`store.steampowered.com`, so either host can be unreachable without affecting the
other.

GOG labels come from one pass over `GET https://catalog.gog.com/v1/catalog` with
`tags=is:nsfw` (about 1,000 products, 11 pages of 100), without account
credentials; Heroic's caches carry no store tags. The pass is stored as
`gog-nsfw:v1` and a product is NSFW when its ID is listed, so the request count
does not grow with the library. Every listed product must carry the `nsfw` tag
slug: a page that ignored the filter, a malformed page or more than 50 pages fails
the pass, which keeps the previous set. The listing omits secret products (Agony,
for example, is secret and tagged NSFW on its product page), so those count as not
tagged; this is an accepted trade-off for not reading each product. The set renews
after seven days, and library Refresh renews a set older than a day. Until the
first pass completes, GOG games await classification.

Exact store IDs and centralized library matches determine classification,
including manual overrides and GOG slugs resolved against Heroic's product records.
Unresolved slugs, Epic-only games and local files have no supported classification.
A merged game is NSFW when any supported store labels it so, and labelled safe only
when every supported store has a known negative label. This is a store-label filter,
not a claim that unlabelled content is safe.

Each label result carries `pending` (a lookup is due) and `awaiting` (due and never
attempted). With NSFW hidden, QML hides known NSFW games and awaiting ones, so a
new title cannot flash before its first lookup. A label that stays unknown after
an attempt (provider outage, missing product, malformed data) is shown. The game
being viewed is not hidden by an awaiting label, for example after editing its
store link; hiding NSFW removes it as it does a known NSFW selection, and closes
its gallery and dialogs.

`native-content:v1:steam:ID` and `steam-platforms:v1:ID` entries in the existing
SQLite cache last 30 days; stale labels and a stale GOG set still apply while a
refresh is due. Failure markers (`KEY:retry`) store their cooldown: five minutes
after an outage, one day when Steam answers without usable data for that app
(item `success` other than 1). A transport/provider
failure pauses that provider across products, including forced reads:
`steam-store-items` (labels/platforms), `steam-appdetails` (descriptions) and
`gog-content`. Consecutive failures double the pause up to an hour, and a success
clears it, so a long outage costs one probe per hour instead of an 8-second timeout
every five minutes. Products skipped during a pause are recorded as attempted. The
library Refresh action clears the pauses and per-product cooldowns; known labels
are not re-read before they expire.

Listing reads cached and local labels without network locks, through one SQLite
connection per listing; the library computes labels only for the returned page.
`content_rating` takes up to 100 `gameIds` and returns `items`; QML sends up to 25
queued games per request with two requests in flight while visible with filtering
enabled. Each request makes at most one Steam store read per 100 apps; fetches
coalesce through source locks. Changing the NSFW toggle only
refilters the current pages and schedules due labels; it does not refresh launcher
libraries or invalidate saved metadata. Browse generations reject late callbacks
after search or view changes. Hiding stops queued reads; closing terminates the
owned worker as usual.

QML keeps raw pages separate from visible rows, patching identities in place.
The inverse toggle persists as `catalogue/hideNsfw` in `games-ui.ini`. Pagination
uses the provider's raw offset and waits for classification before advancing
through wholly hidden pages. End-of-list checks subtract Qt's mutable content
origin, accounting for rows inserted/removed by classification. Scroll events
start the pagination timer without resetting a pending check, so continuous
motion cannot postpone it indefinitely.
Toggle changes refilter, not reload the catalogue.

### Beat times and artwork

`hltb.py` uses bounded HTTPS reads, browser-compatible auth headers, one auth/search
lock and an in-memory auth token. It discovers a changed search route from
same-origin scripts on failure and retries once. Numeric Steam IDs or a unique
normalized exact title determine automatic matches; edition words and sequel
numbers remain significant. Ambiguous or conflicting results require a manual
HLTB game URL/ID. A direct match reads that game's public page. Positive durations
are seconds converted to hours; missing durations stay unavailable. These are
population estimates, not evidence of completion. HLTB's undocumented interface
can change independently of this repository.

Successful HLTB results persist for 30 days; failed reads retain stale times with
a warning and a five-minute cooldown. Manual HLTB overrides have their own table
and survive metadata refresh. An independent request generation prevents a late
automatic result from replacing a newer manual match. Browse, selection and
hydration generations similarly reject stale results.

`presentation.py` reads Steam's most-recent account (or the sole local account)
for custom grid logos/heroes/covers and local playtime. It does not combine stats
from multiple users. Installed Steam library artwork is tried before public CDN
fallbacks. Local artwork URLs include mtimes; title artwork resets immediately
on selection changes and falls back to text when absent. No SteamGridDB API key
is required for artwork already installed in Steam. Downloaded images use a
Games-owned `ArtworkCache`, reusing the Movies bounded cache implementation;
Movies/Series retain their existing shared cache instance.

Refreshing a game, finishing an install or saving a store match re-hydrates the
selected game; a hydration generation alongside the selection generation lets only
the newest responses apply. Saving a store match keeps the selection, and a
refreshed listing keeps a retained selection in view instead of scrolling back to
the start.

Following the shared header contract, a Browse/Favorites warning (saved results
shown offline or without credentials) appears inline as in Movies and Books.
My Library store problems stay on each store's status tooltip, the setup hint has
its own empty state, and launcher confirmations are routine and not shown.

Hidden pages stop selection debounce, pagination, search and content
classification. In-flight bounded reads may finish without activating the page.
Backdrops/logos stop presenting; popups close. Active torrent imports keep their
monitor intentionally; idle hidden monitoring stops. Closing releases the Games
workers and interrupts in-flight indexing, while qBittorrent retains accepted
downloads. Saved jobs resume when Games reopens. Escape dismisses download
review/popups, gallery, match/uninstall dialog, pickers, search and filters before
hiding the Space. The selected detail tab survives hiding and switching Spaces;
selecting a different game or creating a fresh instance starts on Overview.
The host's top-left X remains reachable.

## Configuration, private data and provisioning

User configuration and state:

- `~/.config/quickshell/desktop/spaces/games/games.json`
- `~/.config/quickshell/desktop/spaces/games/games-ui.ini`
- `~/.local/share/quickshell/desktop/spaces/games/library.sqlite`

The JSON game's keys are `igdb_client_id`, `igdb_client_secret`, optional
`steam_api_key`, `steam_id` and `proton_path`. With any credential or
`proton_path` set, the file (or the private-checkout file it links to) must be
owned by the user with mode 0600, as Movies requires for `media.json`;
otherwise the whole file is unused and `configError` replaces the setup hint.
The reader keys its cache on mode and owner as well as mtime, so `chmod` takes
effect at once. qBittorrent connection settings
are shared by all Spaces at `~/.config/quickshell/desktop/integrations/torrents.json`
; see [integration ownership](../../integrations/ARCHITECTURE.md#qbittorrent).
Missing keys disable only the
corresponding provider. The file reloads on mtime changes. Provider failures are
sanitized; keys, sessions and response bodies are not logged to QML. Private
configuration/database files are 0600 and owner directories 0700.

SQLite contains personal favorites, launch settings, store/HLTB matches, saved metadata, imported
file records and torrent jobs. Portable backups exclude the large game payloads
and `prefixes/egs/`, which can contain Wine saves. Those need a separate backup or
mounts at the same paths. Artwork caches live under
`$XDG_CACHE_HOME/quickshell/desktop/spaces/games/artwork/`; they are regenerable.
Steam installs, account credentials, local custom art and Legendary authentication
stay owned by their launchers. Fresh installs must sign in again and reinstall or
remount games. `proton_path` is machine-specific and must point to an installed
Proton if supplied.
