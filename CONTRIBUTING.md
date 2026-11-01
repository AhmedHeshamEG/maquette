# Contributing

Thank you for wanting to help. A few things first.

## Before you start

- **Bugs**: open an issue with what you did, what you expected and what happened. A screen recording helps most.
- **Ideas**: open an issue before writing code. Maquette's layout is deliberately small; a feature has to find a home
  that already exists ([docs/LAYOUT.md](docs/LAYOUT.md)).
- **Pull requests**: one change per pull request, with a test. CI must be green (lint, the Core tests on Linux, the
  render tests and the UI tests).

## The contributor agreement

Maquette is licensed under the GPL v3.0, and the official app is published by its author on the App Store. Apple's
terms and the GPL don't mix for anyone but the code's owner, so the author must keep the right to publish every part
of the app. By opening a pull request you agree that:

1. the contribution is your own work, and you have the right to give it;
2. it is licensed to everyone under the GPL v3.0, like the rest of the code; and
3. you also grant Ahmed Hesham (studio h.) a perpetual, worldwide, royalty-free licence to use, change and publish it
   under any terms, including in the official app on the App Store.

You keep the copyright of what you wrote.

## Working on the code

See [Build from source](README.md#build-from-source). Core tests run in Docker on any computer; the app builds on CI.
Swift is formatted by SwiftFormat and linted by SwiftLint `--strict`; run both before you push.
