# Security

Beam has Accessibility and Automation access, so security reports matter.

Please report vulnerabilities privately to **support@beamlauncher.app** (or GitHub's private vulnerability reporting, if enabled), not in a public issue. Include the Beam and macOS versions and steps to reproduce. You'll get a reply as soon as possible, and credit in the changelog if you'd like.

Beam has no telemetry. It makes two kinds of request: the optional update check (Sparkle; it asks first on the 2nd launch, fetches `beamlauncher.app/appcast.xml` and downloads from `downloads.beamlauncher.app`, and sends no system profile) and the license check (only when you enter a key in the "Enter License Key…" menu item / "Beam Launcher License" window). A `BEAM-` key from beamlauncher.app is sent to `beamlauncher.app/api/validate` when you enter it and then about once a month at launch, so a refunded key stops counting; that key is kept in UserDefaults for the re-check. An older Lemon Squeezy key is sent to `api.lemonsqueezy.com` once, and never again. Chrome favicons are read from Chrome's local cache. The supporter's email returned by the license check is stored in plain UserDefaults (readable by processes running as your user) and is only shown in About.
