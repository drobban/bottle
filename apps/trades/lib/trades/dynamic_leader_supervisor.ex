defmodule Trades.DynamicLeaderSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_trading(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.info("Starting trading on #{symbol}")
        {:ok, _pid} = start_trader(symbol)

      pid ->
        Logger.warn("Trading on #{symbol} already started")
        {:ok, pid}
    end
  end

  def stop_trading(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("Trading on #{symbol} already stopped")

      pid ->
        Logger.info("Stopping trading on #{symbol}")
        Streamer.stop_streaming(symbol)

        :ok =
          DynamicSupervisor.terminate_child(
            __MODULE__,
            pid
          )

        {:ok, symbol}
    end
  end

  defp get_pid(symbol) do
    Process.whereis(:"Elixir.Trades.Leader-#{symbol}")
  end

  defp start_trader(symbol) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Trades.Leader, symbol}
    )
  end
end
