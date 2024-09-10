defmodule LoggerHTTP.Handler do
  @options_schema NimbleOptions.new!(
                    url: [
                      type: :string,
                      required: true,
                      doc: "The HTTP endpoint to send logs to."
                    ]
                  )

  @moduledoc """
  A configurable [`:logger` handler](https://www.erlang.org/doc/apps/kernel/logger_chapter.html#handlers)
  that sends logged messages through HTTP.

  ## Configuration

  This handler supports the following configuration options:

  #{NimbleOptions.docs(@options_schema)}

  ## TODO

  2. batch logs
  3. add pool of workers, use PartitionSupervisor?
  3. add overloading protections
    1. count logs
    2. if over limit 1, go sync
    3. if over limit 2, drop logs

  """

  alias LoggerHTTP.Sender

  # The config for the logger handler
  defstruct [
    :url
  ]

  ## Callbacks for :logger_handler

  @doc false
  @spec adding_handler(:logger.handler_config()) :: {:ok, :logger.handler_config()}
  def adding_handler(handler_config) do
    # All keys are optional in the handler config
    config = Map.get(handler_config, :config, %{})

    handler_config = Map.put(handler_config, :config, cast_config(%__MODULE__{}, config))

    {:ok, handler_config}
  end

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: term()
  def log(log_event, handler_config) do
    log_event
    |> format_log_event(handler_config.formatter)
    |> Sender.send_async(handler_config)

    :ok
  end

  defp format_log_event(log_event, {formatter, opts}) do
    formatter.format(log_event, opts)
  end

  defp cast_config(%__MODULE__{} = existing_config, %{} = new_config) do
    validated_config =
      new_config
      |> Map.to_list()
      |> NimbleOptions.validate!(@options_schema)

    struct!(existing_config, validated_config)
  end
end
