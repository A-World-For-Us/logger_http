defmodule LoggerHTTP.Sender do
  @moduledoc false

  use GenServer

  ## Sender pool public API

  @spec start_pool(map()) :: DynamicSupervisor.on_start_child()
  def start_pool(config) do
    DynamicSupervisor.start_child(
      LoggerHTTP.DynamicSupervisor,
      {PartitionSupervisor,
       name: LoggerHTTP.SenderSupervisor,
       child_spec: child_spec(config),
       partitions: config.pool_size}
    )
  end

  @spec stop_pool(pid()) :: :ok | {:error, :not_found}
  def stop_pool(pid) do
    DynamicSupervisor.terminate_child(LoggerHTTP.DynamicSupervisor, pid)
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  ## Sender public API

  @spec send_async(:unicode.chardata()) :: :ok
  def send_async(log_line) do
    GenServer.cast(random_partition(), {:send_log, log_line})
  end

  defp random_partition do
    nb_partitions = PartitionSupervisor.partitions(LoggerHTTP.SenderSupervisor)
    random_index = Enum.random(1..nb_partitions)
    {:via, PartitionSupervisor, {LoggerHTTP.SenderSupervisor, random_index}}
  end

  ## GenServer callbacks

  defstruct [:config]

  @impl GenServer
  def init(config) do
    {:ok, %__MODULE__{config: config}}
  end

  @impl GenServer
  def handle_cast({:send_log, log_line}, state) do
    send_log!(log_line, state)
    {:noreply, state}
  end

  defp send_log!(log_line, state) do
    # TODO configure http verb
    # TODO handle errors
    # TODO allow other HTTP adapters, make Req dependency optional
    Req.post!(state.config.url, body: log_line)
  end
end
