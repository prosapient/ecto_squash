defmodule EctoSquash.Postgres do
  @moduledoc """
  Schema dumping code based on Ecto.Adapters.Postgres with `schema_migrations`
  table excluded.
  """

  def structure_dump(default, config) do
    table = config[:migration_source] || "schema_migrations"

    with {:ok, versions} <- select_versions(table, config),
         {:ok, path} <- pg_dump(default, config, table),
         do: append_versions(table, versions, path)
  end

  defp select_versions(table, config) do
    case run_query(~s[SELECT version FROM public."#{table}" ORDER BY version], config) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, %{postgres: %{code: :undefined_table}}} -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp pg_dump(default, config, exclude_schema) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    File.mkdir_p!(Path.dirname(path))

    case run_with_cmd("pg_dump", config, [
           "--file",
           path,
           "--schema-only",
           "--no-acl",
           "--no-owner",
           "--exclude-schema",
           exclude_schema,
           config[:database]
         ]) do
      {_output, 0} ->
        {:ok, path}

      {output, _} ->
        {:error, output}
    end
  end

  defp append_versions(_table, [], path) do
    {:ok, path}
  end

  defp append_versions(table, versions, path) do
    sql = Enum.map_join(versions, &~s[INSERT INTO public."#{table}" (version) VALUES (#{&1});\n])

    File.open!(path, [:append], fn file ->
      IO.write(file, sql)
    end)

    {:ok, path}
  end

  ## Helpers

  defp run_query(sql, opts) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    opts =
      opts
      |> Keyword.drop([:name, :log, :pool, :pool_size])
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:max_restarts, 0)

    task =
      Task.Supervisor.async_nolink(Ecto.Adapters.SQL.StorageSupervisor, fn ->
        {:ok, conn} = Postgrex.start_link(opts)

        value = Postgrex.query(conn, sql, [], opts)
        GenServer.stop(conn)
        value
      end)

    timeout = Keyword.get(opts, :timeout, 15_000)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, error}} ->
        {:error, error}

      {:exit, {%{__struct__: struct} = error, _}}
      when struct in [Postgrex.Error, DBConnection.Error] ->
        {:error, error}

      {:exit, reason} ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}

      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end

  defp run_with_cmd(cmd, opts, opt_args) do
    unless System.find_executable(cmd) do
      raise "could not find executable `#{cmd}` in path, " <>
              "please guarantee it is available before running ecto commands"
    end

    env = [{"PGCONNECT_TIMEOUT", "10"}]

    env =
      if password = opts[:password] do
        [{"PGPASSWORD", password} | env]
      else
        env
      end

    args = []
    args = if username = opts[:username], do: ["-U", username | args], else: args
    args = if port = opts[:port], do: ["-p", to_string(port) | args], else: args

    host = opts[:socket_dir] || opts[:hostname] || System.get_env("PGHOST") || "localhost"

    if opts[:socket] do
      IO.warn(
        ":socket option is ignored when connecting in structure_load/2 and structure_dump/2," <>
          " use :socket_dir or :hostname instead"
      )
    end

    args = ["--host", host | args]
    args = args ++ opt_args
    System.cmd(cmd, args, env: env, stderr_to_stdout: true)
  end
end
