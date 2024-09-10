defmodule LoggerHTTPTest do
  use ExUnit.Case
  doctest LoggerHTTP

  test "greets the world" do
    assert LoggerHTTP.hello() == :world
  end
end
