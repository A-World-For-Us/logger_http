defmodule LoggerHTTP do
  @moduledoc """
  LoggerHTTP is a simple HTTP logger for Elixir applications.

  ## Installation

  Add `logger_http` to your list of dependencies in `mix.exs`. If you plan on using the
  default adapter - which uses the `:req` library - add it to your dependencies too:

      defp deps do
        [
          ...
          {:logger_http, "~> 0.1"},
          {:req, "~> 0.5"}
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

  ## Custom error handling

  The default behaviour when an error occurs when sending the logs is to print the error
  to `:stderr`. The log queue is kept as is and an other attempt to send them is made
  later.

  If you need to customize this behaviour while keeping sending logs as the default adapter
  does, you can create a custom adapter and delegate the `c:LoggerHTTP.Adapter.cast_options/1`
  and `c:LoggerHTTP.Adapter.send_logs/3` callbacks to the default adapter.

      defmodule MyAdapter do
        @behaviour LoggerHTTP.Adapter

        @impl LoggerHTTP.Adapter
        defdelegate cast_options(options), to: LoggerHTTP.Adapter.Req

        @impl LoggerHTTP.Adapter
        defdelegate send_logs(url, logs, options), to: LoggerHTTP.Adapter.Req

        @impl LoggerHTTP.Adapter
        def handle_error(error, options) do
          # Custom error handling
        end
      end

  See `LoggerHTTP.Adapter` for more information on creating custom adapters.
  """
end
