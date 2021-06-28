defmodule Mix.Tasks.Ecto.SquashTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Squash, only: [run: 1]

  @fixtures __DIR__ <> "/../../fixtures/"
  @migrations_path "#{tmp_path()}/migrations"

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :ecto_squash,
      adapter: Ecto.Adapters.Postgres
  end

  setup do
    Mix.Task.run("ecto.create", ["-r", to_string(Repo)])
    File.rm_rf!(unquote(tmp_path()))
    File.mkdir_p!(@migrations_path)
    File.cp_r!(@fixtures <> "migrations", @migrations_path)
    :ok
  end

  test "generates new migrations" do
    [squash, checker] = run(["-y", "-r", to_string(Repo), "--to", "20210505120132"])
    assert Path.dirname(squash) == Path.dirname(checker)
    assert Path.dirname(checker) == @migrations_path

    assert_file(squash, fn file ->
      assert file == fixture("20210505120132_apply_squashed_migrations.exs")
    end)

    assert_file(checker, fn file ->
      assert file == fixture("20210505120133_ensure_migrated_squash.exs")
    end)

    # Skip dump header containing tool/DB versions.
    data_range = 6..-1

    dump_data =
      File.stream!(Path.dirname(squash) <> "/structure.sql")
      |> Enum.slice(data_range)

    fixture_data =
      File.stream!(@fixtures <> "/structure.sql")
      |> Enum.slice(data_range)

    assert dump_data == fixture_data
  end

  defp fixture(path) do
    File.read!(@fixtures <> path)
  end

  test "custom migrations_path" do
    dir = Path.join([tmp_path(), "custom_migrations"])
    File.mkdir_p!(dir)

    [path, _path] =
      run(["-y", "-r", to_string(Repo), "--migrations-path", dir, "--to", "20210505120132"])

    assert Path.dirname(path) == dir
  end

  test "raises when missing mandatory option `--to`" do
    assert_raise Mix.Error, fn -> run(["-r", to_string(Repo)]) end
  end
end
