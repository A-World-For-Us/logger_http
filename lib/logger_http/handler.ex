defmodule LoggerHTTP.Handler do
  @moduledoc """
  TODO

  1. send logs to endpoint
  2. batch logs
  3. add pool of workers, use PartitionSupervisor?
  3. add overloading protections
    1. count logs
    2. if over limit 1, go sync
    3. if over limit 2, drop logs

  """

  ## Callbacks for :logger_handler

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: term()
  def log(log_event, handler_config) do
    log_line = format_log_event(log_event, handler_config.formatter)
    File.write("./tmp.log", log_line, [:append])

    :ok
  end

  defp format_log_event(log_event, {formatter, opts}) do
    formatter.format(log_event, opts)
  end
end
