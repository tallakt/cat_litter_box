defmodule CatLitterBox.MixProject do
  use Mix.Project

  def project do
    [
      app: :cat_litter_box,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [test: "test --no-start"]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CatLitterBox.Application, []}
    ]
  end

  defp deps do
    [
      {:xignal, git: "git@github.com:tallakt/xignal.git", branch: "main"},
      {:websockex, "~> 0.5"},
      {:req, "~> 0.5"}
    ]
  end
end
