# Changelogs - v2.9.0-unreleased

### ✨ *New Features & Enhancements*

#### 🧩 CloudStream Extensions
- **CloudStream (.cs3) extensions on every platform** – Install and run CloudStream extensions on Android, iOS, macOS, Windows and Linux. Their providers appear on Home, in search and in the provider list.
- **Repositories** – Add a repository by its URL (repo.json or plugins.json), a cloudstreamrepo:// link or a shortcode. MegaRepo is supported, Check Updates shows what changed, and each extension can be updated or removed.
- **Extension settings** – An extension's own settings open in SkyStream on every platform and take effect without restarting the app. Extensions' own dialogs and pages open in SkyStream too.
- **Full-screen extension windows** – Extensions that open a full-screen page, games included, work on every platform, and Back closes them.
- **One switch** – Turn CloudStream off entirely in Settings: no extension loads and their providers are hidden everywhere. Nothing is uninstalled.

#### 🛡️ Bot Checks (Cloudflare and Others)
- **SkyStream's own browser engine** – Bot checks are now cleared in each platform's own browser engine on every platform, Linux included, instead of the old WebView plugin.
- **Checks cleared for you** – SkyStream ticks the checkbox itself where it can. When a site needs you, its check opens right where you are.
- **One check per site** – A site cleared once works for SkyStream plugins, CloudStream extensions, Nuvio scrapers and Stremio add-ons alike, and stays cleared across restarts until the site asks again.
- **See each site's check** – Search, Explore and Home show the sites that need a check, with Verify for one site or all of them. A site can be set not to open its check by itself.
- **Clearer reasons** – A site that blocks VPNs, keeps asking, can't be reached, or needs a newer Android System WebView says so.
- **Moved sites followed** – When a site moves to a new address, SkyStream follows it.
- **More check vendors** – DDoS-Guard and other vendors are handled, and a captcha an extension asks for is shown to you to solve.

#### 🔎 Search
- **Universal search** – One search bar for SkyStream, CloudStream, Stremio and Nuvio: a section for each Stremio add-on and one for Nuvio, with every result tagged with where it came from.
- **Search in every language** – Titles are found whatever their accents, letter forms, digits or spacing: "pokemon" finds "Pokémon", and Arabic, Persian, Urdu, Hebrew, Turkish and Indian-language titles match the way they are typed. Japanese, Chinese and Thai titles written without spaces are found by any part of the name, and Korean ones with or without spaces. A provider whose titles are all in another script shows them instead of nothing (PR #127 by @1eren0).

#### 🎬 Player & Playback
- **Volume and brightness swipes like VLC** – Both follow your finger with no lag. The volume boost above 100% shows in orange, and a swipe from below 100% stops there first: swipe up again to go past it.
- **Volume keys** – On Android the volume keys change the video's volume even while it is paused. On a desktop keyboard, holding a volume key keeps stepping.
- **Orientation** – Leaving the player returns to your device's orientation, with the rotation lock respected.
- **New player controls** – Frosted controls, and one Options button for sources, audio, subtitles and episodes. The volume and episode buttons can be hidden in Player Controls (PR #121 by @likhithkrishna1103-tech).
- **Held keys** – Holding left or right on a keyboard or a TV remote, or J/L on a keyboard, keeps seeking (PR #121 by @likhithkrishna1103-tech).

#### 🖥️ Interface
- **Navigation bar** – A new frosted navigation bar on phones (PR #121 by @likhithkrishna1103-tech).

#### 🔐 Accounts
- **MyAnimeList and AniList sign-in inside SkyStream** – Signing in happens in the app, on every platform.
- **Trakt's new sign-in** – Trakt now signs in through Trakt's new sign-in page. If you were signed in to Trakt before, you may be asked to connect once more.

---

### 🐞 *Bug Fixes & System Stability*
- 🛠️ **Fixed: lines from a subtitle file flickered** – They no longer blink off and on or flash an earlier line, worst on HLS streams, and a short seek back shows the line it lands in (PR #132 by @1eren0).
- 🛠️ **Fixed: some repository short links and shortcodes didn't add their repository** – Links that pass through a redirect page now work, a shortcode works in any letter case ("Universe" adds SkyStream's own collection), and the add-repository boxes no longer autocorrect what you type (PR #129 by @1eren0).
- 🛠️ **Fixed: another repository could replace an extension with its own code** – An extension now updates only from the repository it was installed from, and only to the extension that repository lists. To move an extension to another repository, use Install from this repository in that repository's list.
- 🛠️ **Fixed: on TV, a keyboard closed with Back couldn't be opened again from its text field** – OK on the field opens it again, and Down moves on from the field to what is below it, in search on Home, Explore and the Search tab and in the text boxes of dialogs (PR #128 by @1eren0).
- 🛠️ **Fixed: on some low-memory Google TV devices, the on-screen keyboard showed but typed nothing into SkyStream.**
- 🛠️ **Fixed: on iPad, a video's sound stopped a second in** – The video went on playing silently until an audio track was picked again.
- 🛠️ **Fixed: leaving the player could freeze the app on iPad.**
- 🛠️ **Fixed: brightness swipes lagged on iPhone and iPad** – The brightness changed only after the finger stopped.
- 🛠️ **Fixed: the app could open in landscape after leaving the player.**
- 🛠️ **Fixed: on Linux, the screen stopped going to sleep after playback** until SkyStream was closed.
- 🛠️ **Fixed: on Linux, opening some streams, such as Internet Archive's, froze the app.**
- 🛠️ **Fixed: on TV, the search screen's scope selector and first result ignored the D-pad.**
- 🛠️ **Fixed: on Windows, macOS and Linux, Clear cache could delete other apps' temporary files** – It now clears only SkyStream's own.
- 🛠️ **Fixed: the Linux .deb didn't install the VLC and WebKitGTK it needs** – apt now installs them with SkyStream.
- 🛠️ **Fixed: the Linux x64 build didn't start on Ubuntu 22.04, Debian 12 and other systems older than Ubuntu 24.04** (PR #121 by @likhithkrishna1103-tech).


### ⚙️ Improvements
- 🚀 **Linux AppImage** for x64 and arm64, beside the .deb and the archive (PR #125 by @vivin-neelankavil).
- 🚀 Updated to Flutter 3.47.7, Android Gradle Plugin 9.1.1 and VLC 3.0.24.
- 🚀 Fewer third-party plugins: flutter_inappwebview, screen_brightness and flutter_volume_controller are gone, replaced by SkyStream's own.
- 🚀 Thousands of new automated tests, and checks that run the app on every platform.
