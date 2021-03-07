defmodule Plot.Subscriber do
  use GenServer, restart: :temporary

  require Logger

  defmodule State do
    defstruct [:symbol, :trades]
  end

  defp set_tick() do
    Process.send_after(self(), :plot, 5_000)
  end

  def start_link(symbol) do
    Logger.debug("Starting link: #{__MODULE__}-#{symbol}")

    GenServer.start_link(__MODULE__, %State{symbol: symbol, trades: []},
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def init(%State{symbol: symbol, trades: _trades} = state) do
    symbol = String.downcase(symbol)
    Streamer.start_streaming(symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    set_tick()

    {:ok, state}
  end

  def handle_info(:plot, state) do
    dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)

    if !Enum.empty?(state.trades) do
      try do
        Gnuplot.plot(
          [
            [:set, :term, :pngcairo],
            [:set, :output, "/tmp/#{state.symbol}.png"],
            [:plot, "-", :with, :lines, :title, "Binance trade since #{DateTime.to_iso8601(dt)}"]
          ],
          [Enum.to_list(state.trades)]
        )
      rescue
        e in MatchError -> "#{inspect(e)}"
      end
    end

    set_tick()
    {:noreply, state}
  end

  def handle_info(%Streamer.Binance.TradeEvent{trade_time: t_time, price: price}, state) do
    {price, _} = Float.parse(price)
    t = [[t_time, price]] ++ state.trades

    trades =
      Enum.filter(t, fn e ->
        [time, _price] = e
        dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
        time > DateTime.to_unix(dt, :millisecond)
      end)

    new_state = %{state | trades: trades}

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
