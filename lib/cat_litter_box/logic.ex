defmodule CatLitterBox.Logic do
  @moduledoc "The program's logic, as one xignal."

  use Xignal

  # Tells on ntfy which cat it was and its weight when the weight has changed, but at most once a
  # minute: the log keeps every change, the notifications only what the weight settled at. The flanks
  # go with the store the weight is read from, so the runner scans them without a sink.
  #
  # And keeps the socket open: Tuya closes a quiet connection after 5 minutes. Each message Tuya
  # sends is a pulse of `activity_notice`; once none has come for 4 minutes the socket is pinged,
  # and every 4 minutes after that, as the timer starts over in the scan after it fires.
  xignal watch(weight, activity_notice) do
    settled = lossy(weight, min: ~t(1m))

    settled
    |> changed()
    |> do_on_flank(fn -> CatLitterBox.Ntfy.send(CatLitterBox.Cats.weighed(settled)) end)

    pinged = tag(:pinged, prev: true, default: false)

    ton(not activity_notice and not pinged, ~t(4m))
    |> tag(:pinged)
    |> send_on_flank(CatLitterBox.Tuya, :ping)
  end
end
