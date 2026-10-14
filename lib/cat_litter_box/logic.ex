defmodule CatLitterBox.Logic do
  @moduledoc "The program's logic: the weights and the socket, and the litter box's faults."

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

  # Tells on ntfy when the litter box has stopped. It sends no fault of its own, but a box that has
  # stopped stays paused: on 12 to 13 October 2026 it tried to reset every 30 minutes all night and
  # paused again each time, until the drawer was opened. A pause of a few seconds is normal, as when a
  # cat comes in while it cleans, so it is a fault after 10 minutes. After one notice none comes for
  # 6 hours, as the pulse runs its time whatever its input does.
  xignal fault(state) do
    stopped(state)
    |> do_on_flank(fn -> CatLitterBox.Ntfy.send("Kattedoen har stoppet (#{state})") end)
  end

  # True from 10 minutes into a pause, for 6 hours.
  xignal stopped(state) do
    stuck = ton(state in ["Reset_Pause", "Clean_Pause"], ~t(10m))
    tp(stuck, ~t(6h))
  end
end
