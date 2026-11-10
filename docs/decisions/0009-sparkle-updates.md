# 0009: Sparkle for updates

Beam is distributed directly, so it needs its own updater. Sparkle 2 with `SPUStandardUpdaterController`, EdDSA-signed appcast at `https://beamlauncher.app/appcast.xml`. Sparkle's default automatic-check prompt is kept (asks the user on the second launch) rather than silently checking.

Sparkle's XPC services are kept and signed even though Beam is not sandboxed, so enabling the sandbox later needs no packaging change. The experimental sandbox build embeds the framework (it must load) but never starts the updater. Release signing is done by hand, inside out, not with `--deep`.
