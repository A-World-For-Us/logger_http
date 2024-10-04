defmodule LoggerHTTP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/A-World-For-Us/logger_http"

  def project do
    [
      app: :logger_http,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),

      # Hex
      description: "An HTTP logger handler for Elixir applications",
      package: [
        links: %{"GitHub" => @url}
      ],

      # Dialyzer
      dialyzer: [
        # Put the project-level PLT in the priv/ directory (instead of the default _build/ location)
        # for the CI to be able to cache it between builds
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LoggerHTTP.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_options, "~> 1.0"},
      {:req, "~> 0.5", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "LoggerHTTP",
      source_ref: "v#{@version}",
      source_url: @url
    ]
  end
end
