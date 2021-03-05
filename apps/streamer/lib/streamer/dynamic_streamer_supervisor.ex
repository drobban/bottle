defmodule Streamer.DynamicStreamerSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_streaming(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.info("Starting streaming on #{symbol}")
        {:ok, _pid} = start_streamer(symbol)

      pid ->
        Logger.warn("Streaming on #{symbol} already started")
        {:ok, pid}
    end
  end

  def stop_streaming(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("Streaming on #{symbol} already stopped")

      pid ->
        Logger.info("Stopping streaming on #{symbol}")

        :ok =
          DynamicSupervisor.terminate_child(
            __MODULE__,
            pid
          )

        {:ok, symbol}
    end
  end

  defp get_pid(symbol) do
    Process.whereis(:"Elixir.Streamer.Binance-#{symbol}")
  end

  defp start_streamer(symbol) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Streamer.Binance, symbol}
    )
  end
end
