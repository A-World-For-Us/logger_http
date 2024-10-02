defmodule LoggerHTTP.SenderTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias LoggerHTTP.Sender

  @moduletag :capture_log

  defmodule TestOKAdapter do
    @behaviour LoggerHTTP.Adapter

    @impl LoggerHTTP.Adapter
    def send_logs(_url, _logs, _options), do: :ok

    @impl LoggerHTTP.Adapter
    def handle_error(_error, _options) do
      raise "should not be called"
    end
  end

  defmodule TestIOAdapter do
    @behaviour LoggerHTTP.Adapter

    @impl LoggerHTTP.Adapter
    def send_logs(url, logs, _options) do
      IO.puts(["Sending logs to ", url, ": ", logs])
    end

    @impl LoggerHTTP.Adapter
    def handle_error(_error, _options) do
      raise "should not be called"
    end
  end

  describe "start_pool/1" do
    setup :sender_pool

    @tag sender_pool: :ignore
    test "starts the sender pool" do
      {:ok, pid} = Sender.start_pool(config_fixture(pool_size: 2))
      defer_stop_pool(pid)

      assert Process.alive?(pid)

      # The supervisor should have the configured number of children
      assert PartitionSupervisor.partitions(LoggerHTTP.SenderSupervisor) == 2

      # The queued logs counter should be initialized
      counter = :persistent_term.get({Sender, :queued_logs})
      assert :counters.get(counter, 1) == 0
    end

    @tag sender_pool: []
    test "cannot be started twice", %{pool_pid: pool_pid} do
      assert {:error, {:already_started, ^pool_pid}} =
               Sender.start_pool(config_fixture())
    end
  end

  describe "stop_pool/1" do
    setup :sender_pool

    @tag sender_pool: []
    test "stops the sender pool", %{pool_pid: pool_pid} do
      assert :ok = Sender.stop_pool(pool_pid)

      refute Process.alive?(pool_pid)
      assert {:error, :not_found} = Sender.stop_pool(pool_pid)

      # The queued logs counter should be removed
      assert :persistent_term.get({Sender, :queued_logs}, :not_found) == :not_found
    end

    @tag sender_pool: :ignore
    test "returns not found if the process isn't the pool" do
      assert {:error, :not_found} = Sender.stop_pool(self())
    end
  end

  defp sender_pool(%{sender_pool: sender_pool}) do
    pool_pid =
      case sender_pool do
        opts when is_list(opts) -> start_pool(opts)
        :ignore -> nil
      end

    %{pool_pid: pool_pid}
  end

  describe "get_queued_logs_count/0" do
    setup :logger_handler

    @tag logger_handler: [pool_size: 1]
    test "returns the number of logs currently queued for sending" do
      for idx <- 0..9 do
        Logger.bare_log(:info, [~c"message ", idx + ?0])
      end

      assert Sender.get_queued_logs_count() == 10
    end

    @tag logger_handler: [pool_size: 10]
    test "works accross multiple nodes" do
      for idx <- 0..9 do
        Logger.bare_log(:info, [~c"message ", idx + ?0])
      end

      assert Sender.get_queued_logs_count() == 10
    end
  end

  describe "send_async/1" do
    setup :logger_handler

    @tag logger_handler: [pool_size: 1]
    test "increases the global queued logs counter" do
      :ok = Sender.send_async(~c"log line 1")

      assert Sender.get_queued_logs_count() == 1

      for idx <- 2..4 do
        :ok = Sender.send_async([~c"log line ", idx + ?0])
      end

      assert Sender.get_queued_logs_count() == 4
    end

    @tag logger_handler: [pool_size: 1]
    test "enqueues the logs in the sender" do
      for idx <- 1..3 do
        :ok = Sender.send_async([~c"log line ", idx + ?0])
      end

      [pid] = senders_pid()
      state = :sys.get_state(pid)

      assert state.counter == 3

      assert state.queue == [
               [~c"log line ", ?3],
               [~c"log line ", ?2],
               [~c"log line ", ?1]
             ]
    end
  end

  describe "send_sync/1" do
    setup :logger_handler

    @tag logger_handler: [adapter: {TestOKAdapter, []}, pool_size: 1]
    test "waits for the queue to be processed to return to caller" do
      current = self()

      spawn(fn ->
        :ok = Sender.send_sync(~c"log line 1")
        send(current, :test_passed)
      end)

      [sender_pid] = senders_pid()
      state = sleep_until_caller_available(sender_pid)

      {:noreply, _state, _continue} = Sender.handle_continue(:process_queue, state)

      assert_receive :test_passed
    end
  end

  defp sleep_until_caller_available(sender_pid) do
    state = :sys.get_state(sender_pid)

    case state.callers do
      [] ->
        Process.sleep(50)
        sleep_until_caller_available(sender_pid)

      _other ->
        state
    end
  end

  defp logger_handler(%{logger_handler: logger_handler}) do
    case logger_handler do
      opts when is_list(opts) -> add_logger_handler(opts)
      :ignore -> :ok
    end
  end

  ## GenServer callbacks

  describe "init/1" do
    test "initializes the GenServer state with the provided configuration" do
      config = config_fixture()

      # The GenServer should continue to start the timeout timer
      assert {:ok, state, {:continue, :start_timer}} = Sender.init(config)

      # The state should be initialized with the provided configuration
      assert state.config == config
      assert state.queue == []
      assert state.counter == 0
      assert state.timeout_ref == nil
      assert state.callers == []
    end
  end

  describe "handle_cast/2 with `:send_log`" do
    setup :sender_state

    test "add the log line to the state", %{state: state} do
      {:noreply, state} = Sender.handle_cast({:send_log, ~c"log line 1"}, state)

      assert state.counter == 1
      assert state.queue == [~c"log line 1"]
    end

    @tag sender_state: [batch_size: 2]
    test "if the counter is above batch size, continue to process the queue", %{state: state} do
      {:noreply, state} = Sender.handle_cast({:send_log, ~c"log line 1"}, state)

      assert {:noreply, state, {:continue, :process_queue}} =
               Sender.handle_cast({:send_log, ~c"log line 2"}, state)

      assert state.counter == 2
    end
  end

  describe "handle_call/2 with `:send_log`" do
    setup :sender_state

    test "add the log line to the state", %{state: state} do
      from = {self(), make_ref()}
      {:noreply, state} = Sender.handle_call({:send_log, ~c"log line 1"}, from, state)

      assert state.counter == 1
      assert state.queue == [~c"log line 1"]
      assert state.callers == [from]
    end

    @tag sender_state: [batch_size: 2]
    test "if the counter is above batch size, continue to process the queue", %{state: state} do
      {:noreply, state} =
        Sender.handle_call({:send_log, ~c"log line 1"}, {self(), make_ref()}, state)

      assert {:noreply, state, {:continue, :process_queue}} =
               Sender.handle_call({:send_log, ~c"log line 2"}, {self(), make_ref()}, state)

      assert state.counter == 2
    end
  end

  describe "handle_info/2 with `:process_queue`" do
    setup :sender_state

    test "continues to process the queue", %{state: state} do
      assert {:noreply, ^state, {:continue, :process_queue}} =
               Sender.handle_info(:process_queue, state)
    end
  end

  describe "handle_continue/2 with `:start_timer`" do
    setup :sender_state

    @tag sender_state: [batch_timeout: 1000]
    test "starts the timeout timer", %{state: state} do
      {:noreply, state} = Sender.handle_continue(:start_timer, state)

      assert state.timeout_ref != nil

      timer_value = Process.read_timer(state.timeout_ref)
      assert is_integer(timer_value) and timer_value > 0 and timer_value <= 1000
    end

    @tag sender_state: [batch_timeout: 0]
    test "does not start the timer if the config is `0`", %{state: state} do
      {:noreply, state} = Sender.handle_continue(:start_timer, state)

      assert state.timeout_ref == nil
    end
  end

  describe "handle_continue/2 with `:process_queue`" do
    setup :sender_state

    @tag sender_state: [adapter: {TestOKAdapter, []}]
    test "cancel the timeout timer and continues to restart it", %{state: state} do
      {:noreply, state} = Sender.handle_continue(:start_timer, state)

      assert {:noreply, state, {:continue, :start_timer}} =
               Sender.handle_continue(:process_queue, state)

      assert Process.read_timer(state.timeout_ref) == false
    end

    @tag sender_state: [adapter: {TestIOAdapter, []}]
    test "sends the logs", %{state: state} do
      counter = :persistent_term.get({Sender, :queued_logs})
      :counters.add(counter, 1, 2)

      {:noreply, state} = Sender.handle_cast({:send_log, ~c"log line 1"}, state)
      {:noreply, state} = Sender.handle_cast({:send_log, ~c"log line 2"}, state)
      ref_log3 = make_ref()

      {:noreply, state} =
        Sender.handle_call({:send_log, ~c"log line 3"}, {self(), ref_log3}, state)

      ref_log4 = make_ref()

      {:noreply, state} =
        Sender.handle_call({:send_log, ~c"log line 3"}, {self(), ref_log4}, state)

      :counters.add(counter, 1, 4)

      {state, output} =
        with_io(fn ->
          {:noreply, state, _continue} = Sender.handle_continue(:process_queue, state)
          state
        end)

      # Empties the log queue
      assert state.queue == []
      assert state.counter == 0
      assert Sender.get_queued_logs_count() == 2

      # Replies to the callers
      assert state.callers == []
      assert_received {^ref_log3, :ok}
      assert_received {^ref_log4, :ok}

      # Outputs the logs to stdio due to the TestIOAdapter
      assert output =~
               "Sending logs to http://localhost:4000: log line 1log line 2log line 3log line 3\n"
    end
  end

  defp add_logger_handler(attrs) do
    config = config_fixture(attrs)

    :ok =
      :logger.add_handler(:test_logger_http, LoggerHTTP.Handler, %{
        level: :info,
        config: config
      })

    :ok = defer_remove_handler(:test_logger_http)
  end

  defp defer_remove_handler(handler_id) do
    on_exit(fn -> :logger.remove_handler(handler_id) end)
  end

  defp start_pool(attrs) do
    config = config_fixture(attrs)

    {:ok, pid} = Sender.start_pool(config)
    defer_stop_pool(pid)

    pid
  end

  defp defer_stop_pool(pid) do
    on_exit(fn -> Sender.stop_pool(pid) end)
  end

  defp senders_pid do
    children = PartitionSupervisor.which_children(LoggerHTTP.SenderSupervisor)
    Enum.map(children, fn {_idx, pid, _type, _modules} -> pid end)
  end

  defp sender_state(context) do
    queued_logs_counter = :counters.new(1, [])
    :persistent_term.put({Sender, :queued_logs}, queued_logs_counter)

    config = config_fixture(Map.get(context, :sender_state, []))
    {:ok, state, _continue} = Sender.init(config)

    %{state: state}
  end

  defp config_fixture(attrs \\ []) do
    # The adapter is not included in the attributes to force the tests
    # using the adapter to explicitely define which one they want to use.
    Enum.into(attrs, %{
      url: "http://localhost:4000",
      batch_size: 10,
      batch_timeout: 5000,
      pool_size: 1,
      sync_threshold: 300,
      drop_threshold: 2000
    })
  end
end
