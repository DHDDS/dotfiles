# Games

Open **Spaces → Games** for Steam/Epic/GOG/itch.io libraries, IGDB discovery, favorites,
ProtonDB ratings, title artwork, playtime and HowLongToBeat estimates.
Installed Steam games and public store descriptions work without API keys.

The header cog opens **Games settings**, with Performance, store connections and
Tools. Choose an overlay, position, size and frame limit; library games have
**Settings** for overrides, a preferred store copy, reset and installation
folders. Frame limiting also works with the overlay hidden. Changes apply to
the next game launch through Games. Proton selection is available for Epic;
**Tools → ProtonPlus** manages installed runners and Steam compatibility settings.

Enable performance controls on the Steam and GOG settings pages with Steam or
Heroic closed. Reopen the launcher afterwards; subsequent preference changes
need no launcher restart. Repeat Steam setup after adding new Steam games.

The NSFW filter uses Steam/GOG labels. Unlabelled games and GOG's unlisted
products can remain visible; the filter is not a complete content classification.
See [classification details](ARCHITECTURE.md#native-content-filtering).

Configure `~/.config/quickshell/desktop/spaces/games/games.json` using
[games.example.json](games.example.json); with credentials or `proton_path` it
must be private (`chmod 600`), or Games ignores it and says why. A Twitch
application's `igdb_client_id` and `igdb_client_secret` enable Browse. Optional
`steam_api_key` and 17-digit `steam_id` enable ownership checks for a public
Steam profile. Use **Settings → Epic Games → Connect Epic**, or `legendary auth`;
the Legendary module
supplies its launcher and UMU. Steam and Legendary accounts require sign-in
after a fresh installation. Epic purchases appear after **Refresh**; Games
re-reads Epic ownership every few hours and keeps the saved list while Epic is
unreachable. After an uninstall, the store button updates once the launcher
finishes. Epic installations show progress on the store button and speed/ETA
below it; the notifications bell lists tracked installs and the selected game's
torrent downloads. Downloads continue when Games
closes, and reopening restores their progress. Click Install again to retry a
failed download.

For GOG, enable the `gaming/launchers/heroic` module, sign into GOG in Heroic and
refresh its library, then refresh Games. Native and Flatpak Heroic are supported;
Heroic supplies GOGdl, so no additional Python library or GOG API key is needed.
Install opens Heroic's confirmation; play uses its existing Wine/Proton settings
and cloud-save support. Use **Manage in Heroic** for updates and uninstalling.
Refresh Heroic first when purchases or installations change; Games reads its
cached library and does not sign into GOG itself.

For itch.io, the `gaming/launchers/itch` module supplies the installer for the
[itch desktop app](https://itch.io/app). Sign in and refresh its library, then
refresh Games. Cached purchases and bundle games appear alongside installed
games in My Library. Install opens itch's confirmation; **Manage in itch** handles
updates and uninstalling. Current itch versions launch installed games directly,
with performance preferences; older versions use the app's launch confirmation
and need updating for performance controls. Games uses itch's local cache, so
purchases missing there require a refresh in itch first.

Steam's custom title/hero artwork takes priority. When HowLongToBeat has no match,
click its clock to enter a game link or ID. Estimates
and descriptions stay available offline after their first successful lookup.

Browse's **Find** tab uses qBittorrent search and imports completed game files;
it is hidden for library games. Use the game's
folder button to open its imported files.
Configure the shared `~/.config/quickshell/desktop/integrations/torrents.json` using the
[connection example](../../integrations/torrents.example.json); the managed local client
only needs `{"url":"http://127.0.0.1:8080"}`; keep the file mode 0600 if you add a
password or API key. Imported archives/installers open in
the file manager; they are never automatically executed.

Game files, Wine prefixes,
saves, Heroic settings and custom Steam artwork need their own backup. See
[architecture](ARCHITECTURE.md) for storage, provider and lifecycle details.
