defmodule DataManagerTest do
  use ExUnit.Case
  doctest DataManager

  test "greets the world" do
    assert DataManager.hello() == :world
  end
end
