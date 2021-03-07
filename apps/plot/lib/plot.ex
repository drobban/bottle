defmodule Plot do
  @moduledoc """
  Documentation for `Plot`.
  """
  alias Plot.DynamicPlotSupervisor
  defdelegate start_plotting(symbol), to: DynamicPlotSupervisor
  defdelegate stop_plotting(symbol), to: DynamicPlotSupervisor
end
