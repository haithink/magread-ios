# Repository maintenance

- Keep this repository independent from the Android, desktop, and Chrome repositories.
- Update CHANGELOG.md in the same commit for user-visible changes. Keep version fields in project.yml and SettingsView.swift consistent.
- Do not commit imported books, reading data, credentials, signing certificates, or provisioning profiles.
- All API keys must stay in Keychain; Codable configuration must exclude apiKey.
- Keep AI generation cancellable with progress. Do not add unbounded retries or enable reasoning by default.
- Use synthetic publications in tests. Run the GitHub Actions iOS test/build workflow for Swift changes when local Xcode is unavailable.
- Do not claim on-device validation unless a real device was tested.
