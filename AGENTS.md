# Cross-platform parity

- Maintain 100% feature and UI parity between the macOS and Windows apps. Implement every user-facing feature, setting, behavior, state, and localization change on both platforms in the same changeset unless the task is explicitly platform-specific.
- When platform conventions or capabilities differ, implement the closest native equivalent on each platform and keep the user-visible behavior aligned.
- Validate changes on both platforms, using CI when the current development machine cannot run one platform locally.
