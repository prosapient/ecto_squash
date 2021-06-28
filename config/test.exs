import Config

config :ecto_squash, Mix.Tasks.Ecto.SquashTest.Repo,
  priv: "tmp",
  database: "squash_test",
  username: "postgres",
  password: "postgres"
