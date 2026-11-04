# Contributing to Ada Note

Bug reports, feature requests, documentation, and pull requests are welcome.

## Report a bug

Search [existing issues](https://github.com/opendream/ada-note/issues) first. If the problem is new, open an issue with:

- What you expected and what happened
- Steps to reproduce
- Your macOS version and the Ada Note commit you built
- The status line from the window, with names and transcript text removed

## Suggest a change

Describe the problem you want to solve. A small fix can go straight to a pull request. For a change to recording, the note, or where transcript text is sent, open an issue first.

## Work on a change

1. Fork the repository and clone your fork.
2. Create a branch: `git switch -c your-change`.
3. Build with `swift test` and, for app changes, `./scripts/bundle-app.sh`.
4. Open a pull request against `main`.

Keep the change focused. `Sources/MeetingCore` should stay testable without a microphone, a live CLI, or the network. Do not add a path from your own machine.

## License

Ada Note uses the [MIT License](LICENSE). Contributions should be compatible with it.
