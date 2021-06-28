defmodule Pt.Repo.Migrations.DropEducations do
  use Ecto.Migration

  def up do
    drop_if_exists table("teams")
  end

  def down, do: nil
end
