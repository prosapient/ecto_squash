defmodule Mix.Tasks.Ecto.Squash do
  use Mix.Task

  require Logger
  import Mix.Generator
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Squashes several migrations into one"

  @aliases [
    r: :repo,
    t: :to,
    y: :yes
  ]

  @switches [
    to: :integer,
    yes: :boolean,
    repo: [:string, :keep],
    migrations_path: :string,
    no_compile: :boolean,
    no_deps_check: :boolean
    # XXX: No support for prefix yet.
    # prefix: :string,
  ]

  @moduledoc """
  Replaces several migrations with a SQL-based migration, which applies schema,
  and a second one for making sure that all of the squashed migrations has been
  applied and nothing else, before migrating further.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  ## Examples

  Squash migrations upto and including 20210601033528 into a single one:

      mix ecto.squash --to 20210601033528
      mix ecto.squash --to 20210601033528 -r Custom.Repo

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

  If :ecto_sql app configuration specifies a custom migration module,
  the generated migration code will use that rather than the default
  `Ecto.Migration`:

      config :ecto_sql, migration_module: MyApplication.CustomMigrationModule

  """

  @impl true
  def run(args) do
    [repo, opts] = parse_args(args)

    # Start ecto_sql explicitly before as we don't need
    # to restart those apps if migrated.
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    ensure_repo(repo, args)

    to = opts[:to]

    migrate_opts =
      ["-r", inspect(repo)] ++
        if path = opts[:migrations_path], do: ["--migrations-path", path], else: []

    if yes?(opts, "Migrate to #{to}? (Mandatory to proceed)") do
      migrate_to(repo, migrate_opts, to)
    else
      Logger.warn("Need to apply migrations to proceed.")
      exit(:normal)
    end

    migrations = get_migrations(repo)

    path = opts[:migrations_path] || Path.join(source_repo_priv(repo), "migrations")
    unless File.dir?(path), do: create_directory(path)

    remove_squashed_migrations(path, migrations, opts)
    squash_path = create_squash_migration(path, repo, to)
    EctoSquash.Postgres.structure_dump(path, repo.config())
    checker_path = create_checker_migration(path, repo, migrations, to)

    if yes?(opts, "Do you want to apply all migrations?") do
      Mix.Task.run("ecto.migrate", migrate_opts)
    end

    [squash_path, checker_path]
  end

  defp parse_args(args) do
    repo =
      case parse_repo(args) do
        [repo] ->
          repo

        [repo | _] ->
          Mix.raise(
            "repo ambiguity: several repos available - " <>
              "please specify which repo to use with -r, " <>
              "e.g. -r #{inspect(repo)}"
          )
      end

    case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
      {opts, []} ->
        opts[:to] ||
          Mix.raise(
            "`--to` option is mandatory, which is stupid and hopefully will be fixed, " <>
              "got: #{inspect(Enum.join(args, " "))}"
          )

        [repo, opts]

      {_, _} ->
        Mix.raise(
          "ecto.squash supports no arguments, " <>
            "got: #{inspect(Enum.join(args, " "))}"
        )
    end
  end

  defp yes?(opts, question) do
    opts[:yes] || Mix.shell().yes?(question)
  end

  defp migrate_to(repo, migrate_opts, to) do
    migrate_opts_to = migrate_opts ++ ["--to"]

    # Migrate forward if we're behind.
    Mix.Task.run("ecto.migrate", migrate_opts_to ++ [Integer.to_string(to)])

    # Migrate backwards if we're ahead.
    # XXX: ecto.rollback rolls back migration specified with `--to` as well.
    # Offset index +1 to keep that migration.
    migrations = get_migrations(repo)
    index = migrations |> Enum.find_index(fn {_, id, _} -> id == to end)

    case Enum.at(migrations, index + 1) do
      {_dir, next_migration_id, _name} ->
        Mix.Task.run("ecto.rollback", migrate_opts_to ++ [Integer.to_string(next_migration_id)])

      # Migration is nil when squashing all migrations.
      nil ->
        nil
    end
  end

  defp get_migrations(repo) do
    {:ok, migrations, _apps} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.migrations(repo)
      end)

    migrations
  end

  defp migration_module do
    case Application.get_env(:ecto_sql, :migration_module, Ecto.Migration) do
      migration_module when is_atom(migration_module) -> migration_module
      other -> Mix.raise("Expected :migration_module to be a module, got: #{inspect(other)}")
    end
  end

  defp remove_squashed_migrations(path, migrations, opts) do
    rm_list =
      migrations
      |> Enum.map(fn {_dir, id, _name} -> id end)
      |> Enum.filter(fn id -> id <= opts[:to] end)
      |> Enum.flat_map(fn id -> Path.wildcard(Path.join(path, "#{id}_*.exs")) end)

    if yes?(
         opts,
         "Remove squashed migrations upto and including #{opts[:to]} (#{length(rm_list)})?"
       ) do
      Enum.each(rm_list, fn path -> File.rm!(path) end)
    end
  end

  defp create_squash_migration(path, repo, to) do
    # ID matches that of the last migration squashed to prevent newly created
    # migration from being applied, since all migrations it contains
    # are already applied.
    file = Path.join(path, "#{to}_apply_squashed_migrations.exs")
    assigns = [mod: Module.concat([repo, Migrations, SquashMigrations]), repo: repo]
    create_file(file, sql_migration_template(assigns))
    file
  end

  defp create_checker_migration(path, repo, migrations, to) do
    file = Path.join(path, "#{to + 1}_ensure_migrated_squash.exs")

    ids =
      migrations
      |> Enum.filter(fn {dir, _id, _name} -> dir == :up end)
      |> Enum.map(fn {_dir, id, _name} -> id end)
      |> Enum.sort()

    assigns = [
      mod: Module.concat([repo, Migrations, EnsureMigratedSquash]),
      repo: repo,
      migration_ids: ids
    ]

    create_file(file, checker_migration_template(assigns))
    file
  end

  embed_template(:sql_migration, """
  defmodule <%= inspect @mod %> do
    use <%= inspect migration_module() %>

    def up do
      repo = <%= inspect @repo %>
      {:ok, _path} = repo.__adapter__.structure_load(__DIR__, repo.config())
    end
  end
  """)

  embed_template(:checker_migration, ~S"""
  defmodule <%= inspect @mod %> do
    use <%= inspect migration_module() %>
    alias Ecto.Migration.SchemaMigration

    def up do
      needed_migrations = MapSet.new(
  <%= inspect @migration_ids, limit: :infinity, pretty: true %>
      )
      repo = <%= inspect @repo %>
      # XXX: No support for prefix yet.
      {migration_repo, query, all_opts} = SchemaMigration.versions(repo, repo.config(), nil)
      has_migrations = migration_repo.all(query, all_opts)
                       |> MapSet.new()
      if needed_migrations != has_migrations do
        raise "Missing migrations: #{inspect MapSet.difference(needed_migrations, has_migrations)}
  extra migrations: #{inspect MapSet.difference(has_migrations, needed_migrations)}"
      end
    end

    def down do
    end
  end
  """)
end
