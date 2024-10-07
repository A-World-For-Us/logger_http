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
      aliases: aliases(),
      deps: deps(),
      docs: docs(),

      # Hex
      description: "An HTTP logger handler for Elixir applications",
      package: package(),

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

  defp aliases do
    [
      release: [
        "git_ops.release --yes"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_options, "~> 1.0"},
      {:req, "~> 0.5", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:git_ops, "~> 2.6", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "LoggerHTTP",
      extras: ["CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @url
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @url,
        "Changelog" => "#{@url}/blob/#{@version}/CHANGELOG.md"
      }
    ]
  end
end
