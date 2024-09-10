defmodule LoggerHTTP.Sender do
  @moduledoc false

  @spec send_async(:unicode.chardata(), :logger.handler_config()) :: :ok
  def send_async(log_line, handler_config) do
    url = handler_config.config.url

    # TODO configure http verb
    # TODO handle errors
    # TODO allow other HTTP adapters, make Req dependency optional
    Req.post!(url, body: log_line)
  end
end
