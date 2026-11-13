# Release notes

Each new versioned GitHub release needs a human-written Markdown file at
`docs/releases/vX.Y.Z.md`. The tagged commit must contain that file. CI uses it
as the GitHub release body. The `update-feed` prerelease is a Sparkle feed container.

1. Identify the previous public version and the exact release candidate. Review
   their commit range and diff, then check the resulting behavior against the
   available verification.
2. Write in English for people using Quota Rail. Lead with what they can now do
   or what works better. Include an upgrade step or known limitation when it
   affects them. Mention development changes separately when useful to contributors.
3. Review the notes with the candidate. Use short bullets and omit empty sections,
   commit prefixes, and internal details that do not affect the reader.
4. Include the notes in the commit before the authorized tag push. CI requires
   a non-empty file when it creates a versioned release. A feed retry for an
   existing release uses its published ZIP and keeps the existing release body.

See the [README](../README.md#development) for packaging and the
[engineering guidelines](GUIDELINES.md) for update verification.
