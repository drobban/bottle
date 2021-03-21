defmodule Plot.MixProject do
  use Mix.Project

  def project do
    [
      app: :plot,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Plot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gnuplot, "~> 1.20.320"},
      {:phoenix_pubsub, "~> 2.0"},
      {:decimal, "~> 2.0"},
      {:deque,
       git: "https://github.com/drobban/deque.git",
       ref: "49076ecb0ea6283577edcb008cdf185dfb4a3f54"},
      {:streamer, in_umbrella: true}
    ]
  end
end
