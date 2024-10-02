defmodule LoggerHTTP.Sender do
  @moduledoc false

  use GenServer

  ## Sender pool public API

  @queued_logs_key {__MODULE__, :queued_logs}

  @spec start_pool(map()) :: DynamicSupervisor.on_start_child()
  def start_pool(config) do
    queued_logs_counter = :counters.new(1, [:write_concurrency])
    :persistent_term.put(@queued_logs_key, queued_logs_counter)

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
    :persistent_term.erase(@queued_logs_key)

    DynamicSupervisor.terminate_child(LoggerHTTP.DynamicSupervisor, pid)
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @spec increase_queued_logs_counter() :: :ok
  defp increase_queued_logs_counter do
    counter = :persistent_term.get(@queued_logs_key)
    :counters.add(counter, 1, 1)
  end

  @spec decrease_queued_logs_counter(pos_integer()) :: :ok
  defp decrease_queued_logs_counter(decr) do
    counter = :persistent_term.get(@queued_logs_key)
    :counters.sub(counter, 1, decr)
  end

  @doc """
  Returns the number of logs currently queued for sending.
  """
  @spec get_queued_logs_count() :: non_neg_integer()
  def get_queued_logs_count do
    counter = :persistent_term.get(@queued_logs_key)
    :counters.get(counter, 1)
  end

  ## Sender public API

  @spec send_async(:unicode.chardata()) :: :ok
  def send_async(log_line) do
    increase_queued_logs_counter()
    GenServer.cast(random_partition(), {:send_log, log_line})
  end

  @spec send_sync(binary()) :: :ok
  def send_sync(log_line) do
    increase_queued_logs_counter()
    :ok = GenServer.call(random_partition(), {:send_log, log_line}, 30_000)
  end

  defp random_partition do
    nb_partitions = PartitionSupervisor.partitions(LoggerHTTP.SenderSupervisor)
    random_index = Enum.random(1..nb_partitions)
    {:via, PartitionSupervisor, {LoggerHTTP.SenderSupervisor, random_index}}
  end

  ## GenServer callbacks

  defstruct [:config, :queue, :counter, :timeout_ref, :callers]

  @impl GenServer
  def init(config) do
    state = %__MODULE__{
      config: config,
      queue: [],
      counter: 0,
      timeout_ref: nil,
      callers: []
    }

    {:ok, state, {:continue, :start_timer}}
  end

  @impl GenServer
  def handle_cast({:send_log, log_line}, state) do
    state
    |> enqueue_log(log_line)
    |> reply_to_log_request()
  end

  @impl GenServer
  def handle_call({:send_log, log_line}, from, state) do
    state
    |> enqueue_log(log_line)
    |> add_caller(from)
    |> reply_to_log_request()
  end

  defp enqueue_log(state, log_line) do
    queue = [log_line | state.queue]
    counter = state.counter + 1

    %{state | queue: queue, counter: counter}
  end

  defp add_caller(state, caller) do
    callers = [caller | state.callers]
    %{state | callers: callers}
  end

  defp reply_to_log_request(state) do
    if state.counter >= state.config.batch_size do
      {:noreply, state, {:continue, :process_queue}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:process_queue, state) do
    {:noreply, state, {:continue, :process_queue}}
  end

  @impl GenServer
  def handle_continue(:start_timer, state) do
    batch_timeout = state.config.batch_timeout

    ref =
      if batch_timeout > 0 do
        Process.send_after(self(), :process_queue, batch_timeout)
      end

    {:noreply, %{state | timeout_ref: ref}}
  end

  def handle_continue(:process_queue, state) do
    if state.timeout_ref != nil do
      # Do not set `:timeout_ref` to nil, the `:start_timer` continue
      # will override its value anyway.
      Process.cancel_timer(state.timeout_ref, info: false)
    end

    logs = Enum.reverse(state.queue)
    body = Enum.intersperse(logs, ?\n)

    # TODO configure http verb
    # TODO handle errors
    # TODO allow other HTTP adapters, make Req dependency optional
    Req.post!(state.config.url, body: body)

    decrease_queued_logs_counter(state.counter)
    Enum.each(state.callers, &GenServer.reply(&1, :ok))

    new_state = %{state | queue: [], counter: 0, callers: []}
    {:noreply, new_state, {:continue, :start_timer}}
  end
end
