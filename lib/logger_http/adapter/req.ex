defmodule LoggerHTTP.Adapter.Req do
  @options_schema NimbleOptions.new!(
                    method: [
                      type: :atom,
                      default: :post,
                      doc: "The HTTP method to use to send logs."
                    ],
                    separator: [
                      type: :any,
                      default: ?\n,
                      doc: "The separator to interleave logs with. Can be any iodata value."
                    ],
                    error_device: [
                      type: {:or, [:atom, :pid]},
                      default: :stderr,
                      doc: "The device to output errors to."
                    ]
                  )

  @moduledoc """
  An HTTP adapter for LoggerHTTP that uses the `:req` library to send logs, and
  outputs errors to `:stderr` by default, or any device.

  ## Usage

  This adapter needs the `:req` library to be part of your dependencies. Add it
  to your `mix.exs` file if it is not already.

      defp deps do
        [
          ...
          {:req, "~> 0.5"}
        ]
      end

  ## Configuration

  This adapter supports the following configuration options:

  #{NimbleOptions.docs(@options_schema)}
  """

  @behaviour LoggerHTTP.Adapter

  @doc false
  @impl LoggerHTTP.Adapter
  def cast_options(options) do
    if not Code.ensure_loaded?(Req) do
      raise "LoggerHTTP.Adapter.Req requires the `:req` library to be loaded"
    end

    NimbleOptions.validate!(options, @options_schema)
  end

  @doc false
  @impl LoggerHTTP.Adapter
  def send_logs(url, logs, options) do
    separator = Keyword.fetch!(options, :separator)
    method = Keyword.fetch!(options, :method)

    body = Enum.intersperse(logs, separator)

    with {:ok, _response} <- Req.request(url: url, method: method, body: body) do
      :ok
    end
  end

  @doc false
  @impl LoggerHTTP.Adapter
  def handle_error(error, options) do
    device = Keyword.fetch!(options, :error_device)

    IO.puts(device, [~c"ERROR - ", inspect(error)])
  end
end
