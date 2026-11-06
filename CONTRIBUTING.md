# Contributing

Thank you for wanting to help. A few things first.

## Before you start

- **Bugs:** open an issue with what you did, what you expected and what happened. A screen recording helps most.
- **Fixes, translations and ports:** go ahead, one change per pull request, with a test. CI must be green (lint, the
  Core tests on Linux, the render tests and the UI tests).
- **New features:** open an issue first and wait for a yes before you write code. After 1.0 the layout is frozen
  ([docs/LAYOUT.md](docs/LAYOUT.md)), so most "add a button" ideas will get a kind no.
- **Speed:** issues are read once a week. I'm one person, so be patient with me and I'll be patient with your commit
  messages.

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
