# Contributing to Beam

Thanks for helping. Beam is a one-person project, so this page is mostly about keeping things manageable.

## Reporting a bug
Use the bug report template. Most "Beam can't find my windows/tabs" reports come down to permissions, so check first:
- **Windows:** System Settings → Privacy & Security → Accessibility → Beam is on.
- **Chrome tabs:** System Settings → Privacy & Security → Automation → Beam → Google Chrome is on.

## Asking for a feature
Read [docs/product.md](docs/product.md) first. Beam is deliberately narrow: apps, windows, Chrome tabs and tab groups. File search, calculators, web search and plugins are out of scope, and requests for them will be closed.

## Pull requests
- **Open an issue before a pull request** and wait for a go-ahead. Unrequested PRs may be closed, however good they are.
- Keep PRs small and focused: bug fixes, compatibility fixes, small polish.
- Read [docs/architecture.md](docs/architecture.md) and [docs/gotchas.md](docs/gotchas.md), then run `make test` and the manual checklist in [docs/testing.md](docs/testing.md).
- Sign off your commits (`git commit -s`) to certify the [Developer Certificate of Origin](https://developercertificate.org): you wrote the change or have the right to submit it.
- By submitting a PR you license your contribution under GPL-3.0, like the rest of Beam, and also grant the author the right to license it under other terms, including GPL-3.0 together with a commercial license. This keeps future relicensing possible.

## Building
`make run` builds `build/Beam.app` with an ad-hoc signature and launches it. You'll need to grant Accessibility to your own build.
