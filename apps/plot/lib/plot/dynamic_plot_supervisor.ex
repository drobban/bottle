defmodule Plot.DynamicPlotSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_plotting(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.info("Starting plotting on #{symbol}")
        {:ok, _pid} = start_plotter(symbol)

      pid ->
        Logger.warn("Plotter on #{symbol} already started")
        {:ok, pid}
    end
  end

  def stop_plotting(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("Plotting on #{symbol} already stopped")

      pid ->
        Logger.info("Stopping plotter on #{symbol}")
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
    Process.whereis(:"Elixir.Plot.Subscriber-#{symbol}")
  end

  defp start_plotter(symbol) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Plot.Subscriber, symbol}
    )
  end
end
