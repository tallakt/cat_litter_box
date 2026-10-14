defmodule CatLitterBox.LogicTest do
  use ExUnit.Case
  import Xignal, only: [sigil_t: 2]
  import Xignal.Testbench

  # The state minute by minute, and the minutes the notice goes out in: a pause that begins in minute
  # 5 has lasted 10 minutes in minute 14, as the timer counts the scan it begins in.
  defp notices(minutes) do
    states = Enum.flat_map(minutes, fn {state, n} -> List.duplicate(state, n) end)
    outs = CatLitterBox.Logic.stopped(feed(states)) |> scans(length(states), ~t(1m))

    for {[false, true], i} <- Enum.with_index(Enum.chunk_every([false | outs], 2, 1, :discard)),
        do: i
  end

  test "a pause of 10 minutes is a fault, a short one is not" do
    assert notices([{"Standby", 5}, {"Clean_Pause", 1}, {"Cleaning", 2}, {"Standby", 30}]) == []
    assert notices([{"Standby", 5}, {"Reset_Pause", 9}, {"Standby", 30}]) == []
    assert notices([{"Standby", 5}, {"Reset_Pause", 15}, {"Standby", 30}]) == [14]
    assert notices([{"Standby", 5}, {"Clean_Pause", 15}, {"Standby", 30}]) == [14]
  end

  test "after a notice none comes for 6 hours, and then one does" do
    night = [{"Standby", 5}] ++ List.duplicate([{"Resetting", 1}, {"Reset_Pause", 29}], 10)

    assert notices(List.flatten(night) ++ [{"Standby", 60}]) == [15]

    assert notices(List.flatten(night) ++ [{"Standby", 100}, {"Reset_Pause", 20}, {"Standby", 5}]) ==
             [15, 5 + 300 + 100 + 9]
  end
end
