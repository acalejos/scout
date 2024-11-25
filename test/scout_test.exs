defmodule ScoutTest do
  use ExUnit.Case
  doctest Scout

  test "greets the world" do
    assert Scout.hello() == :world
  end
end
