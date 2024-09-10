defmodule LoggerHTTP do
  @moduledoc """
  LoggerHTTP is a simple HTTP logger for Elixir applications.

  ## Installation

  Add `logger_http` to your list of dependencies in `mix.exs`:

      defp deps do
        [
          ...
          {:logger_http, "~> 0.1"}
        ]
      end

  ## Usage

  To add the LoggerHTTP handler to your system, see [the documentation for handlers in
  Elixir](https://hexdocs.pm/logger/Logger.html#module-erlang-otp-handlers).

  You can configure the handler in the `:logger` key under your application's configuration,
  potentially alongside other `:logger` handlers:

      config :my_app, :logger, [
        {:handler, :my_http_handler, LoggerHTTP.Handler, %{
          config: %{url: "https://example.com/logs"}
        }}
      ]

  If you do this, then you'll want to add custom handlers in your application's
  `c:Application.start/2` callback if you haven't already:

      def start(_type, _args) do
        Logger.add_handlers(:my_app)

        # ...
      end

  Alternatively, you can skip the `:logger` configuration and add the handler directly to
  your application's `c:Application.start/2` callback:

      def start(_type, _args) do
        :logger.add_handler(:my_http_handler, LoggerHTTP.Handler, %{
          config: %{url: "https://example.com/logs"}
        })

        # ...
      end

  See `LoggerHTTP.Handler` to configure the handler.
  """
end
