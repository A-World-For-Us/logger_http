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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_options, "~> 1.0"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
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
