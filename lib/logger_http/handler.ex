defmodule LoggerHTTP.Handler do
  @options_schema NimbleOptions.new!(
                    url: [
                      type: :string,
                      required: true,
                      doc: "The HTTP endpoint to send logs to."
                    ],
                    adapter: [
                      type: {:or, [:atom, :keyword_list, {:tuple, [:atom, :keyword_list]}]},
                      default: {LoggerHTTP.Adapter.Req, []},
                      doc: """
                      Configuration for the adapter module, used both to send logs and
                      handle errors.

                      The value can be one of the following:
                      - a keyword list to configure the default adapter `LoggerHTTP.Adapter.Req`,
                      - a module implementing the`LoggerHTTP.Adapter` behaviour to use a
                      custom adapter,
                      - a 2-tuple containing a module and a keyword list to use a configured
                      custom adapter.

                      The configuration is validated by the callback
                      `c:LoggerHTTP.Adapter.cast_options/1` of the adapter.
                      """
                    ],
                    batch_size: [
                      type: :integer,
                      default: 10,
                      doc: """
                      The maximum number of logs to queue before making an HTTP request.
                      If the timeout configured by `:batch_timeout` is reached before the
                      queue as reached the configured size, less logs will be sent. Setting
                      this parameter to 1 will effectively disable batching.
                      """
                    ],
                    batch_timeout: [
                      type: :integer,
                      default: 5000,
                      doc: """
                      The maximum time to wait before sending a batch of logs, in milliseconds.
                      If the queue reaches the size configured by `batch_size` before this
                      timeout, the logs will be sent. This parameter is only used when
                      `batch_size` is greater than 1. It can also be disabled by settings the
                      value to `0`.
                      """
                    ],
                    pool_size: [
                      type: :integer,
                      doc: """
                      LoggerHTTP uses a pool of GenServers to make HTTP requests. The log
                      are evenly distributed among the processes in the pool. This option
                      allows you to configure the size of the pool.

                      The default is the result of `max(10, System.schedulers_online())`.
                      """
                    ],
                    sync_threshold: [
                      type: :integer,
                      default: 300,
                      doc: """
                      The maximum of queued logs before switching to synchronous mode.
                      In synchronous mode, the logger will await for logs to be sent
                      before returning control to the caller. This option, along with
                      `drop_threshold`, effectively implements **overload protection**.
                      """
                    ],
                    drop_threshold: [
                      type: :integer,
                      default: 2000,
                      doc: """
                      The maximum of queued logs before dropping logs. This option, along
                      with `sync_threshold`, effectively implements **overload protection**.
                      """
                    ]
                  )

  @moduledoc """
  A configurable [`:logger` handler](https://www.erlang.org/doc/apps/kernel/logger_chapter.html#handlers)
  that sends logged messages through HTTP.

  ## Features

  This logger handler provides the features listed here.

  ### Overload protection

  This handler has built-in *[overload protection](https://www.erlang.org/doc/apps/kernel/logger_chapter.html#protecting-the-handler-from-overload)*
  via the `:sync_threshold` and `:drop_threshold` configuration options. Under normal
  circumstances, the logs are sent asynchronously to the HTTP endpoint, returning control
  to the caller immediately. However, if the number of queued logs exceeds the configured
  `:sync_threshold`, the handler will switch to synchronous mode, blocking the logging
  process until the logs are sent. Moreover, if the number of queued logs exceeds the
  `:drop_threshold`, the handler will start dropping logs to prevent the system from
  becoming unresponsive.

  > #### Choosing the right values {: .warning}
  >
  > Since sending the logs is batched and there is a pool of processes, it is not abnormal
  > to have a few logs queued. With the default configuration, `:batch_size` * `:pool_size`
  > means at least a hundred logs can be queued before being sent. Keep this in mind when
  > overriding the defaults, or you might end up in sync or drop mode too early!

  ## Configuration

  This handler supports the following configuration options:

  #{NimbleOptions.docs(@options_schema)}
  """

  alias LoggerHTTP.Sender

  # The config for the logger handler
  defstruct [
    :supervisor_pid,

    # Configuration from user options
    :url,
    :adapter,
    :batch_size,
    :batch_timeout,
    :pool_size,
    :sync_threshold,
    :drop_threshold
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
    config = handler_config.config

    log_line = format_log_event(log_event, handler_config.formatter)

    case Sender.get_queued_logs_count() do
      count when count >= config.drop_threshold ->
        :dropped

      count when count >= config.sync_threshold ->
        Sender.send_sync(log_line)

      _count ->
        Sender.send_async(log_line)
    end

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
      |> Map.update!(:adapter, &cast_adapter/1)

    struct!(existing_config, validated_config)
  end

  defp cast_adapter(adapter_or_options) do
    {module, options} =
      case adapter_or_options do
        {_module, _options} = adapter -> adapter
        adapter when is_atom(adapter) -> {adapter, []}
        options when is_list(options) -> {LoggerHTTP.Adapter.Req, options}
      end

    Code.ensure_loaded!(module)

    validated_options =
      if function_exported?(module, :cast_options, 1),
        do: module.cast_options(options),
        else: options

    {module, validated_options}
  end

  defp start_sender_pool(%__MODULE__{} = config) do
    {:ok, supervisor_pid} = Sender.start_pool(config)

    %{config | supervisor_pid: supervisor_pid}
  end
end
