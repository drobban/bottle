defmodule Trades do
  alias Trades.DynamicLeaderSupervisor
  defdelegate start_trading(symbol), to: DynamicLeaderSupervisor
  defdelegate stop_trading(symbol), to: DynamicLeaderSupervisor
end
