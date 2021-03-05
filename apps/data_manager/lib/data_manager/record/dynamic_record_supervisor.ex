defmodule DataManager.Record.DynamicRecordSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_recording(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.info("Starting recording on #{symbol}")
        {:ok, _pid} = start_recorder(symbol)

      pid ->
        Logger.warn("Recording on #{symbol} already started")
        {:ok, pid}
    end
  end

  def stop_recording(symbol) when is_binary(symbol) do
    # This is something that we should take into account during the development
    # Do we kill the recording process when the trading halts?
    # We do want to keep track of the trading history and in that case the recording should continue
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("Recording on #{symbol} already stopped")

      pid ->
        Logger.info("Stopping recording on #{symbol}")
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
    Process.whereis(:"Elixir.DataManager.Record.Subscriber-#{symbol}")
  end

  defp start_recorder(symbol) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {DataManager.Record.Subscriber, symbol}
    )
  end
end
