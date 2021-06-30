# Ecto Squash

![Package version](https://img.shields.io/hexpm/v/ecto_squash?style=plastic)

This is a Mix task intended to streamline migration squashing. It replaces
several migrations with a SQL-based migration, which applies schema, and
a second one for making sure that all of the squashed migrations has been
applied and nothing else, before migrating further.
Note: only PostgreSQL is supported yet.

## Installation

The package can be installed by adding `ecto_squash` to your list of
dependencies in `mix.exs` (replace `x.x.x` with current version in the badge):

```elixir
def deps do
  [
    {:ecto_squash, "~> x.x.x", only: [:dev]}
  ]
end
```

## Examples

Squash migrations upto and including 20210601033528 into a single one:

      mix ecto.squash --to 20210601033528
      mix ecto.squash --to 20210601033528 -r Custom.Repo

The repository must be set under `:ecto_repos` in the
current app configuration or given via the `-r` option.

SQL migration will have a filename prefixed with timestamp of the latest
migration squashed. That way it won't be applied if squashed migration is
already there. Another generated migration will have a +1 second
timestamp.

By default, the migration will be generated to the
"priv/YOUR_REPO/migrations" directory of the current application
but it can be configured to be any subdirectory of `priv` by
specifying the `:priv` key under the repository configuration.

## Command line options

* `--to VERSION` - squash migrations upto and including VERSION
* `-y`, `--yes` - migrate to specified version, remove squashed migrations
and migrate to latest version without asking to confirm actions
* `-r REPO`, `--repo REPO` - the REPO to generate migration for
* `--migrations-path PATH` - the PATH to run the migrations from,
  defaults to `priv/repo/migrations`
* `--no-compile` - does not compile applications before running
* `--no-deps-check` - does not check dependencies before running

## Configuration

If `:ecto_sql` app configuration specifies a custom migration module,
the generated migration code will use that rather than the default
`Ecto.Migration`:

      config :ecto_sql, migration_module: MyApplication.CustomMigrationModule
