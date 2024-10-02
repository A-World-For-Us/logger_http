defmodule LoggerHTTP.HandlerTest do
  use ExUnit.Case, async: true

  alias LoggerHTTP.Handler

  @moduletag :capture_log

  setup do
    handler_name = unique_handler_name()
    on_exit(fn -> :logger.remove_handler(handler_name) end)

    %{handler_name: handler_name}
  end

  test "adding the handler validates the config", %{handler_name: handler_name} do
    assert {:error, {:handler_not_added, {:callback_crashed, {:error, error, _stacktrace}}}} =
             :logger.add_handler(handler_name, Handler, %{
               config: %{}
             })

    assert %NimbleOptions.ValidationError{} = error
    assert error.key == :url
    assert error.message == "required :url option not found, received options: []"

    assert :ok =
             :logger.add_handler(handler_name, Handler, %{
               config: %{
                 url: "http://localhost:4000",
                 adapter: [method: :get],
                 batch_size: 1,
                 batch_timeout: 1,
                 pool_size: 1,
                 sync_threshold: 1,
                 drop_threshold: 1
               }
             })
  end

  test "configuring an adapter validates the adapter config", %{handler_name: handler_name} do
    assert {:error, {:handler_not_added, {:callback_crashed, {:error, error, _stacktrace}}}} =
             :logger.add_handler(handler_name, Handler, %{
               config: %{
                 url: "http://localhost:4000",
                 adapter: [method: "get"]
               }
             })

    assert error.key == :method
    assert error.message == "invalid value for :method option: expected atom, got: \"get\""
  end

  defmodule TestAdapter do
    @behaviour LoggerHTTP.Adapter

    @impl LoggerHTTP.Adapter
    def cast_options(options) do
      if options[:foo] == :bar do
        raise "invalid value for :foo option"
      end

      options
    end

    @impl LoggerHTTP.Adapter
    defdelegate send_logs(url, logs, options), to: LoggerHTTP.Adapter.Req

    @impl LoggerHTTP.Adapter
    defdelegate handle_error(error, options), to: LoggerHTTP.Adapter.Req
  end

  test "configuring a custom adapter validates its config", %{handler_name: handler_name} do
    assert {:error, {:handler_not_added, {:callback_crashed, {:error, error, _stacktrace}}}} =
             :logger.add_handler(handler_name, Handler, %{
               config: %{
                 url: "http://localhost:4000",
                 adapter: {TestAdapter, [foo: :bar]}
               }
             })

    assert error.message == "invalid value for :foo option"
  end

  test "adding the handler starts the sender pool", %{handler_name: handler_name} do
    :logger.add_handler(handler_name, Handler, %{
      config: %{url: "http://localhost:4000", pool_size: 2}
    })

    assert pid = Process.whereis(LoggerHTTP.SenderSupervisor)
    assert is_pid(pid)
    assert PartitionSupervisor.partitions(LoggerHTTP.SenderSupervisor) == 2
  end

  test "sending logs queues them", %{handler_name: handler_name} do
    :logger.add_handler(handler_name, Handler, %{
      level: :info,
      config: %{url: "http://localhost:4000", drop_threshold: 2, pool_size: 1}
    })

    [child] = PartitionSupervisor.which_children(LoggerHTTP.SenderSupervisor)
    {0, genserver_pid, :worker, [LoggerHTTP.Sender]} = child

    Logger.bare_log(:info, "foo")
    # Not accounted for since it's below the expected level
    Logger.bare_log(:debug, "bar")
    Logger.bare_log(:info, "foobar")

    state = :sys.get_state(genserver_pid)
    assert [msg2, msg1] = state.queue
    assert ~c"foo" in msg1
    assert ~c"foobar" in msg2
  end

  test "removing the handler stops the sender pool", %{handler_name: handler_name} do
    :logger.add_handler(handler_name, Handler, %{
      config: %{url: "http://localhost:4000"}
    })

    :logger.remove_handler(handler_name)

    refute Process.whereis(LoggerHTTP.SenderSupervisor)
  end

  defp unique_handler_name do
    i = System.unique_integer()
    String.to_atom("test_http_handler_#{i}")
  end
end
