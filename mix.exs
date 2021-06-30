defmodule EctoSquash.MixProject do
  use Mix.Project

  @github_url "https://github.com/prosapient/ecto_squash"

  def project do
    [
      app: :ecto_squash,
      description: "A Mix task intended to streamline migration squashing.",
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @github_url,
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.6.2"},
      {:postgrex, "~> 0.15.0 or ~> 1.0", optional: true},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      links: %{"GitHub" => @github_url},
      licenses: ["Apache-2.0"]
    ]
  end
end
