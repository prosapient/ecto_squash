defmodule Support.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :ecto_squash,
    adapter: Ecto.Adapters.Postgres
end
