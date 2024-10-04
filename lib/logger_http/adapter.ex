defmodule LoggerHTTP.Adapter do
  @moduledoc """
  A behaviour module for implementing a custom HTTP adapter for LoggerHTTP.

  The default adapter is `LoggerHTTP.Adapter.Req`.

  To configure a different adapter, implement the `LoggerHTTP.Adapter` behaviour and
  set the `:adapter` option in the logger handler configuration.

      config :my_app, :logger, [
        {:handler, :my_http_handler, LoggerHTTP.Handler, %{
          config: %{
            url: "https://example.com/logs",
            adapter: MyApp.CustomAdapter
          }
        }}
      ]

  > #### Be careful about using Logger in the adapter {: .warning}
  >
  > Since the adapter is called from within a logger handler, it can be very troublesome
  > to use Logger in its callbacks. Doing so can lead to an infinite number of logs being
  > created, the app slowing down, and finally the logger handler crashing and being detached.
  > Try to avoid it, and be careful if you really need it.
  """

  @typedoc """
  The options for the adapter.

  The options are given in the logger handler configuration, then validated using the
  `c:cast_options/1` callback if provided. They are then passed to the other callbacks
  to configure the adapter's behaviour.
  """
  @type options :: keyword()

  @doc """
  Validate and cast the options given to the adapter.

  This callback is called directly when adding the logger. It may raise an exception if
  the passed options are invalid, which will lead to the logger handler failing to be
  added.
  """
  @callback cast_options(options()) :: options()
  @optional_callbacks cast_options: 1

  @doc """
  Send the logs to the given URL.

  This callback should not handle the error directly, but rather return `{:error, reason}`.
  `c:handle_error/2` will then be called with `reason` as its first parameter.
  """
  @callback send_logs(url :: String.t(), logs :: [iodata()], options()) :: :ok | {:error, term()}

  @doc """
  Handle an error that occurred when sending the logs.

  The error can be anything returned by `c:send_logs/3`. When using the default adapter,
  the error is known to be of type `t:Exception.t/0`.
  """
  @callback handle_error(term(), options()) :: term()
end
