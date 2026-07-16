# open_pg_tde documentation

`open_pg_tde` is an open source PostgreSQL extension that provides Transparent Data Encryption (TDE) to protect data at rest. It ensures that the data stored on disk is encrypted, and that no one can read it without the proper encryption keys, even if they gain access to the physical storage media.

`open_pg_tde` is an open fork of Percona's `pg_tde`, maintained by [Command Prompt, Inc.](https://commandprompt.com/) It runs on upstream PostgreSQL 16 and later: you apply the `open_pg_tde` core patch to a PostgreSQL source tree, build it with the hooks enabled, and build the extension against that install. See [Install from source](install-from-source.md).

<div data-grid markdown><div data-banner markdown>

### :material-progress-download: Installation guide { .title }

Get started quickly with the step-by-step installation instructions.

[How to install `open_pg_tde` :material-arrow-right:](install.md){ .md-button }

</div><div data-banner markdown>

### :rocket: Features { .title }

Explore what features the `open_pg_tde` extension brings to PostgreSQL.

[Check what you can do with `open_pg_tde` :material-arrow-right:](features.md){ .md-button }

</div><div data-banner markdown>

### :material-cog-refresh-outline: Architecture { .title }

Understand how `open_pg_tde` integrates into PostgreSQL. Learn how keys are managed, how encryption is applied, and how the design ensures performance and security.

[Check what’s under the hood for `open_pg_tde` :material-arrow-right:](architecture/overview.md){.md-button}

</div><div data-banner markdown>

### :loudspeaker: What's new? { .title }

Learn about the releases and changes in `open_pg_tde`.

[Check what’s new in the latest version :material-arrow-right:](release-notes/{{latestreleasenotes}}.md){.md-button}
</div>
</div>
