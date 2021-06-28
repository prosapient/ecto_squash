defmodule Mix.Tasks.Ecto.SquashTest.Repo.Migrations.EnsureMigratedSquash do
  use Ecto.Migration
  alias Ecto.Migration.SchemaMigration

  def up do
    needed_migrations = MapSet.new(
[20180103194816, 20180122130454, 20180122130942, 20210505120132]
    )
    repo = Mix.Tasks.Ecto.SquashTest.Repo
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
