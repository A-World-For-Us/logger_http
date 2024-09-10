defmodule LoggerHTTP.Handler do
  @options_schema NimbleOptions.new!(
                    url: [
                      type: :string,
                      required: true,
                      doc: "The HTTP endpoint to send logs to."
                    ],
                    pool_size: [
                      type: :integer,
                      doc: """
                      LoggerHTTP uses a pool of GenServers to make HTTP requests. The log
                      are evenly distributed among the processes in the pool. This option
                      allows you to configure the size of the pool.

                      The default is the result of `max(10, System.schedulers_online())`.
                      """
                    ]
                  )

  @moduledoc """
  A configurable [`:logger` handler](https://www.erlang.org/doc/apps/kernel/logger_chapter.html#handlers)
  that sends logged messages through HTTP.

  ## Configuration

  This handler supports the following configuration options:

  #{NimbleOptions.docs(@options_schema)}

  ## TODO

  1. batch logs
  2. add overloading protections
    1. count logs
    2. if over limit 1, go sync
    3. if over limit 2, drop logs

  """

  alias LoggerHTTP.Sender

  # The config for the logger handler
  defstruct [
    :supervisor_pid,

    # Configuration from user options
    :url,
    :pool_size
  ]

  ## Callbacks for :logger_handler

  @doc false
  @spec adding_handler(:logger.handler_config()) :: {:ok, :logger.handler_config()}
  def adding_handler(handler_config) do
    # All keys are optional in the handler config
    config = Map.get(handler_config, :config, %{})

    validated_config =
      %__MODULE__{supervisor_pid: nil}
      |> cast_config(config)
      |> start_sender_pool()

    handler_config =
      Map.put(handler_config, :config, validated_config)

    {:ok, handler_config}
  end

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: term()
  def log(log_event, handler_config) do
    log_event
    |> format_log_event(handler_config.formatter)
    |> Sender.send_async()

    :ok
  end

  @doc false
  @spec removing_handler(:logger.handler_config()) :: :ok
  def removing_handler(handler_config) do
    Sender.stop_pool(handler_config.config.supervisor_pid)
  end

  ## Private functions

  defp format_log_event(log_event, {formatter, opts}) do
    formatter.format(log_event, opts)
  end

  defp cast_config(%__MODULE__{} = existing_config, %{} = new_config) do
    validated_config =
      new_config
      |> NimbleOptions.validate!(@options_schema)
      |> Map.put_new_lazy(:pool_size, fn -> max(10, System.schedulers_online()) end)

    struct!(existing_config, validated_config)
  end

  defp start_sender_pool(%__MODULE__{} = config) do
    {:ok, supervisor_pid} = Sender.start_pool(config)

    %{config | supervisor_pid: supervisor_pid}
  end
end
