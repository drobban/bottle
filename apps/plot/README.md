# Plot

Implements plotter for symbol.
To start/stop plotting use 

``` elixir

Plot.start_plotting(symbol)
Plot.stop_plotting(symbol)

```

Plot.start_plotting/1 subcribes to symbol trade stream and plots latest trading price and 3 kinds of moving avrages
short ma, long ma, and 24hour ma.

Plot.start_plotting/4 subcribes to symbol trade stream, uses the three fns to calculate custom moving avrages instead of the default fns.
